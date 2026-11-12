import Foundation

/// Estado de OpenCode para el panel de diagnóstico (SIS-2).
public enum EstadoDeOpenCode: Sendable, Equatable {
    case instalado(ruta: String)
    case noEncontrado

    public var estaListo: Bool {
        if case .instalado = self { return true }
        return false
    }

    public var detalle: String {
        switch self {
        case .instalado(let ruta): "Instalado en \(ruta) (el supervisor se conecta en M6)"
        case .noEncontrado: "No se encontró el binario de OpenCode. Instálalo con: brew install opencode"
        }
    }
}

/// Estado de la base de datos para el panel de diagnóstico (SIS-2).
public struct DiagnosticoDeBase: Sendable, Equatable {
    public let estaBien: Bool
    public let detalle: String
    public let comoArreglarlo: String?

    public init(estaBien: Bool, detalle: String, comoArreglarlo: String? = nil) {
        self.estaBien = estaBien
        self.detalle = detalle
        self.comoArreglarlo = comoArreglarlo
    }
}

/// Resumen de un módulo para mostrar en el panel de diagnóstico.
public struct DiagnosticoDeModulo: Sendable, Equatable, Identifiable {
    public let id: String
    public let nombre: String
    public let activo: Bool
    public let salud: SaludDeModulo

    public init(id: String, nombre: String, activo: Bool, salud: SaludDeModulo) {
        self.id = id
        self.nombre = nombre
        self.activo = activo
        self.salud = salud
    }
}
