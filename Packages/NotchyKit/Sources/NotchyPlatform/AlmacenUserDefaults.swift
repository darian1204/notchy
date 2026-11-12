import Foundation
import NotchyCore

/// Preferencias en `UserDefaults`. En depuración usa un dominio aparte para no mezclar
/// las preferencias de prueba con las reales, igual que la carpeta de datos (D-23).
public struct AlmacenUserDefaults: AlmacenDeAjustes, @unchecked Sendable {
    // `UserDefaults` es seguro entre hilos aunque no esté marcado como Sendable.
    private let defaults: UserDefaults

    public init(_ compilacion: NotchyInfo.Compilacion = NotchyInfo.compilacionActual) {
        switch compilacion {
        case .depuracion:
            defaults = UserDefaults(suiteName: NotchyInfo.identificador + ".dev") ?? .standard
        case .publicacion:
            defaults = .standard
        }
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func leer(_ clave: String) -> Data? {
        defaults.data(forKey: clave)
    }

    public func guardar(_ dato: Data?, en clave: String) {
        defaults.set(dato, forKey: clave)
    }
}
