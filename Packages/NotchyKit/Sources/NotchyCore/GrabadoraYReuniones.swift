import Foundation

/// Idiomas soportados para la transcripción en vivo y notas de voz (GRB-3, D-07).
public enum IdiomaDeTranscripcion: String, Codable, Sendable, CaseIterable, Identifiable, Equatable {
    case espanolMexico = "es-MX"
    case inglesEstadosUnidos = "en-US"

    public var id: String { rawValue }

    public var etiqueta: String {
        switch self {
        case .espanolMexico: "Español (México)"
        case .inglesEstadosUnidos: "Inglés (EE. UU.)"
        }
    }

    public var etiquetaCorta: String {
        switch self {
        case .espanolMexico: "ES"
        case .inglesEstadosUnidos: "EN"
        }
    }

    public var siguiente: IdiomaDeTranscripcion {
        switch self {
        case .espanolMexico: .inglesEstadosUnidos
        case .inglesEstadosUnidos: .espanolMexico
        }
    }
}

/// Fuente del segmento de audio o marca en una reunión (GRB-3, GRB-8, D-08).
public enum FuenteDeAudio: String, Codable, Sendable, CaseIterable, Equatable {
    case microfono = "yo"
    case sistema = "otros"
    case marca = "marca"

    public var etiqueta: String {
        switch self {
        case .microfono: "Tú"
        case .sistema: "Otros"
        case .marca: "Marca"
        }
    }
}

/// Ciclo de vida de una reunión grabada (GRB-2, GRB-4, RNF-4).
public enum EstadoDeReunion: String, Codable, Sendable, CaseIterable, Equatable {
    case enCurso = "en_curso"
    case pausada = "pausada"
    case finalizada = "finalizada"
    case recuperada = "recuperada"

    public var etiqueta: String {
        switch self {
        case .enCurso: "En curso"
        case .pausada: "En pausa"
        case .finalizada: "Finalizada"
        case .recuperada: "Recuperada"
        }
    }
}

/// Nota de voz rápida con cronómetro y transcripción opcional (GRB-1).
public struct NotaDeVoz: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let creado: Date
    public var titulo: String
    public var duracionSegundos: Double
    public var rutaArchivo: String
    public var transcripcion: String?
    public var idioma: IdiomaDeTranscripcion

    public init(
        id: String = UUID().uuidString,
        creado: Date = .now,
        titulo: String,
        duracionSegundos: Double,
        rutaArchivo: String,
        transcripcion: String? = nil,
        idioma: IdiomaDeTranscripcion = .espanolMexico
    ) {
        self.id = id
        self.creado = creado
        self.titulo = titulo
        self.duracionSegundos = duracionSegundos
        self.rutaArchivo = rutaArchivo
        self.transcripcion = transcripcion
        self.idioma = idioma
    }

    public var urlArchivo: URL {
        URL(fileURLWithPath: rutaArchivo)
    }
}

/// Reunión que graba micrófono y audio del sistema con transcripción en vivo (GRB-2, GRB-4, GRB-7).
public struct ReunionGrabada: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var titulo: String
    public let inicio: Date
    public var fin: Date?
    public var estado: EstadoDeReunion
    public var idioma: IdiomaDeTranscripcion
    public var eventoCalendarioID: String?
    public var rutasAudioMicrofono: [String]
    public var rutasAudioSistema: [String]
    public var desfaseInicialMs: Double?

    public init(
        id: String = UUID().uuidString,
        titulo: String,
        inicio: Date = .now,
        fin: Date? = nil,
        estado: EstadoDeReunion = .enCurso,
        idioma: IdiomaDeTranscripcion = .espanolMexico,
        eventoCalendarioID: String? = nil,
        rutasAudioMicrofono: [String] = [],
        rutasAudioSistema: [String] = [],
        desfaseInicialMs: Double? = nil
    ) {
        self.id = id
        self.titulo = titulo
        self.inicio = inicio
        self.fin = fin
        self.estado = estado
        self.idioma = idioma
        self.eventoCalendarioID = eventoCalendarioID
        self.rutasAudioMicrofono = rutasAudioMicrofono
        self.rutasAudioSistema = rutasAudioSistema
        self.desfaseInicialMs = desfaseInicialMs
    }

    public var duracionSegundos: Double {
        guard let fin else { return max(0, Date.now.timeIntervalSince(inicio)) }
        return max(0, fin.timeIntervalSince(inicio))
    }
}

/// Segmento de transcripción o marca de tiempo de una reunión (GRB-3, GRB-4, GRB-8).
public struct SegmentoDeTranscripcion: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let reunionID: String
    public let fuente: FuenteDeAudio
    public let inicioSegundos: Double
    public var finSegundos: Double
    public var texto: String
    public var confianza: Double?
    public var esFinal: Bool

    public init(
        id: String = UUID().uuidString,
        reunionID: String,
        fuente: FuenteDeAudio,
        inicioSegundos: Double,
        finSegundos: Double,
        texto: String,
        confianza: Double? = nil,
        esFinal: Bool = true
    ) {
        self.id = id
        self.reunionID = reunionID
        self.fuente = fuente
        self.inicioSegundos = inicioSegundos
        self.finSegundos = max(inicioSegundos, finSegundos)
        self.texto = texto
        self.confianza = confianza
        self.esFinal = esFinal
    }

    public var marcaDeTiempoFormateada: String {
        let total = max(0, Int(inicioSegundos.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Regla del glosario de correcciones posteriores (GRB-5, D-09).
public struct EntradaDeGlosario: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var malReconocido: String
    public var correcto: String
    public var activo: Bool

    public init(
        id: String = UUID().uuidString,
        malReconocido: String,
        correcto: String,
        activo: Bool = true
    ) {
        self.id = id
        self.malReconocido = malReconocido
        self.correcto = correcto
        self.activo = activo
    }

    public static let porDefecto: [EntradaDeGlosario] = [
        EntradaDeGlosario(id: "glosario-supabase", malReconocido: "supavase", correcto: "Supabase"),
        EntradaDeGlosario(id: "glosario-opencode", malReconocido: "open code", correcto: "OpenCode"),
        EntradaDeGlosario(id: "glosario-notchy", malReconocido: "notchi", correcto: "Notchy"),
        EntradaDeGlosario(id: "glosario-antigravity", malReconocido: "antigraviti", correcto: "Antigravity"),
    ]
}

/// Aplica el glosario de correcciones sobre fragmentos de transcripción sin depender del sistema (GRB-5, D-09).
public struct CorrectorDeGlosario: Sendable, Equatable {
    public var entradas: [EntradaDeGlosario]

    public init(entradas: [EntradaDeGlosario] = EntradaDeGlosario.porDefecto) {
        self.entradas = entradas
    }

    public func corregir(_ texto: String) -> String {
        guard !texto.isEmpty else { return texto }
        var resultado = texto
        for entrada in entradas where entrada.activo {
            let buscado = entrada.malReconocido.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !buscado.isEmpty else { continue }
            let escapado = NSRegularExpression.escapedPattern(for: buscado)
            let patron = "(?i)\\b\(escapado)\\b"
            if let regex = try? NSRegularExpression(pattern: patron) {
                let rango = NSRange(resultado.startIndex..<resultado.endIndex, in: resultado)
                let plantilla = NSRegularExpression.escapedTemplate(for: entrada.correcto)
                resultado = regex.stringByReplacingMatches(
                    in: resultado,
                    range: rango,
                    withTemplate: plantilla
                )
            }
        }
        return resultado
    }
}

/// Ensamblador puro de segmentos en vivo: mantiene los textos provisionales de "Tú" y "Otros",
/// aplica el glosario y consolida los segmentos finales ordenados por tiempo (GRB-3, GRB-5, GRB-8).
public struct EnsambladorDeSegmentos: Sendable, Equatable {
    public let reunionID: String
    public var corrector: CorrectorDeGlosario
    public private(set) var segmentosFinales: [SegmentoDeTranscripcion] = []
    public private(set) var provisionalMicrofono: SegmentoDeTranscripcion?
    public private(set) var provisionalSistema: SegmentoDeTranscripcion?
    private var inicioProvisionalMic: Double?
    private var inicioProvisionalSistema: Double?

    public init(
        reunionID: String,
        corrector: CorrectorDeGlosario = CorrectorDeGlosario(),
        segmentosIniciales: [SegmentoDeTranscripcion] = []
    ) {
        self.reunionID = reunionID
        self.corrector = corrector
        self.segmentosFinales = segmentosIniciales.sorted { $0.inicioSegundos < $1.inicioSegundos }
    }

    /// Todos los segmentos visibles en la vista en vivo (finales más provisionales activos).
    public var segmentosEnVivo: [SegmentoDeTranscripcion] {
        var lista = segmentosFinales
        if let provisionalSistema {
            lista.append(provisionalSistema)
        }
        if let provisionalMicrofono {
            lista.append(provisionalMicrofono)
        }
        return lista
    }

    /// Registra un texto parcial o final proveniente de un analizador de voz.
    /// Devuelve el segmento final cuando `esFinal` es verdadero y tiene contenido.
    @discardableResult
    public mutating func recibir(
        fuente: FuenteDeAudio,
        texto: String,
        esFinal: Bool,
        enSegundos: Double,
        confianza: Double? = nil,
        id: String = UUID().uuidString
    ) -> SegmentoDeTranscripcion? {
        let limpio = corrector.corregir(texto.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !limpio.isEmpty else {
            if esFinal { limpiarProvisional(de: fuente) }
            return nil
        }

        if !esFinal {
            let inicio: Double
            switch fuente {
            case .microfono:
                inicio = inicioProvisionalMic ?? enSegundos
                inicioProvisionalMic = inicio
                let seg = SegmentoDeTranscripcion(
                    id: "prov-mic",
                    reunionID: reunionID,
                    fuente: .microfono,
                    inicioSegundos: inicio,
                    finSegundos: max(inicio, enSegundos),
                    texto: limpio,
                    confianza: confianza,
                    esFinal: false
                )
                provisionalMicrofono = seg
                return seg
            case .sistema:
                inicio = inicioProvisionalSistema ?? enSegundos
                inicioProvisionalSistema = inicio
                let seg = SegmentoDeTranscripcion(
                    id: "prov-sis",
                    reunionID: reunionID,
                    fuente: .sistema,
                    inicioSegundos: inicio,
                    finSegundos: max(inicio, enSegundos),
                    texto: limpio,
                    confianza: confianza,
                    esFinal: false
                )
                provisionalSistema = seg
                return seg
            case .marca:
                return nil
            }
        }

        let inicio: Double
        switch fuente {
        case .microfono:
            inicio = inicioProvisionalMic ?? max(0, enSegundos - 1)
            limpiarProvisional(de: .microfono)
        case .sistema:
            inicio = inicioProvisionalSistema ?? max(0, enSegundos - 1)
            limpiarProvisional(de: .sistema)
        case .marca:
            inicio = enSegundos
        }

        let final = SegmentoDeTranscripcion(
            id: id,
            reunionID: reunionID,
            fuente: fuente,
            inicioSegundos: inicio,
            finSegundos: max(inicio, enSegundos),
            texto: limpio,
            confianza: confianza,
            esFinal: true
        )
        segmentosFinales.append(final)
        return final
    }

    /// Inserta una marca de tiempo durante la reunión (GRB-8).
    @discardableResult
    public mutating func agregarMarca(
        etiqueta: String = "Marca importante",
        enSegundos: Double,
        id: String = UUID().uuidString
    ) -> SegmentoDeTranscripcion {
        let texto = etiqueta.trimmingCharacters(in: .whitespacesAndNewlines)
        let marca = SegmentoDeTranscripcion(
            id: id,
            reunionID: reunionID,
            fuente: .marca,
            inicioSegundos: max(0, enSegundos),
            finSegundos: max(0, enSegundos),
            texto: texto.isEmpty ? "Marca importante" : texto,
            esFinal: true
        )
        segmentosFinales.append(marca)
        return marca
    }

    /// Consolida cualquier texto provisional pendiente (por ejemplo antes de entrar en reposo o detener).
    public mutating func consolidarProvisionales(enSegundos: Double) -> [SegmentoDeTranscripcion] {
        var consolidados: [SegmentoDeTranscripcion] = []
        if let provSis = provisionalSistema, !provSis.texto.isEmpty {
            let seg = SegmentoDeTranscripcion(
                reunionID: reunionID,
                fuente: .sistema,
                inicioSegundos: provSis.inicioSegundos,
                finSegundos: max(provSis.inicioSegundos, enSegundos),
                texto: provSis.texto,
                confianza: provSis.confianza,
                esFinal: true
            )
            segmentosFinales.append(seg)
            consolidados.append(seg)
        }
        if let provMic = provisionalMicrofono, !provMic.texto.isEmpty {
            let seg = SegmentoDeTranscripcion(
                reunionID: reunionID,
                fuente: .microfono,
                inicioSegundos: provMic.inicioSegundos,
                finSegundos: max(provMic.inicioSegundos, enSegundos),
                texto: provMic.texto,
                confianza: provMic.confianza,
                esFinal: true
            )
            segmentosFinales.append(seg)
            consolidados.append(seg)
        }
        limpiarProvisional(de: .sistema)
        limpiarProvisional(de: .microfono)
        return consolidados
    }

    private mutating func limpiarProvisional(de fuente: FuenteDeAudio) {
        switch fuente {
        case .microfono:
            provisionalMicrofono = nil
            inicioProvisionalMic = nil
        case .sistema:
            provisionalSistema = nil
            inicioProvisionalSistema = nil
        case .marca:
            break
        }
    }
}

// MARK: - Bloques de audio y Puertos (M4)

/// Bloque de muestras PCM en coma flotante (-1...1) que viaja entre los puertos de captura,
/// escritura por trozos y transcripción sin acoplar `NotchyFeatures` a `AVFoundation`.
public struct BloqueDeAudioPCM: Sendable, Equatable {
    public let fuente: FuenteDeAudio
    public let muestras: [Float]
    public let frecuencia: Double
    public let canales: Int
    public let frames: Int
    public let muestraInicial: Double
    public let marcaHostMs: Double
    public let nivelRMS: Double

    public init(
        fuente: FuenteDeAudio,
        muestras: [Float],
        frecuencia: Double = 48_000,
        canales: Int = 1,
        frames: Int? = nil,
        muestraInicial: Double = 0,
        marcaHostMs: Double = 0,
        nivelRMS: Double? = nil
    ) {
        self.fuente = fuente
        self.muestras = muestras
        self.frecuencia = max(1, frecuencia)
        self.canales = max(1, canales)
        self.frames = frames ?? (muestras.count / max(1, canales))
        self.muestraInicial = muestraInicial
        self.marcaHostMs = marcaHostMs
        if let nivelRMS {
            self.nivelRMS = min(max(nivelRMS, 0), 1)
        } else {
            self.nivelRMS = Self.calcularNivelRMS(muestras)
        }
    }

    public static func calcularNivelRMS(_ muestras: [Float]) -> Double {
        guard !muestras.isEmpty else { return 0 }
        var suma: Float = 0
        for muestra in muestras {
            suma += muestra * muestra
        }
        let rms = sqrt(suma / Float(muestras.count))
        return min(max(Double(rms) * 4.2, 0), 1)
    }
}

/// Eventos del hardware o de energía que afectan a una grabación en curso (GRB-7).
public enum EventoDeEntornoDeAudio: Sendable, Equatable {
    case reposoDelMacIniciado
    case despertarDelMac
    case cambioDeDispositivo(nombre: String)
    case falloDeFuente(fuente: FuenteDeAudio, detalle: String)
}

/// Diagnóstico de captura en vivo para medir cortes y desfase (S3, GRB-2, GRB-7).
public struct EstadisticasDeCapturaDeAudio: Sendable, Equatable {
    public var nombreMicrofono: String
    public var usaMicrofonoInterno: Bool
    public var formatoMicrofono: String
    public var formatoSistema: String
    public var bloquesMicrofono: Int
    public var cortesMicrofono: Int
    public var bloquesSistema: Int
    public var cortesSistema: Int
    public var desfaseInicialMs: Double?

    public init(
        nombreMicrofono: String = "Micrófono",
        usaMicrofonoInterno: Bool = false,
        formatoMicrofono: String = "",
        formatoSistema: String = "",
        bloquesMicrofono: Int = 0,
        cortesMicrofono: Int = 0,
        bloquesSistema: Int = 0,
        cortesSistema: Int = 0,
        desfaseInicialMs: Double? = nil
    ) {
        self.nombreMicrofono = nombreMicrofono
        self.usaMicrofonoInterno = usaMicrofonoInterno
        self.formatoMicrofono = formatoMicrofono
        self.formatoSistema = formatoSistema
        self.bloquesMicrofono = bloquesMicrofono
        self.cortesMicrofono = cortesMicrofono
        self.bloquesSistema = bloquesSistema
        self.cortesSistema = cortesSistema
        self.desfaseInicialMs = desfaseInicialMs
    }
}

/// Puerto de captura de micrófono y audio del sistema (GRB-1, GRB-2, GRB-7).
@MainActor
public protocol PuertoDeCapturaDeAudio: AnyObject {
    var capturando: Bool { get }
    var estadisticas: EstadisticasDeCapturaDeAudio { get }
    func estadoDePermisoMicrofono() -> EstadoDePermiso
    func pedirPermisoMicrofono() async -> EstadoDePermiso
    func iniciarCaptura(
        incluirSistema: Bool,
        preferirMicrofonoInterno: Bool,
        alRecibirBloque: @escaping @Sendable (BloqueDeAudioPCM) -> Void,
        alCambiarEntorno: @escaping @Sendable (EventoDeEntornoDeAudio) -> Void
    ) async throws
    func detenerCaptura() async
}

/// Puerto de escritura incremental de audio por trozos (GRB-1, GRB-4, GRB-7, RNF-4).
@MainActor
public protocol PuertoDeEscritorDeAudio: AnyObject {
    var rutasMicrofono: [String] { get }
    var rutasSistema: [String] { get }
    func iniciarSesion(
        carpetaBase: URL,
        prefijo: String,
        incluirSistema: Bool,
        duracionTrozoSegundos: Double
    ) throws
    func escribir(_ bloque: BloqueDeAudioPCM) throws
    /// Cierra los archivos actuales y abre el siguiente trozo numerado sin perder muestras (GRB-7).
    func rotarTrozo() throws
    /// Cierra la sesión y elimina cualquier trozo de 0 frames para no dejar archivos vacíos.
    func finalizarSesion() -> (rutasMicrofono: [String], rutasSistema: [String])
}

/// Fragmento emitido por un analizador de transcripción (GRB-3, GRB-4).
public struct ResultadoDeTranscripcion: Sendable, Equatable {
    public let fuente: FuenteDeAudio
    public let texto: String
    public let esFinal: Bool
    public let confianza: Double?

    public init(
        fuente: FuenteDeAudio,
        texto: String,
        esFinal: Bool,
        confianza: Double? = nil
    ) {
        self.fuente = fuente
        self.texto = texto
        self.esFinal = esFinal
        self.confianza = confianza
    }
}

/// Puerto de transcripción con dos analizadores (`SpeechTranscriber` en `es-MX` o `en-US`, D-07).
@MainActor
public protocol PuertoDeTranscripcion: AnyObject {
    var idiomaActivo: IdiomaDeTranscripcion { get }
    func iniciar(
        idioma: IdiomaDeTranscripcion,
        incluirSistema: Bool,
        alRecibirResultado: @escaping @Sendable (ResultadoDeTranscripcion) -> Void
    ) async throws
    func alimentar(_ bloque: BloqueDeAudioPCM)
    func cambiarIdioma(_ nuevo: IdiomaDeTranscripcion) async throws
    func detener() async
    /// Retranscribe los archivos guardados de una reunión o nota de voz (GRB-4, D-25).
    func retranscribir(
        archivos: [(fuente: FuenteDeAudio, url: URL)],
        idioma: IdiomaDeTranscripcion
    ) async throws -> [ResultadoDeTranscripcion]
}

// MARK: - Eventos entre módulos (M4)

/// Estado del indicador de grabación para la isla y otros módulos (GRB-6).
public struct GrabacionCambiada: Evento, Equatable {
    public let activa: Bool
    public let esReunion: Bool
    public let pausada: Bool
    public let segundos: Int
    public let nivelMicrofono: Double
    public let nivelSistema: Double

    public init(
        activa: Bool,
        esReunion: Bool,
        pausada: Bool = false,
        segundos: Int = 0,
        nivelMicrofono: Double = 0,
        nivelSistema: Double = 0
    ) {
        self.activa = activa
        self.esReunion = esReunion
        self.pausada = pausada
        self.segundos = segundos
        self.nivelMicrofono = nivelMicrofono
        self.nivelSistema = nivelSistema
    }
}

/// Publicado cada vez que llega un segmento de transcripción en vivo (GRB-3).
public struct SegmentoDeTranscripcionRecibido: Evento, Equatable {
    public let segmento: SegmentoDeTranscripcion

    public init(segmento: SegmentoDeTranscripcion) {
        self.segmento = segmento
    }
}

/// Publicado al cerrar y guardar una reunión, para que Notas de reunión pueda resumirla (M5).
public struct ReunionTerminada: Evento, Equatable {
    public let reunion: ReunionGrabada

    public init(reunion: ReunionGrabada) {
        self.reunion = reunion
    }
}

/// Petición para iniciar la grabación de una reunión desde el aviso de llamada de Agenda (AGD-4).
public struct IniciarReunionDesdeAviso: Evento, Equatable {
    public let titulo: String
    public let eventoCalendarioID: String?

    public init(titulo: String, eventoCalendarioID: String? = nil) {
        self.titulo = titulo
        self.eventoCalendarioID = eventoCalendarioID
    }
}
