import Foundation
import Observation

/// Donde se guardan las preferencias. El adaptador real usa `UserDefaults`; las pruebas, memoria.
public protocol AlmacenDeAjustes: Sendable {
    func leer(_ clave: String) -> Data?
    func guardar(_ dato: Data?, en clave: String)
}

/// Preferencias de la app. Cada cambio se guarda al momento y avisa a quien observe,
/// así se aplican sin reiniciar (ISL-8).
@MainActor
@Observable
public final class Ajustes {
    /// Versión del formato guardado. Sube cuando una preferencia cambia de forma y necesita migrarse.
    public static let esquemaActual = 1

    /// Orden elegido de los módulos. Un módulo que no aparece aquí va al final.
    public var ordenDeModulos: [String] {
        didSet { alCambiar(ordenDeModulos, oldValue, .ordenDeModulos) }
    }
    public var modulosApagados: Set<String> {
        didSet { alCambiar(modulosApagados, oldValue, .modulosApagados) }
    }
    public var pantalla: PantallaPreferida {
        didSet { alCambiar(pantalla, oldValue, .pantalla) }
    }
    public var atajo: AtajoDeIsla {
        didSet { alCambiar(atajo, oldValue, .atajo) }
    }
    public var iconoEnBarraDeMenus: Bool {
        didSet { alCambiar(iconoEnBarraDeMenus, oldValue, .iconoEnBarraDeMenus) }
    }

    @ObservationIgnored private let almacen: any AlmacenDeAjustes
    @ObservationIgnored private var observadores: [@MainActor () -> Void] = []

    public init(almacen: any AlmacenDeAjustes) {
        self.almacen = almacen
        Self.migrar(almacen)
        ordenDeModulos = Self.leer(.ordenDeModulos, de: almacen) ?? []
        modulosApagados = Self.leer(.modulosApagados, de: almacen) ?? []
        pantalla = Self.leer(.pantalla, de: almacen) ?? .conNotch
        atajo = Self.leer(.atajo, de: almacen) ?? .controlOpcionEspacio
        iconoEnBarraDeMenus = Self.leer(.iconoEnBarraDeMenus, de: almacen) ?? false
    }

    /// Llama a `accion` después de cada cambio guardado. Para quien no es una vista de SwiftUI.
    public func observar(_ accion: @escaping @MainActor () -> Void) {
        observadores.append(accion)
    }

    // MARK: Módulos

    public func estaActivo(_ id: String) -> Bool {
        !modulosApagados.contains(id)
    }

    public func activar(_ id: String, _ activo: Bool) {
        if activo {
            modulosApagados.remove(id)
        } else {
            modulosApagados.insert(id)
        }
    }

    /// Ordena los módulos disponibles: primero los del orden guardado, después los nuevos tal como llegan.
    public func ordenar(_ disponibles: [String]) -> [String] {
        let conocidos = ordenDeModulos.filter(disponibles.contains)
        return conocidos + disponibles.filter { !conocidos.contains($0) }
    }

    // MARK: Guardado

    enum Clave: String {
        case esquema, ordenDeModulos, modulosApagados, pantalla, atajo, iconoEnBarraDeMenus
    }

    private func alCambiar<Valor: Codable & Equatable>(_ nuevo: Valor, _ anterior: Valor, _ clave: Clave) {
        guard nuevo != anterior else { return }
        almacen.guardar(try? JSONEncoder().encode(nuevo), en: clave.rawValue)
        for accion in observadores {
            accion()
        }
    }

    private static func leer<Valor: Codable>(_ clave: Clave, de almacen: any AlmacenDeAjustes) -> Valor? {
        guard let dato = almacen.leer(clave.rawValue) else { return nil }
        // Un valor que ya no se puede leer (por ejemplo un caso de enum que se quitó) cae al valor por defecto.
        return try? JSONDecoder().decode(Valor.self, from: dato)
    }

    /// Sella el almacén con la versión del formato. Un almacén de una versión más nueva no se toca.
    static func migrar(_ almacen: any AlmacenDeAjustes) {
        let guardado: Int? = leer(.esquema, de: almacen)
        guard (guardado ?? 0) < esquemaActual else { return }
        // Aquí van los pasos de migración cuando exista un esquema 2.
        almacen.guardar(try? JSONEncoder().encode(esquemaActual), en: Clave.esquema.rawValue)
    }
}
