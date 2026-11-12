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
