import Foundation

/// Color muestreado para el Color Picker con conversiones a HEX, RGB, HSL, literal Swift y contraste WCAG.
public struct ColorMuestreado: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let rojo: Double
    public let verde: Double
    public let azul: Double

    public init(id: String = UUID().uuidString, rojo: Double, verde: Double, azul: Double) {
        self.id = id
        self.rojo = min(max(rojo, 0), 1)
        self.verde = min(max(verde, 0), 1)
        self.azul = min(max(azul, 0), 1)
    }

    public init?(hex: String) {
        let limpio = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard limpio.count == 6, let valor = UInt32(limpio, radix: 16) else { return nil }
        self.init(
            rojo: Double((valor >> 16) & 0xFF) / 255.0,
            verde: Double((valor >> 8) & 0xFF) / 255.0,
            azul: Double(valor & 0xFF) / 255.0
        )
    }

    public var hexEntero: UInt32 {
        let r = UInt32((rojo * 255).rounded()) & 0xFF
        let g = UInt32((verde * 255).rounded()) & 0xFF
        let b = UInt32((azul * 255).rounded()) & 0xFF
        return (r << 16) | (g << 8) | b
    }

    public var hex: String {
        String(format: "#%06X", hexEntero)
    }

    public var rgbTexto: String {
        let r = Int((rojo * 255).rounded())
        let g = Int((verde * 255).rounded())
        let b = Int((azul * 255).rounded())
        return "rgb(\(r), \(g), \(b))"
    }

    public var hslTexto: String {
        let maxC = max(rojo, verde, azul)
        let minC = min(rojo, verde, azul)
        let delta = maxC - minC
        let l = (maxC + minC) / 2.0
        var h = 0.0
        var s = 0.0
        if delta > 0.0001 {
            s = delta / (1.0 - abs(2.0 * l - 1.0))
            if maxC == rojo {
                h = 60.0 * (((verde - azul) / delta).truncatingRemainder(dividingBy: 6.0))
            } else if maxC == verde {
                h = 60.0 * (((azul - rojo) / delta) + 2.0)
            } else {
                h = 60.0 * (((rojo - verde) / delta) + 4.0)
            }
            if h < 0 { h += 360.0 }
        }
        return String(
            format: "hsl(%d, %d%%, %d%%)", Int(h.rounded()), Int((s * 100).rounded()), Int((l * 100).rounded()))
    }

    public var swiftTexto: String {
        String(format: "Color(red: %.2f, green: %.2f, blue: %.2f)", rojo, verde, azul)
    }

    public func texto(en formato: FormatoDeColor) -> String {
        switch formato {
        case .hex: hex
        case .rgb: rgbTexto
        case .hsl: hslTexto
        case .swift: swiftTexto
        }
    }

    /// Luminancia relativa según WCAG 2.1.
    public var luminanciaRelativa: Double {
        func canal(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * canal(rojo) + 0.7152 * canal(verde) + 0.0722 * canal(azul)
    }

    /// Razón de contraste WCAG (1.0 a 21.0) frente a otro color.
    public func contrasteWCAG(contra otro: ColorMuestreado) -> Double {
        let l1 = max(luminanciaRelativa, otro.luminanciaRelativa)
        let l2 = min(luminanciaRelativa, otro.luminanciaRelativa)
        return (l1 + 0.05) / (l2 + 0.05)
    }
}

public enum FormatoDeColor: String, Sendable, CaseIterable, Equatable {
    case hex = "HEX"
    case rgb = "RGB"
    case hsl = "HSL"
    case swift = "Swift"
}

@MainActor
public protocol PuertoMuestreadorDeColor: AnyObject {
    func muestrearColorEnPantalla() async -> ColorMuestreado?
    func copiarAlPortapapeles(_ texto: String)
}

/// Línea sincronizada o plana de la letra de una canción.
public struct LineaDeLetra: Sendable, Equatable, Identifiable {
    public let id: Int
    public let tiempoSegundos: Double?
    public let texto: String

    public init(id: Int, tiempoSegundos: Double?, texto: String) {
        self.id = id
        self.tiempoSegundos = tiempoSegundos
        self.texto = texto
    }
}

public struct LetraDeCancion: Sendable, Equatable {
    public let titulo: String
    public let artista: String
    public let lineas: [LineaDeLetra]

    public init(titulo: String, artista: String, lineas: [LineaDeLetra]) {
        self.titulo = titulo
        self.artista = artista
        self.lineas = lineas
    }

    public func indiceActivo(en segundos: Double) -> Int {
        guard !lineas.isEmpty else { return 0 }
        var ultimo = 0
        for (indice, linea) in lineas.enumerated() {
            if let t = linea.tiempoSegundos {
                if segundos >= t {
                    ultimo = indice
                } else {
                    break
                }
            }
        }
        return ultimo
    }
}

/// Evento publicado cuando cambia el color dominante de la carátula actual (para los temas dinámicos).
public struct ColorDeCaratulaActualizado: Evento, Equatable {
    public let hex: UInt32?

    public init(hex: UInt32?) {
        self.hex = hex
    }
}

/// Tipo de HUD del sistema mostrado en las orejas compactas del notch.
public enum TipoDeHUD: String, Sendable, Equatable, CaseIterable {
    case volumen
    case silencio
    case brillo
    case bateria

    public var icono: String {
        switch self {
        case .volumen: "speaker.wave.2.fill"
        case .silencio: "speaker.slash.fill"
        case .brillo: "sun.max.fill"
        case .bateria: "battery.100percent"
        }
    }
}

public struct EstadoDeHUDSistema: Sendable, Equatable {
    public let tipo: TipoDeHUD
    /// Fracción entre 0.0 y 1.0.
    public let nivel: Double
    public let etiqueta: String

    public init(tipo: TipoDeHUD, nivel: Double, etiqueta: String? = nil) {
        self.tipo = tipo
        self.nivel = min(max(nivel, 0), 1)
        self.etiqueta = etiqueta ?? "\(Int((self.nivel * 100).rounded()))%"
    }
}

/// Categorías de Screen Time local en el Mac.
public enum CategoriaDeScreenTime: String, Sendable, CaseIterable, Codable, Identifiable {
    case desarrollo = "Development"
    case productividad = "Productivity"
    case navegacion = "Browsing"
    case utilidades = "Utilities"
    case comunicacion = "Communication"
    case entretenimiento = "Media"

    public var id: String { rawValue }

    public var hexColor: UInt32 {
        switch self {
        case .desarrollo: 0x5AA9FF
        case .productividad: 0xFFB84D
        case .navegacion: 0xFF8A3D
        case .utilidades: 0x35C3FF
        case .comunicacion: 0x3DDC97
        case .entretenimiento: 0xFF5D55
        }
    }

    public static func clasificar(bundleId: String, nombre: String) -> CategoriaDeScreenTime {
        let b = bundleId.lowercased()
        let n = nombre.lowercased()
        if b.contains("xcode") || b.contains("vscode") || b.contains("cursor") || b.contains("terminal")
            || b.contains("iterm") || b.contains("warp") || b.contains("t3") || n.contains("code")
        {
            return .desarrollo
        }
        if b.contains("safari") || b.contains("chrome") || b.contains("arc") || b.contains("firefox")
            || b.contains("brave")
        {
            return .navegacion
        }
        if b.contains("obsidian") || b.contains("notion") || b.contains("notes") || b.contains("calendar")
            || b.contains("reminders") || b.contains("word") || b.contains("excel") || b.contains("powerpoint")
        {
            return .productividad
        }
        if b.contains("whatsapp") || b.contains("telegram") || b.contains("discord") || b.contains("slack")
            || b.contains("teams") || b.contains("zoom") || b.contains("facetime") || b.contains("mail")
        {
            return .comunicacion
        }
        if b.contains("spotify") || b.contains("music") || b.contains("Resolve") || b.contains("tv")
            || b.contains("quicktime") || b.contains("vlc")
        {
            return .entretenimiento
        }
        return .utilidades
    }
}

public struct UsoDeAppScreenTime: Sendable, Equatable, Codable, Identifiable {
    public var id: String { bundleId }
    public let bundleId: String
    public let nombre: String
    public let categoria: CategoriaDeScreenTime
    public var segundos: Double
    public var cambiosDeApp: Int

    public init(
        bundleId: String,
        nombre: String,
        categoria: CategoriaDeScreenTime,
        segundos: Double,
        cambiosDeApp: Int
    ) {
        self.bundleId = bundleId
        self.nombre = nombre
        self.categoria = categoria
        self.segundos = segundos
        self.cambiosDeApp = cambiosDeApp
    }
}

// MARK: - Clima (Open-Meteo)

public struct PronosticoPorHora: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let etiquetaHora: String
    public let codigoWMO: Int
    public let esDeDia: Bool
    public let temperaturaC: Double

    public init(
        id: String,
        etiquetaHora: String,
        codigoWMO: Int,
        esDeDia: Bool,
        temperaturaC: Double
    ) {
        self.id = id
        self.etiquetaHora = etiquetaHora
        self.codigoWMO = codigoWMO
        self.esDeDia = esDeDia
        self.temperaturaC = temperaturaC
    }
}

public struct EstadoDelClima: Sendable, Equatable, Codable {
    public let ciudad: String
    public let latitud: Double
    public let longitud: Double
    public let temperaturaC: Double
    public let sensacionC: Double
    public let maximaC: Double
    public let minimaC: Double
    public let humedadPorcentaje: Int
    public let vientoKmH: Double
    public let indiceUV: Double
    public let probabilidadLluvia: Int
    public let presionHPa: Int
    public let amanecer: String
    public let atardecer: String
    public let codigoWMO: Int
    public let esDeDia: Bool
    public let porHora: [PronosticoPorHora]
    public let fechaActualizacion: Date

    public init(
        ciudad: String,
        latitud: Double,
        longitud: Double,
        temperaturaC: Double,
        sensacionC: Double,
        maximaC: Double,
        minimaC: Double,
        humedadPorcentaje: Int,
        vientoKmH: Double,
        indiceUV: Double,
        probabilidadLluvia: Int,
        presionHPa: Int,
        amanecer: String,
        atardecer: String,
        codigoWMO: Int,
        esDeDia: Bool,
        porHora: [PronosticoPorHora],
        fechaActualizacion: Date = .now
    ) {
        self.ciudad = ciudad
        self.latitud = latitud
        self.longitud = longitud
        self.temperaturaC = temperaturaC
        self.sensacionC = sensacionC
        self.maximaC = maximaC
        self.minimaC = minimaC
        self.humedadPorcentaje = humedadPorcentaje
        self.vientoKmH = vientoKmH
        self.indiceUV = indiceUV
        self.probabilidadLluvia = probabilidadLluvia
        self.presionHPa = presionHPa
        self.amanecer = amanecer
        self.atardecer = atardecer
        self.codigoWMO = codigoWMO
        self.esDeDia = esDeDia
        self.porHora = porHora
        self.fechaActualizacion = fechaActualizacion
    }

    public static func iconoWMO(codigo: Int, esDeDia: Bool) -> String {
        switch codigo {
        case 0:
            return esDeDia ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2:
            return esDeDia ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55, 56, 57:
            return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86:
            return "cloud.snow.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return esDeDia ? "cloud.sun.fill" : "cloud.moon.fill"
        }
    }

    public static func descripcionWMO(codigo: Int) -> String {
        switch codigo {
        case 0: "Clear sky"
        case 1: "Mainly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Foggy"
        case 51, 53, 55: "Light drizzle"
        case 61, 63, 65: "Rain"
        case 71, 73, 75: "Snow"
        case 80, 81, 82: "Rain showers"
        case 95, 96, 99: "Thunderstorm"
        default: "Clear sky"
        }
    }
}

// MARK: - Notificaciones Recientes

public struct NotificacionReciente: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let bundleId: String
    public let nombreApp: String
    public let titulo: String
    public let subtitulo: String?
    public let cuerpo: String
    public let fecha: Date
    public var leida: Bool

    public init(
        id: String = UUID().uuidString,
        bundleId: String,
        nombreApp: String,
        titulo: String,
        subtitulo: String? = nil,
        cuerpo: String,
        fecha: Date = .now,
        leida: Bool = false
    ) {
        self.id = id
        self.bundleId = bundleId
        self.nombreApp = nombreApp
        self.titulo = titulo
        self.subtitulo = subtitulo
        self.cuerpo = cuerpo
        self.fecha = fecha
        self.leida = leida
    }
}

/// Lee las notificaciones que macOS entregó a cualquier app (base de Notification Center).
public protocol PuertoDeNotificacionesDelSistema: Sendable {
    /// `false` si falta Acceso total al disco o la base no existe.
    func tieneAcceso() -> Bool
    /// Notificaciones entregadas, más recientes primero.
    func recientes(limite: Int) async throws -> [NotificacionReciente]
}

// MARK: - Minichatbot Agéntico (OpenCode)

public struct MensajeDeAgente: Sendable, Equatable, Codable, Identifiable {
    public enum Rol: String, Sendable, Equatable, Codable {
        case usuario
        case asistente
        case herramienta
    }

    public let id: String
    public let rol: Rol
    public var texto: String
    public let fecha: Date

    public init(
        id: String = UUID().uuidString,
        rol: Rol,
        texto: String,
        fecha: Date = .now
    ) {
        self.id = id
        self.rol = rol
        self.texto = texto
        self.fecha = fecha
    }
}

@MainActor
public protocol PuertoAgenteOpenCode: AnyObject {
    func estaDisponible() -> Bool
    func modelosDisponibles() async -> [String]
    func enviarMensaje(
        prompt: String,
        modelo: String?,
        sesionID: String?,
        directorio: String?,
        alRecibirFragmento: @escaping @MainActor (String, String?) -> Void
    ) async throws -> (textoFinal: String, sesionID: String?)
}

// MARK: - Traductor (Translate)

public enum IdiomaDeTraduccion: String, Sendable, CaseIterable, Codable, Identifiable {
    case espanol = "es"
    case ingles = "en"
    case aleman = "de"
    case frances = "fr"
    case portugues = "pt"
    case italiano = "it"
    case japones = "ja"
    case chino = "zh"

    public var id: String { rawValue }

    public var etiqueta: String {
        switch self {
        case .espanol: "SPANISH"
        case .ingles: "ENGLISH"
        case .aleman: "GERMAN"
        case .frances: "FRENCH"
        case .portugues: "PORTUGUESE"
        case .italiano: "ITALIAN"
        case .japones: "JAPANESE"
        case .chino: "CHINESE"
        }
    }

    public var nombreCompleto: String {
        switch self {
        case .espanol: "Español"
        case .ingles: "English"
        case .aleman: "Deutsch"
        case .frances: "Français"
        case .portugues: "Português"
        case .italiano: "Italiano"
        case .japones: "日本語"
        case .chino: "中文"
        }
    }
}

// MARK: - Window Snap

public enum DisposicionDeVentana: String, Sendable, CaseIterable, Codable, Identifiable {
    case mitadIzquierda
    case mitadDerecha
    case mitadSuperior
    case mitadInferior
    case cuartoSupIzq
    case cuartoSupDer
    case cuartoInfIzq
    case cuartoInfDer
    case maximizar
    case centrar
    case tercioIzquierdo
    case tercioCentral
    case tercioDerecho

    public var id: String { rawValue }

    public var titulo: String {
        switch self {
        case .mitadIzquierda: "Left Half"
        case .mitadDerecha: "Right Half"
        case .mitadSuperior: "Top Half"
        case .mitadInferior: "Bottom Half"
        case .cuartoSupIzq: "Top Left"
        case .cuartoSupDer: "Top Right"
        case .cuartoInfIzq: "Bottom Left"
        case .cuartoInfDer: "Bottom Right"
        case .maximizar: "Maximize"
        case .centrar: "Center"
        case .tercioIzquierdo: "Left Third"
        case .tercioCentral: "Center Third"
        case .tercioDerecho: "Right Third"
        }
    }

    /// Rectángulo normalizado (0...1) en coordenadas con origen arriba-izquierda de la pantalla visible.
    public var rectanguloNormalizado: (x: Double, y: Double, ancho: Double, alto: Double) {
        switch self {
        case .mitadIzquierda: (0.0, 0.0, 0.5, 1.0)
        case .mitadDerecha: (0.5, 0.0, 0.5, 1.0)
        case .mitadSuperior: (0.0, 0.0, 1.0, 0.5)
        case .mitadInferior: (0.0, 0.5, 1.0, 0.5)
        case .cuartoSupIzq: (0.0, 0.0, 0.5, 0.5)
        case .cuartoSupDer: (0.5, 0.0, 0.5, 0.5)
        case .cuartoInfIzq: (0.0, 0.5, 0.5, 0.5)
        case .cuartoInfDer: (0.5, 0.5, 0.5, 0.5)
        case .maximizar: (0.0, 0.0, 1.0, 1.0)
        case .centrar: (0.12, 0.10, 0.76, 0.80)
        case .tercioIzquierdo: (0.0, 0.0, 0.3333, 1.0)
        case .tercioCentral: (0.3333, 0.0, 0.3334, 1.0)
        case .tercioDerecho: (0.6667, 0.0, 0.3333, 1.0)
        }
    }
}

@MainActor
public protocol PuertoWindowSnap: AnyObject {
    var nombreAppObjetivo: String { get }
    var bundleIdObjetivo: String? { get }
    var tienePermisoAccesibilidad: Bool { get }
    func pedirPermisoAccesibilidad()
    func aplicar(_ disposicion: DisposicionDeVentana) -> Bool
}

// MARK: - System Monitor (System Analytics)

public struct MetricasDelSistema: Sendable, Equatable {
    public let usoCPUPorcentaje: Double
    public let memoriaUsadaGB: Double
    public let memoriaTotalGB: Double
    public let almacenamientoUsadoPorcentaje: Double
    public let discoLibreGB: Double
    public let discoTotalGB: Double
    public let redBytesPorSegundo: Double
    public let bateriaPorcentaje: Int
    public let bateriaCargando: Bool

    public init(
        usoCPUPorcentaje: Double,
        memoriaUsadaGB: Double,
        memoriaTotalGB: Double,
        almacenamientoUsadoPorcentaje: Double,
        discoLibreGB: Double,
        discoTotalGB: Double,
        redBytesPorSegundo: Double,
        bateriaPorcentaje: Int,
        bateriaCargando: Bool
    ) {
        self.usoCPUPorcentaje = usoCPUPorcentaje
        self.memoriaUsadaGB = memoriaUsadaGB
        self.memoriaTotalGB = memoriaTotalGB
        self.almacenamientoUsadoPorcentaje = almacenamientoUsadoPorcentaje
        self.discoLibreGB = discoLibreGB
        self.discoTotalGB = discoTotalGB
        self.redBytesPorSegundo = redBytesPorSegundo
        self.bateriaPorcentaje = bateriaPorcentaje
        self.bateriaCargando = bateriaCargando
    }

    public var memoriaPorcentaje: Double {
        guard memoriaTotalGB > 0 else { return 0 }
        return min(max((memoriaUsadaGB / memoriaTotalGB) * 100.0, 0), 100)
    }

    public var discoLibrePorcentaje: Double {
        guard discoTotalGB > 0 else { return 0 }
        return min(max((discoLibreGB / discoTotalGB) * 100.0, 0), 100)
    }

    public static func formatearVelocidadRed(_ bytesPorSegundo: Double) -> String {
        if bytesPorSegundo >= 1_048_576 {
            return String(format: "%.2f MB/s", bytesPorSegundo / 1_048_576.0)
        }
        if bytesPorSegundo >= 1024 {
            return String(format: "%.2f KB/s", bytesPorSegundo / 1024.0)
        }
        return String(format: "%.0f B/s", max(0, bytesPorSegundo))
    }
}

@MainActor
public protocol PuertoMonitorDelSistema: AnyObject {
    func leerMetricas() -> MetricasDelSistema
}
