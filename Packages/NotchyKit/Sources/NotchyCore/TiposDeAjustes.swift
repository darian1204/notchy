import Foundation

/// En qué pantalla vive la isla. En v1 solo hay una isla a la vez (D-27).
public enum PantallaPreferida: String, Codable, Sendable, CaseIterable {
    /// La pantalla con notch; si no hay ninguna, la principal.
    case conNotch
    /// La pantalla principal, tenga o no notch.
    case principal
}

/// Atajo global para abrir y cerrar la isla. Lista fija: sin grabador de teclas por ahora (D-19).
public enum AtajoDeIsla: String, Codable, Sendable, CaseIterable {
    case ninguno
    case controlOpcionEspacio
    case controlOpcionN
    case opcionComandoN

    public var etiqueta: String {
        switch self {
        case .ninguno: "Ninguno"
        case .controlOpcionEspacio: "⌃⌥ Espacio"
        case .controlOpcionN: "⌃⌥ N"
        case .opcionComandoN: "⌥⌘ N"
        }
    }
}

/// Los 7 temas para el fondo/panel de la isla.
public enum TemaDePanel: String, Codable, Sendable, CaseIterable, Identifiable {
    case obsidiana
    case medianoche
    case ciruela
    case bosque
    case grafito
    case ambar
    case caratula

    public var id: String { rawValue }

    public var nombre: String {
        switch self {
        case .obsidiana: "Obsidiana (Negro puro)"
        case .medianoche: "Medianoche"
        case .ciruela: "Ciruela"
        case .bosque: "Bosque"
        case .grafito: "Grafito"
        case .ambar: "Ámbar"
        case .caratula: "Carátula en reproducción"
        }
    }

    public var hexBase: UInt32 {
        switch self {
        case .obsidiana: 0x000000
        case .medianoche: 0x0B1020
        case .ciruela: 0x1A0F1E
        case .bosque: 0x0B1914
        case .grafito: 0x141619
        case .ambar: 0x1C140B
        case .caratula: 0x1E121A
        }
    }
}

/// Los 9 temas de acento para la barra superior e íconos de la isla.
public enum TemaDeBarra: String, Codable, Sendable, CaseIterable, Identifiable {
    case clasico
    case rosaCuarzo
    case esmeralda
    case zafiro
    case ambar
    case violeta
    case coral
    case cian
    case caratula

    public var id: String { rawValue }

    public var nombre: String {
        switch self {
        case .clasico: "Clásico (Por módulo)"
        case .rosaCuarzo: "Rosa cuarzo"
        case .esmeralda: "Esmeralda"
        case .zafiro: "Zafiro"
        case .ambar: "Ámbar"
        case .violeta: "Violeta"
        case .coral: "Coral"
        case .cian: "Cian"
        case .caratula: "Color de la carátula"
        }
    }

    public var hexAcento: UInt32? {
        switch self {
        case .clasico: nil
        case .rosaCuarzo: 0xD97D98
        case .esmeralda: 0x3DDC97
        case .zafiro: 0x5AA9FF
        case .ambar: 0xFFB84D
        case .violeta: 0xA58BFF
        case .coral: 0xFF6B6B
        case .cian: 0x35C3FF
        case .caratula: 0xE07A9B
        }
    }
}

/// Cómo se ve la isla abierta. Los dos conviven; se elige en Ajustes.
public enum EstiloDeIsla: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Barra con un ícono por módulo y columnas separadas por líneas.
    case clasico
    /// Pestañas en las orejas, buscador ⌘K y tarjetas.
    case tarjetas

    public var id: String { rawValue }

    public var nombre: String {
        switch self {
        case .clasico: "Clásico"
        case .tarjetas: "Tarjetas"
        }
    }

    public var descripcion: String {
        switch self {
        case .clasico: "Un ícono por módulo arriba y columnas en el Inicio."
        case .tarjetas: "Pestañas en las orejas, buscador ⌘K y tarjetas en el Inicio."
        }
    }
}

/// Liquid glass en la isla. Cada nivel incluye al anterior.
public enum EstiloDeVidrio: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Superficies tenues sobre el fondo del tema, como siempre.
    case apagado
    /// Vidrio en las píldoras de pestañas, botones y accesos rápidos.
    case pildoras
    /// Vidrio en las píldoras y en las tarjetas.
    case pildorasYTarjetas
    /// Toda la isla abierta es vidrio, con píldoras y tarjetas encima.
    case completo

    public var id: String { rawValue }

    public var nombre: String {
        switch self {
        case .apagado: "Apagado"
        case .pildoras: "Píldoras"
        case .pildorasYTarjetas: "Píldoras y tarjetas"
        case .completo: "Completo"
        }
    }

    public var descripcion: String {
        switch self {
        case .apagado: "Superficies tenues sobre el color del tema."
        case .pildoras: "Liquid glass en las pestañas, botones y accesos rápidos."
        case .pildorasYTarjetas: "Liquid glass en las píldoras y en las tarjetas; el fondo sigue con el tema."
        case .completo: "Toda la isla abierta es liquid glass. El notch queda negro arriba."
        }
    }

    public var pildoras: Bool { self != .apagado }
    public var tarjetas: Bool { self == .pildorasYTarjetas || self == .completo }
    public var fondo: Bool { self == .completo }
}

/// Tarjetas que se pueden poner en el Inicio del estilo tarjetas.
public enum TarjetaDeInicio: String, Codable, Sendable, CaseIterable, Identifiable {
    case musica, inbox, bandeja, agenda, portapapeles, monitor

    public var id: String { rawValue }

    public var nombre: String {
        switch self {
        case .musica: "Música y estado"
        case .inbox: "Inbox"
        case .bandeja: "Bandeja"
        case .agenda: "Agenda de hoy"
        case .portapapeles: "Portapapeles"
        case .monitor: "Monitor"
        }
    }

    public var icono: String {
        switch self {
        case .musica: "music.note"
        case .inbox: "tray.and.arrow.down"
        case .bandeja: "square.and.arrow.down.on.square"
        case .agenda: "calendar"
        case .portapapeles: "doc.on.clipboard"
        case .monitor: "gauge.with.dots.needle.33percent"
        }
    }
}

/// Ancho relativo de una tarjeta del Inicio. Los anchos reales se reparten el espacio en proporción.
public enum AnchoDeTarjeta: String, Codable, Sendable, CaseIterable, Identifiable {
    case angosta, media, ancha

    public var id: String { rawValue }

    public var nombre: String {
        switch self {
        case .angosta: "Angosta"
        case .media: "Media"
        case .ancha: "Ancha"
        }
    }

    /// Peso en puntos: con las tres por defecto suman exactamente el ancho de la fila.
    public var peso: Double {
        switch self {
        case .angosta: 124
        case .media: 208
        case .ancha: 262
        }
    }

    /// El siguiente ancho, para un botón que cicla.
    public var siguiente: AnchoDeTarjeta {
        switch self {
        case .angosta: .media
        case .media: .ancha
        case .ancha: .angosta
        }
    }
}

/// Una tarjeta puesta en el Inicio, con su ancho.
public struct TarjetaDeInicioElegida: Codable, Sendable, Equatable, Identifiable {
    public var tarjeta: TarjetaDeInicio
    public var ancho: AnchoDeTarjeta

    public var id: String { tarjeta.rawValue }

    public init(_ tarjeta: TarjetaDeInicio, _ ancho: AnchoDeTarjeta) {
        self.tarjeta = tarjeta
        self.ancho = ancho
    }
}
