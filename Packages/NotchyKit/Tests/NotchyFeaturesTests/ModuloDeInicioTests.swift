import NotchyCore
import NotchyDesign
import Testing

@testable import NotchyFeatures

@MainActor
@Suite struct ModuloDeInicioTests {
    @Test func esElModuloQueAbreElHover() {
        let inicio = ModuloDeInicio()
        #expect(inicio.identidad.id == ModulosBase.inicio)
        #expect(inicio.tamanoExpandido == Medidas.inicio)
        #expect(inicio.salud == .listo)
    }
}
