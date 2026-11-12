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
