import Foundation
import NotchyCore
import Synchronization

/// Almacén de preferencias que vive en memoria.
public final class AlmacenEnMemoria: AlmacenDeAjustes {
    private let datos = Mutex<[String: Data]>([:])

    public init() {}

    public func leer(_ clave: String) -> Data? {
        datos.withLock { $0[clave] }
    }

    public func guardar(_ dato: Data?, en clave: String) {
        datos.withLock { $0[clave] = dato }
    }

    public var claves: Set<String> {
        datos.withLock { Set($0.keys) }
    }
}
