import AVFoundation
import Foundation
import NotchyCore

/// Escritor de audio por trozos (`.m4a` AAC) con rotación automática cada minuto o ante reposo/cambio
/// de dispositivo y limpieza de archivos vacíos (GRB-1, GRB-4, GRB-7, RNF-4).
@MainActor
public final class AdaptadorDeEscritorDeAudio: PuertoDeEscritorDeAudio {
    public private(set) var rutasMicrofono: [String] = []
    public private(set) var rutasSistema: [String] = []

    private var carpetaBase: URL?
    private var prefijo = "grabacion"
    private var incluirSistema = false
    private var duracionTrozoSegundos: Double = 60
    private var indiceTrozo = 0

    private var archivoMic: AVAudioFile?
    private var urlMicActual: URL?
    private var framesMicEnTrozo = 0
    private var segundosMicEnTrozo: Double = 0

    private var archivoSistema: AVAudioFile?
    private var urlSistemaActual: URL?
    private var framesSistemaEnTrozo = 0
    private var segundosSistemaEnTrozo: Double = 0

    public init() {}

    public func iniciarSesion(
        carpetaBase: URL,
        prefijo: String,
        incluirSistema: Bool,
        duracionTrozoSegundos: Double = 60
    ) throws {
        _ = finalizarSesion()
        try FileManager.default.createDirectory(at: carpetaBase, withIntermediateDirectories: true)
        self.carpetaBase = carpetaBase
        self.prefijo = prefijo
        self.incluirSistema = incluirSistema
        self.duracionTrozoSegundos = max(5, duracionTrozoSegundos)
        self.indiceTrozo = 1
        self.rutasMicrofono = []
        self.rutasSistema = []
    }

    public func escribir(_ bloque: BloqueDeAudioPCM) throws {
        guard let carpetaBase, !bloque.muestras.isEmpty,
            let buffer = ExtraerMuestrasMono.reconstruirBuffer(de: bloque)
        else { return }

        let duracionBloque = Double(bloque.frames) / max(1, bloque.frecuencia)
        switch bloque.fuente {
        case .microfono:
            if segundosMicEnTrozo >= duracionTrozoSegundos, framesMicEnTrozo > 0 {
                try rotarTrozo()
            }
            if archivoMic == nil {
                let url = carpetaBase.appending(
                    path: String(format: "%@-mic-%03d.m4a", prefijo, max(1, indiceTrozo))
                )
                archivoMic = try Self.abrirArchivo(en: url, frecuencia: bloque.frecuencia)
                urlMicActual = url
                framesMicEnTrozo = 0
                segundosMicEnTrozo = 0
            }
            try archivoMic?.write(from: buffer)
            framesMicEnTrozo += bloque.frames
            segundosMicEnTrozo += duracionBloque
            if let ruta = urlMicActual?.path, !rutasMicrofono.contains(ruta) {
                rutasMicrofono.append(ruta)
            }

        case .sistema:
            guard incluirSistema else { return }
            if segundosSistemaEnTrozo >= duracionTrozoSegundos, framesSistemaEnTrozo > 0 {
                try rotarTrozo()
            }
            if archivoSistema == nil {
                let url = carpetaBase.appending(
                    path: String(format: "%@-sistema-%03d.m4a", prefijo, max(1, indiceTrozo))
                )
                archivoSistema = try Self.abrirArchivo(en: url, frecuencia: bloque.frecuencia)
                urlSistemaActual = url
                framesSistemaEnTrozo = 0
                segundosSistemaEnTrozo = 0
            }
            try archivoSistema?.write(from: buffer)
            framesSistemaEnTrozo += bloque.frames
            segundosSistemaEnTrozo += duracionBloque
            if let ruta = urlSistemaActual?.path, !rutasSistema.contains(ruta) {
                rutasSistema.append(ruta)
            }

        case .marca:
            break
        }
    }

    public func rotarTrozo() throws {
        cerrarTrozoActual()
        if carpetaBase != nil {
            indiceTrozo += 1
        }
    }

    public func finalizarSesion() -> (rutasMicrofono: [String], rutasSistema: [String]) {
        cerrarTrozoActual()
        carpetaBase = nil
        return (rutasMicrofono, rutasSistema)
    }

    private func cerrarTrozoActual() {
        archivoMic = nil
        if let url = urlMicActual, framesMicEnTrozo == 0 {
            try? FileManager.default.removeItem(at: url)
            rutasMicrofono.removeAll { $0 == url.path }
        }
        urlMicActual = nil
        framesMicEnTrozo = 0
        segundosMicEnTrozo = 0

        archivoSistema = nil
        if let url = urlSistemaActual, framesSistemaEnTrozo == 0 {
            try? FileManager.default.removeItem(at: url)
            rutasSistema.removeAll { $0 == url.path }
        }
        urlSistemaActual = nil
        framesSistemaEnTrozo = 0
        segundosSistemaEnTrozo = 0
    }

    private static func abrirArchivo(en url: URL, frecuencia: Double) throws -> AVAudioFile {
        let ajustesAAC: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: frecuencia,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        return try AVAudioFile(
            forWriting: url,
            settings: ajustesAAC,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
    }
}
