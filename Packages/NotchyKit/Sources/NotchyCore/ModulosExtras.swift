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
