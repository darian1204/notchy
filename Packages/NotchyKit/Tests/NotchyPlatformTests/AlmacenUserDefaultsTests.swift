import Foundation
import NotchyCore
import Testing

@testable import NotchyPlatform

@MainActor
@Suite struct AlmacenUserDefaultsTests {
    @Test func cumpleElContratoDelAlmacen() throws {
        let dominio = "dev.darian.notchy.pruebas.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: dominio))
        defer { defaults.removePersistentDomain(forName: dominio) }

        let almacen = AlmacenUserDefaults(defaults: defaults)
        #expect(almacen.leer("nada") == nil)
        almacen.guardar(Data([1, 2, 3]), en: "dato")
        #expect(almacen.leer("dato") == Data([1, 2, 3]))
        almacen.guardar(nil, en: "dato")
        #expect(almacen.leer("dato") == nil)
    }

    @Test func losAjustesSobrevivenEnUserDefaults() throws {
        let dominio = "dev.darian.notchy.pruebas.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: dominio))
        defer { defaults.removePersistentDomain(forName: dominio) }

        Ajustes(almacen: AlmacenUserDefaults(defaults: defaults)).pantalla = .principal
        #expect(Ajustes(almacen: AlmacenUserDefaults(defaults: defaults)).pantalla == .principal)
    }
}
