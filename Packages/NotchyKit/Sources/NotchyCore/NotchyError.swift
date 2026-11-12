import Foundation

/// Errores que cruzan capas. El texto es para mostrarlo en el panel de diagnóstico: sin contenido personal.
public enum NotchyError: Error, Equatable, Sendable, LocalizedError {
    /// La base tiene una migración que esta versión de la app no conoce.
    case baseMasNueva(migracion: String)
    case datos(String)
    case noDisponible(String)

    public var errorDescription: String? {
        switch self {
        case .baseMasNueva(let migracion):
            "La base de datos la creó una versión más nueva de Notchy (migración \(migracion))."
        case .datos(let detalle):
            "Error de datos: \(detalle)"
        case .noDisponible(let que):
            "No disponible: \(que)"
        }
    }
}
