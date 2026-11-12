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
