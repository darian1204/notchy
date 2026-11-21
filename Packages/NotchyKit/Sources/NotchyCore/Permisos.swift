import Foundation

/// Permisos del sistema que piden los módulos de Notchy.
public enum PermisoDelSistema: String, Sendable, CaseIterable, Identifiable {
    case microfono
    case camara
    case calendario
    case recordatorios

    public var id: String { rawValue }

    public var nombre: String {
        switch self {
        case .microfono: "Micrófono"
        case .camara: "Cámara"
        case .calendario: "Calendario"
        case .recordatorios: "Recordatorios"
        }
    }

    public var paraQueSirve: String {
        switch self {
        case .microfono: "Grabar notas de voz y reuniones."
        case .camara: "Mostrar el espejo en el notch."
        case .calendario: "Leer tu agenda del día en la isla."
        case .recordatorios: "Leer y completar pendientes de la lista Obsidian."
        }
    }

    /// Texto para el panel de diagnóstico cuando el usuario lo negó y hay que ir a Ajustes del Sistema.
    public var comoConcederlo: String {
        "Ajustes del Sistema → Privacidad y seguridad → \(nombre)"
    }

    /// Enlace directo a la sección de Privacidad y seguridad en Ajustes del Sistema.
    public var enlaceDeAjustesDelSistema: URL? {
        let ancla =
            switch self {
            case .microfono: "Privacy_Microphone"
            case .camara: "Privacy_Camera"
            case .calendario: "Privacy_Calendars"
            case .recordatorios: "Privacy_Reminders"
            }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(ancla)")
    }
}

/// Estado de un permiso del sistema sin acoplarse al framework que lo administra.
public enum EstadoDePermiso: String, Sendable, Equatable {
    case sinPedir
    case concedido
    case denegado
    case restringido

    public var etiqueta: String {
        switch self {
        case .sinPedir: "Sin pedir"
        case .concedido: "Concedido"
        case .denegado: "Denegado"
        case .restringido: "Restringido"
        }
    }

    public var estaConcedido: Bool { self == .concedido }
}

/// Puerto para consultar y pedir permisos del sistema.
public protocol ProveedorDePermisos: Sendable {
    func estado(de permiso: PermisoDelSistema) -> EstadoDePermiso
    func pedir(_ permiso: PermisoDelSistema) async -> EstadoDePermiso
}

/// Cambió el estado de un permiso del sistema.
public struct CambioDePermiso: Evento, Equatable {
    public let permiso: PermisoDelSistema
    public let estado: EstadoDePermiso

    public init(permiso: PermisoDelSistema, estado: EstadoDePermiso) {
        self.permiso = permiso
        self.estado = estado
    }
}

/// Estado del ítem de inicio de sesión administrado con `SMAppService` (SIS-3).
public enum EstadoDeInicioAlAbrirSesion: String, Sendable, Equatable {
    case activo
    case inactivo
    case requiereAprobacion
    case noDisponible

    public var requiereAprobacionEnSistema: Bool {
        self == .requiereAprobacion
    }
}

/// Puerto para registrar o desregistrar Notchy como ítem de inicio de sesión (SIS-3).
public protocol ServicioDeInicioAlAbrirSesion: Sendable {
    func estado() -> EstadoDeInicioAlAbrirSesion
    @discardableResult
    func aplicar(activo: Bool) -> EstadoDeInicioAlAbrirSesion
    func abrirAjustesDeItemsDeInicio()
}
