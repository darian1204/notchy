import NotchyCore
import Synchronization

/// Proveedor de permisos en memoria para pruebas.
public final class ProveedorDePermisosFalso: ProveedorDePermisos {
    private let estados: Mutex<[PermisoDelSistema: EstadoDePermiso]>
    private let respuestasAlPedir: Mutex<[PermisoDelSistema: EstadoDePermiso]>
    private let pedidos = Mutex<[PermisoDelSistema]>([])

    public init(
        iniciales: [PermisoDelSistema: EstadoDePermiso] = [:],
        alPedir: [PermisoDelSistema: EstadoDePermiso] = [:]
    ) {
        estados = Mutex(iniciales)
        respuestasAlPedir = Mutex(alPedir)
    }

    public func estado(de permiso: PermisoDelSistema) -> EstadoDePermiso {
        estados.withLock { $0[permiso] ?? .sinPedir }
    }

    public func pedir(_ permiso: PermisoDelSistema) async -> EstadoDePermiso {
        pedidos.withLock { $0.append(permiso) }
        let nuevo = respuestasAlPedir.withLock { $0[permiso] ?? .concedido }
        estados.withLock { $0[permiso] = nuevo }
        return nuevo
    }

    public func fijar(_ permiso: PermisoDelSistema, _ estado: EstadoDePermiso) {
        estados.withLock { $0[permiso] = estado }
    }

    public var permisosPedidos: [PermisoDelSistema] {
        pedidos.withLock { $0 }
    }
}

/// Servicio falso de inicio al abrir sesión en memoria para pruebas (SIS-3).
public final class ServicioDeInicioAlAbrirSesionFalso: ServicioDeInicioAlAbrirSesion {
    private let estadoActual: Mutex<EstadoDeInicioAlAbrirSesion>
    private let respuestaAlActivar: EstadoDeInicioAlAbrirSesion
    private let aplicaciones = Mutex<[Bool]>([])
    private let aperturasAjustes = Mutex<Int>(0)

    public init(
        inicial: EstadoDeInicioAlAbrirSesion = .inactivo,
        alActivar: EstadoDeInicioAlAbrirSesion = .activo
    ) {
        estadoActual = Mutex(inicial)
        respuestaAlActivar = alActivar
    }

    public func estado() -> EstadoDeInicioAlAbrirSesion {
        estadoActual.withLock { $0 }
    }

    @discardableResult
    public func aplicar(activo: Bool) -> EstadoDeInicioAlAbrirSesion {
        aplicaciones.withLock { $0.append(activo) }
        let nuevo: EstadoDeInicioAlAbrirSesion = activo ? respuestaAlActivar : .inactivo
        estadoActual.withLock { $0 = nuevo }
        return nuevo
    }

    public func abrirAjustesDeItemsDeInicio() {
        aperturasAjustes.withLock { $0 += 1 }
    }

    public func fijarEstado(_ nuevo: EstadoDeInicioAlAbrirSesion) {
        estadoActual.withLock { $0 = nuevo }
    }

    public var historialAplicado: [Bool] {
        aplicaciones.withLock { $0 }
    }

    public var vecesAbrioAjustes: Int {
        aperturasAjustes.withLock { $0 }
    }
}
