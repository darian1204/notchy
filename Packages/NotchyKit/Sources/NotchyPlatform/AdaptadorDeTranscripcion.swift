import AVFoundation
import Foundation
import NotchyCore
import OSLog
import Speech

/// Adaptador de transcripción en vivo con dos analizadores (`SpeechAnalyzer` + `SpeechTranscriber`),
/// cambio de idioma en caliente (`es-MX` ↔ `en-US`) y retranscripción desde archivos (GRB-3, GRB-4, D-07).
@MainActor
public final class AdaptadorDeTranscripcion: PuertoDeTranscripcion {
    public private(set) var idiomaActivo: IdiomaDeTranscripcion = .espanolMexico
    private let log = Registro.de(.reuniones)
    private var canalMicrofono: CanalDeSpeechTranscriber?
    private var canalSistema: CanalDeSpeechTranscriber?
    private var incluirSistema = false
    private var callbackResultado: (@Sendable (ResultadoDeTranscripcion) -> Void)?

    public init() {}

    public func iniciar(
        idioma: IdiomaDeTranscripcion,
        incluirSistema: Bool,
        alRecibirResultado: @escaping @Sendable (ResultadoDeTranscripcion) -> Void
    ) async throws {
        await detener()
        self.idiomaActivo = idioma
        self.incluirSistema = incluirSistema
        self.callbackResultado = alRecibirResultado

        let mic = CanalDeSpeechTranscriber(fuente: .microfono, alEmitir: alRecibirResultado)
        try await mic.iniciar(identificadorIdioma: idioma.rawValue)
        canalMicrofono = mic

        if incluirSistema {
            let sis = CanalDeSpeechTranscriber(fuente: .sistema, alEmitir: alRecibirResultado)
            try await sis.iniciar(identificadorIdioma: idioma.rawValue)
            canalSistema = sis
        }
    }

    public func alimentar(_ bloque: BloqueDeAudioPCM) {
        guard let buffer = ExtraerMuestrasMono.reconstruirBuffer(de: bloque) else { return }
        switch bloque.fuente {
        case .microfono:
            canalMicrofono?.alimentar(buffer)
        case .sistema:
            canalSistema?.alimentar(buffer)
        case .marca:
            break
        }
    }

    public func cambiarIdioma(_ nuevo: IdiomaDeTranscripcion) async throws {
        guard let callback = callbackResultado else {
            idiomaActivo = nuevo
            return
        }
        try await iniciar(
            idioma: nuevo,
            incluirSistema: incluirSistema,
            alRecibirResultado: callback
        )
    }

    public func detener() async {
        let mic = canalMicrofono
        let sis = canalSistema
        canalMicrofono = nil
        canalSistema = nil
        await mic?.terminar()
        await sis?.terminar()
    }

    public func retranscribir(
        archivos: [(fuente: FuenteDeAudio, url: URL)],
        idioma: IdiomaDeTranscripcion
    ) async throws -> [ResultadoDeTranscripcion] {
        let acumulador = AcumuladorDeResultados()
        for par in archivos where FileManager.default.fileExists(atPath: par.url.path) {
            let canal = CanalDeSpeechTranscriber(fuente: par.fuente) { res in
                guard res.esFinal else { return }
                acumulador.agregar(res)
            }
            try await canal.iniciar(identificadorIdioma: idioma.rawValue)
            if let archivo = try? AVAudioFile(forReading: par.url) {
                let formato = archivo.processingFormat
                let capacidad: AVAudioFrameCount = 4096
                while archivo.framePosition < archivo.length,
                    let buffer = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: capacidad)
                {
                    do {
                        try archivo.read(into: buffer)
                        guard buffer.frameLength > 0 else { break }
                        canal.alimentar(buffer)
                    } catch {
                        log.error(
                            "Error al leer trozo para retranscribir: \(error.localizedDescription, privacy: .public)"
                        )
                        break
                    }
                }
            }
            await canal.terminar()
        }
        return acumulador.todos
    }
}

nonisolated private final class AcumuladorDeResultados: @unchecked Sendable {
    private let lock = NSLock()
    private var lista: [ResultadoDeTranscripcion] = []

    func agregar(_ resultado: ResultadoDeTranscripcion) {
        lock.lock()
        lista.append(resultado)
        lock.unlock()
    }

    var todos: [ResultadoDeTranscripcion] {
        lock.lock()
        defer { lock.unlock() }
        return lista
    }
}

nonisolated final class CanalDeSpeechTranscriber: @unchecked Sendable {
    let fuente: FuenteDeAudio
    private let alEmitir: @Sendable (ResultadoDeTranscripcion) -> Void
    private let lock = NSLock()
    private var conversor: AVAudioConverter?
    private var formatoDestino: AVAudioFormat?
    private var continuacion: AsyncStream<AnalyzerInput>.Continuation?
    private var analizador: SpeechAnalyzer?
    private var tareaResultados: Task<Void, Never>?

    init(
        fuente: FuenteDeAudio,
        alEmitir: @escaping @Sendable (ResultadoDeTranscripcion) -> Void
    ) {
        self.fuente = fuente
        self.alEmitir = alEmitir
    }

    func iniciar(identificadorIdioma: String) async throws {
        guard
            let locale = await SpeechTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: identificadorIdioma)
            )
        else {
            throw NSError(
                domain: "NotchySpeech",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "El idioma \(identificadorIdioma) no está soportado por SpeechTranscriber."
                ]
            )
        }
        let transcriptor = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        if let instalacion = try await AssetInventory.assetInstallationRequest(supporting: [transcriptor]) {
            try await instalacion.downloadAndInstall()
        }
        let analizador = SpeechAnalyzer(modules: [transcriptor])
        let formato = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriptor])
        let (flujo, cont) = AsyncStream<AnalyzerInput>.makeStream()
        lock.withLock {
            self.formatoDestino = formato
            self.continuacion = cont
            self.analizador = analizador
        }
        try await analizador.start(inputSequence: flujo)

        let fuente = self.fuente
        let alEmitir = self.alEmitir
        tareaResultados = Task.detached {
            do {
                for try await r in transcriptor.results {
                    let texto = String(r.text.characters)
                    guard !texto.isEmpty else { continue }
                    alEmitir(
                        ResultadoDeTranscripcion(
                            fuente: fuente,
                            texto: texto,
                            esFinal: r.isFinal
                        )
                    )
                }
            } catch {
                // Fin o cancelación del flujo de transcripción.
            }
        }
    }

    func alimentar(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let formatoDestino, let continuacion else { return }
        if conversor == nil || conversor?.inputFormat != buffer.format {
            conversor = AVAudioConverter(from: buffer.format, to: formatoDestino)
        }
        let capacidad =
            AVAudioFrameCount(
                Double(buffer.frameLength) * formatoDestino.sampleRate / max(1, buffer.format.sampleRate)
            ) + 32
        guard let conversor,
            let convertido = AVAudioPCMBuffer(pcmFormat: formatoDestino, frameCapacity: capacidad)
        else { return }
        var entregado = false
        var err: NSError?
        let estado = conversor.convert(to: convertido, error: &err) { _, estadoEntrada in
            if entregado {
                estadoEntrada.pointee = .noDataNow
                return nil
            }
            entregado = true
            estadoEntrada.pointee = .haveData
            return buffer
        }
        guard estado != .error, convertido.frameLength > 0 else { return }
        continuacion.yield(AnalyzerInput(buffer: convertido))
    }

    func terminar() async {
        let (cont, ana, tarea) = lock.withLock {
            let t = (continuacion, analizador, tareaResultados)
            continuacion = nil
            analizador = nil
            tareaResultados = nil
            return t
        }
        cont?.finish()
        try? await ana?.finalizeAndFinishThroughEndOfInput()
        tarea?.cancel()
    }
}
