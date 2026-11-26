import Foundation
import NotchyTestSupport
import Testing

@testable import NotchyCore

@MainActor
struct TemasDeColorTests {
    @Test func empiezaConLosOriginales() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        #expect(ajustes.temasDePanel.count == 7)
        #expect(ajustes.temasDeBarra.count == 9)
        #expect(ajustes.temaDePanelActual.id == "obsidiana")
        #expect(ajustes.temaDeBarraActual.fuente == .porModulo)
    }

    @Test func conservaElTemaElegidoConElFormatoDeAntes() throws {
        let almacen = AlmacenEnMemoria()
        almacen.guardar(try JSONEncoder().encode("bosque"), en: "temaPanel")
        almacen.guardar(try JSONEncoder().encode("rosaCuarzo"), en: "temaBarra")
        let ajustes = Ajustes(almacen: almacen)
        #expect(ajustes.temaDePanelActual.hex == TemaDePanel.bosque.hexBase)
        #expect(ajustes.temaDeBarraActual.hex == 0xD97D98)
    }

    @Test func agregarEligeElTemaYPersiste() {
        let almacen = AlmacenEnMemoria()
        let ajustes = Ajustes(almacen: almacen)
        let id = ajustes.agregarTema(en: .barra, nombre: "  Lima  ", hex: 0xB4FF39)
        #expect(ajustes.temaBarra == id)
        let otra = Ajustes(almacen: almacen)
        #expect(otra.temaDeBarraActual.nombre == "Lima")
        #expect(otra.temaDeBarraActual.hex == 0xB4FF39)
        #expect(otra.temasDeBarra.count == 10)
    }

    @Test func editarCambiaNombreYColorPeroNoElColorDeLaCaratula() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        var ciruela = ajustes.temasDePanel.first { $0.id == "ciruela" }!
        ciruela.nombre = ""
        ciruela.hex = 0x123456
        ajustes.actualizarTema(ciruela, en: .panel)
        let editada = ajustes.temasDePanel.first { $0.id == "ciruela" }!
        #expect(editada.nombre == "Tema sin nombre")
        #expect(editada.hex == 0x123456)

        var caratula = ajustes.temasDePanel.first { $0.id == "caratula" }!
        let antes = caratula.hex
        caratula.hex = 0xFFFFFF
        ajustes.actualizarTema(caratula, en: .panel)
        #expect(ajustes.temasDePanel.first { $0.id == "caratula" }!.hex == antes)
    }

    @Test func borrarElElegidoPasaAlPrimeroYNuncaQuedaVacia() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.elegirTema("bosque", en: .panel)
        ajustes.eliminarTema("bosque", de: .panel)
        #expect(!ajustes.temasDePanel.contains { $0.id == "bosque" })
        #expect(ajustes.temaPanel == ajustes.temasDePanel[0].id)

        for tema in ajustes.temasDePanel { ajustes.eliminarTema(tema.id, de: .panel) }
        #expect(ajustes.temasDePanel.count == 1)
        #expect(!ajustes.puedeEliminarTema(de: .panel))
    }

    @Test func restaurarDevuelveLosOriginalesYConservaLosPropios() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        let propio = ajustes.agregarTema(en: .panel, nombre: "Mío", hex: 0x101010)
        ajustes.eliminarTema("medianoche", de: .panel)
        var grafito = ajustes.temasDePanel.first { $0.id == "grafito" }!
        grafito.hex = 0xFF0000
        ajustes.actualizarTema(grafito, en: .panel)
        #expect(ajustes.originalesModificados(.panel))

        ajustes.restaurarTemasOriginales(.panel)
        #expect(!ajustes.originalesModificados(.panel))
        #expect(Array(ajustes.temasDePanel.prefix(7)) == ListaDeTemas.panel.originales)
        #expect(ajustes.temasDePanel.last?.id == propio)
    }

    @Test func restablecerTodoVuelveALosOriginales() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.agregarTema(en: .barra, nombre: "X", hex: 1)
        ajustes.restablecerValoresPorDefecto()
        #expect(ajustes.temasDeBarra == ListaDeTemas.barra.originales)
        #expect(ajustes.temaBarra == "clasico")
    }

    @Test func leeColoresHex() {
        #expect(TemaDeColor.hex(desde: "#d97d98") == 0xD97D98)
        #expect(TemaDeColor.hex(desde: " F0A ") == 0xFF00AA)
        #expect(TemaDeColor.hex(desde: "#12345G") == nil)
        #expect(TemaDeColor.hex(desde: "") == nil)
        #expect(TemaDeColor.texto(de: 0x0B1020) == "#0B1020")
    }
}
