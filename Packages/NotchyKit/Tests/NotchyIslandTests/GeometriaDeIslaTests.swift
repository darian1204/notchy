import CoreGraphics
import NotchyCore
import NotchyDesign
import Testing

@testable import NotchyIsland

@Suite struct GeometriaDeIslaTests {
    private let conNotch = GeometriaDeIsla(pantalla: .porDefecto)
    private let sinNotch = GeometriaDeIsla(
        pantalla: PantallaDeIsla(
            marco: CGRect(x: 1470, y: 0, width: 1920, height: 1080), notch: nil, altoDeBarraDeMenus: 24))
    private let compacto = EstadoDeIsla.compacto(PeticionCompacta(modulo: "musica", prioridad: .musica))

    @Test func enReposoEsElNotch() {
        let zona = conNotch.zona(conNotch.tamano(de: .reposo, expandido: nil))
        #expect(zona == CGRect(x: 645.5, y: 924, width: 179, height: 32))
    }

    @Test func cadaEstadoMideLoQueDiceElDiseno() {
        #expect(conNotch.tamano(de: compacto, expandido: nil) == CGSize(width: 283, height: 32))
        #expect(conNotch.tamano(de: .aviso(modulo: "agenda"), expandido: nil) == CGSize(width: 440, height: 82))
        #expect(conNotch.tamano(de: .expandido(modulo: "inicio"), expandido: Medidas.inicio) == Medidas.inicio)
    }

    @Test func lasOrejasSeSumanAlNotchReal() {
        var pantalla = PantallaDeIsla.porDefecto
        pantalla.notch = CGSize(width: 200, height: 38)
        let tamano = GeometriaDeIsla(pantalla: pantalla).tamano(de: compacto, expandido: nil)
        #expect(tamano == CGSize(width: 304, height: 38))
    }

    @Test func elPanelFijoVaCentradoYPegadoArriba() {
        let panel = conNotch.marcoDelPanel
        #expect(panel.size == Medidas.panel)
        #expect(panel.midX == 735)
        #expect(panel.maxY == 956)
    }

    @Test func sinNotchEsUnaPildoraBajoLaBarraDeMenus() {
        #expect(!sinNotch.tieneNotch)
        let zona = sinNotch.zona(sinNotch.tamano(de: .reposo, expandido: nil))
        #expect(zona.size == Medidas.pildora)
        #expect(zona.midX == CGFloat(2430))
        #expect(zona.maxY == 1080 - 24 - Medidas.separacionDePildora)
        // En compacto no crece: las orejas caben dentro de la píldora.
        #expect(sinNotch.tamano(de: compacto, expandido: nil) == Medidas.pildora)
    }

    @Test func elCursorPegadoAlBordeSuperiorCuenta() {
        let zona = conNotch.zonaDeCursor(estado: .reposo, tamano: conNotch.tamanoDeReposo)
        #expect(GeometriaDeIsla.contiene(zona, CGPoint(x: 735, y: 956)))
        #expect(GeometriaDeIsla.contiene(zona, CGPoint(x: 735, y: 940)))
        #expect(!GeometriaDeIsla.contiene(zona, CGPoint(x: 735, y: 900)))
        #expect(!GeometriaDeIsla.contiene(zona, CGPoint(x: 600, y: 950)))
    }

    @Test func enReposoLaZonaDelCursorEsUnPocoMayorQueElNotch() {
        let reposo = conNotch.zonaDeCursor(estado: .reposo, tamano: conNotch.tamanoDeReposo)
        #expect(reposo.width == 191)
        let abierta = conNotch.zonaDeCursor(estado: .expandido(modulo: "inicio"), tamano: Medidas.inicio)
        #expect(abierta == conNotch.zona(Medidas.inicio))
    }
}
