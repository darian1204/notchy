import AVFoundation
import FluidAudio
import Foundation
import NotchyCore
import OSLog

/// Adaptador de separación de voces (diarización offline en el dispositivo) con FluidAudio (`OfflineDiarizerManager`).
/// Convierte y concatena los trozos `.m4a` del micrófono a 16 kHz mono Float32 respetando el desfase temporal
/// de cada trozo y guarda los modelos descargados en `Application Support` de Notchy.
public actor AdaptadorDeDiarizacion: PuertoDeDiarizacion {
    private static let frecuenciaObjetivo: Double = 16_000
    private let carpetaModelos: URL?
    private let log = Registro.de(.reuniones)
    private var gestor: OfflineDiarizerManager?
    private var modelosListos = false
    private var diarizando = false

    public init(carpetaModelos: URL? = nil) {
        self.carpetaModelos = carpetaModelos
    }

    public func disponible() async -> Bool {
        true
    }

    public func diarizar(archivos: [URL]) async throws -> [TramoDeHablante] {
        let existentes = archivos.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existentes.isEmpty else { return [] }

        let muestras = try Self.concatenarYConvertirA16kMono(archivos: existentes)
        guard !muestras.isEmpty else { return [] }

        // OfflineDiarizerManager no es Sendable. El actor lo usa de a una reunión a la vez
        // (`diarizando` impide llamadas simultáneas), así que pasarlo fuera del actor es seguro.
        guard !diarizando else { throw NotchyError.datos("Ya se están separando voces de otra reunión.") }
        diarizando = true
        defer { diarizando = false }
        nonisolated(unsafe) let manager = try await asegurarGestorConModelos()
        do {
            let resultado = try await manager.process(audio: muestras)
            return resultado.segments.map { seg in
                TramoDeHablante(
                    hablanteID: seg.speakerId,
                    inicio: Double(seg.startTimeSeconds),
                    fin: Double(seg.endTimeSeconds)
                )
            }
        } catch OfflineDiarizationError.noSpeechDetected {
            return []
        }
    }

    private func asegurarGestorConModelos() async throws -> OfflineDiarizerManager {
        if let gestor, modelosListos {
            return gestor
        }
        let destino: URL
        if let carpetaModelos {
            destino = carpetaModelos
        } else if let rutas = try? RutasDeDatos.porDefecto() {
            destino = rutas.modelos
        } else {
            destino = OfflineDiarizerModels.defaultModelsDirectory()
        }
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)

        let nuevo = OfflineDiarizerManager(config: .default)
        try await nuevo.prepareModels(directory: destino)
        self.gestor = nuevo
        self.modelosListos = true
        return nuevo
    }

    /// Convierte cada trozo `.m4a` a 16 kHz mono Float32 con `AVAudioFile` + `AVAudioConverter`
    /// y los concatena en orden respetando la duración exacta acumulada de cada trozo.
    public static func concatenarYConvertirA16kMono(archivos: [URL]) throws -> [Float] {
        guard
            let formatoDestino = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: frecuenciaObjetivo,
                channels: 1,
                interleaved: false
            )
        else {
            throw NotchyError.datos("No se pudo crear el formato de audio a 16 kHz mono.")
        }

        var muestrasTotales: [Float] = []
        var duracionAcumuladaSegundos: Double = 0

        for url in archivos {
            let archivo = try AVAudioFile(forReading: url)
            let formatoEntrada = archivo.processingFormat
            guard formatoEntrada.sampleRate > 0, archivo.length > 0 else { continue }

            let duracionTrozoSegundos = Double(archivo.length) / formatoEntrada.sampleRate
            let muestrasTrozo = try convertirArchivo(
                archivo,
                formatoEntrada: formatoEntrada,
                formatoDestino: formatoDestino
            )
            muestrasTotales.append(contentsOf: muestrasTrozo)
            duracionAcumuladaSegundos += duracionTrozoSegundos

            // Ajustar la longitud acumulada al desfase temporal real del trozo para no acumular deriva entre trozos.
            let muestrasEsperadas = Int((duracionAcumuladaSegundos * frecuenciaObjetivo).rounded())
            if muestrasTotales.count < muestrasEsperadas {
                muestrasTotales.append(
                    contentsOf: repeatElement(Float(0), count: muestrasEsperadas - muestrasTotales.count)
                )
            } else if muestrasTotales.count > muestrasEsperadas, muestrasEsperadas > 0 {
                muestrasTotales.removeLast(muestrasTotales.count - muestrasEsperadas)
            }
        }

        return muestrasTotales
    }

    private static func convertirArchivo(
        _ archivo: AVAudioFile,
        formatoEntrada: AVAudioFormat,
        formatoDestino: AVAudioFormat
    ) throws -> [Float] {
        let framesPorLectura = AVAudioFrameCount(max(4096, Int(formatoEntrada.sampleRate)))
        guard let bufferEntrada = AVAudioPCMBuffer(pcmFormat: formatoEntrada, frameCapacity: framesPorLectura) else {
            throw NotchyError.datos("No se pudo reservar el buffer de lectura de audio.")
        }

        let ratio = formatoDestino.sampleRate / formatoEntrada.sampleRate
        var salida: [Float] = []
        salida.reserveCapacity(Int((Double(archivo.length) * ratio).rounded(.up)) + 1024)

        if formatoEntrada.sampleRate == formatoDestino.sampleRate,
            formatoEntrada.channelCount == 1,
            formatoEntrada.commonFormat == .pcmFormatFloat32,
            !formatoEntrada.isInterleaved
        {
            while archivo.framePosition < archivo.length {
                let restantes = AVAudioFrameCount(min(archivo.length - archivo.framePosition, Int64(framesPorLectura)))
                do {
                    try archivo.read(into: bufferEntrada, frameCount: restantes)
                } catch {
                    break
                }
                guard bufferEntrada.frameLength > 0, let canal = bufferEntrada.floatChannelData?[0] else { break }
                salida.append(contentsOf: UnsafeBufferPointer(start: canal, count: Int(bufferEntrada.frameLength)))
            }
            return salida
        }

        guard let conversor = AVAudioConverter(from: formatoEntrada, to: formatoDestino) else {
            throw NotchyError.datos("No se pudo crear el conversor de audio a 16 kHz.")
        }
        let capacidadSalida = AVAudioFrameCount((Double(framesPorLectura) * ratio).rounded(.up)) + 1024
        guard let bufferSalida = AVAudioPCMBuffer(pcmFormat: formatoDestino, frameCapacity: capacidadSalida),
            let canalSalida = bufferSalida.floatChannelData?[0]
        else {
            throw NotchyError.datos("No se pudo reservar el buffer de salida a 16 kHz.")
        }

        var finDeArchivo = false
        var leyoAlgunBloque = false
        let archivoUnsafe = archivo
        nonisolated(unsafe) let entradaUnsafe = bufferEntrada

        while !finDeArchivo {
            bufferSalida.frameLength = 0
            var errorConversion: NSError?
            let estado = conversor.convert(to: bufferSalida, error: &errorConversion) { _, estadoEntrada in
                let posicion = archivoUnsafe.framePosition
                guard posicion < archivoUnsafe.length else {
                    finDeArchivo = true
                    estadoEntrada.pointee = .endOfStream
                    return nil
                }
                let restantes = AVAudioFrameCount(min(archivoUnsafe.length - posicion, Int64(framesPorLectura)))
                do {
                    try archivoUnsafe.read(into: entradaUnsafe, frameCount: restantes)
                } catch {
                    // En archivos AAC (.m4a), los últimos frames estimados pueden ser padding del codificador.
                    finDeArchivo = true
                    estadoEntrada.pointee = .endOfStream
                    return nil
                }
                guard entradaUnsafe.frameLength > 0 else {
                    finDeArchivo = true
                    estadoEntrada.pointee = .endOfStream
                    return nil
                }
                leyoAlgunBloque = true
                estadoEntrada.pointee = .haveData
                return entradaUnsafe
            }
            if estado == .error {
                if leyoAlgunBloque { break }
                throw errorConversion ?? NotchyError.datos("Error al convertir trozo de audio a 16 kHz.")
            }
            if bufferSalida.frameLength > 0 {
                salida.append(
                    contentsOf: UnsafeBufferPointer(start: canalSalida, count: Int(bufferSalida.frameLength))
                )
            }
            if estado == .endOfStream {
                break
            }
        }

        return salida
    }
}
