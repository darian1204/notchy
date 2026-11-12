import Foundation
import NotchyTestSupport
import Testing

@testable import NotchyCore

@MainActor
@Suite struct AjustesTests {
    @Test func valoresPorDefecto() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        #expect(ajustes.pantalla == .conNotch)
        #expect(ajustes.atajo == .controlOpcionEspacio)
        #expect(ajustes.iconoEnBarraDeMenus == false)
        #expect(ajustes.ordenDeModulos.isEmpty)
        #expect(ajustes.estaActivo("inicio"))
    }

    @Test func losCambiosPersisten() {
        let almacen = AlmacenEnMemoria()
        let ajustes = Ajustes(almacen: almacen)
        ajustes.pantalla = .principal
        ajustes.atajo = .ninguno
        ajustes.iconoEnBarraDeMenus = true
        ajustes.ordenDeModulos = ["agenda", "inicio"]
        ajustes.activar("musica", false)

        let otra = Ajustes(almacen: almacen)
        #expect(otra.pantalla == .principal)
        #expect(otra.atajo == .ninguno)
        #expect(otra.iconoEnBarraDeMenus)
        #expect(otra.ordenDeModulos == ["agenda", "inicio"])
        #expect(!otra.estaActivo("musica"))
    }

    @Test func avisaSoloCuandoElValorCambia() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        var avisos = 0
        ajustes.observar { avisos += 1 }
        ajustes.pantalla = .conNotch
        #expect(avisos == 0)
        ajustes.pantalla = .principal
        #expect(avisos == 1)
    }

    @Test func ordenaConocidosPrimeroYNuevosAlFinal() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.ordenDeModulos = ["agenda", "borrado", "inicio"]
        #expect(ajustes.ordenar(["inicio", "musica", "agenda"]) == ["agenda", "inicio", "musica"])
    }

    @Test func unAlmacenNuevoQuedaSelladoConElEsquema() throws {
        let almacen = AlmacenEnMemoria()
        _ = Ajustes(almacen: almacen)
        let dato = try #require(almacen.leer("esquema"))
        #expect(try JSONDecoder().decode(Int.self, from: dato) == Ajustes.esquemaActual)
    }

    @Test func unEsquemaMasNuevoNoSeRebaja() throws {
        let almacen = AlmacenEnMemoria()
        almacen.guardar(try JSONEncoder().encode(99), en: "esquema")
        _ = Ajustes(almacen: almacen)
        let dato = try #require(almacen.leer("esquema"))
        #expect(try JSONDecoder().decode(Int.self, from: dato) == 99)
    }

    @Test func unValorIlegibleCaeAlValorPorDefecto() throws {
        let almacen = AlmacenEnMemoria()
        almacen.guardar(try JSONEncoder().encode("atajoQueYaNoExiste"), en: "atajo")
        #expect(Ajustes(almacen: almacen).atajo == .controlOpcionEspacio)
    }
}
