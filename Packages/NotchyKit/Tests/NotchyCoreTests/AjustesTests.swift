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
        #expect(ajustes.iniciarAlAbrirSesion == true)
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

    @Test func estiloYAccesosPorDefectoYPersisten() {
        let almacen = AlmacenEnMemoria()
        let ajustes = Ajustes(almacen: almacen)
        #expect(ajustes.estiloDeIsla == .clasico)
        #expect(ajustes.accesosRapidos == ["colorpicker", "espejo", "grabadora"])

        ajustes.estiloDeIsla = .tarjetas
        ajustes.cambiarAcceso(en: 1, por: "clima")

        let otra = Ajustes(almacen: almacen)
        #expect(otra.estiloDeIsla == .tarjetas)
        #expect(otra.accesosRapidos == ["colorpicker", "clima", "grabadora"])
    }

    @Test func vidrioPorDefectoApagadoYPersiste() {
        let almacen = AlmacenEnMemoria()
        let ajustes = Ajustes(almacen: almacen)
        #expect(ajustes.vidrio == .apagado)
        ajustes.vidrio = .pildorasYTarjetas
        #expect(Ajustes(almacen: almacen).vidrio == .pildorasYTarjetas)
    }

    @Test func tintadoDelVidrioPersisteYSeLimita() {
        let almacen = AlmacenEnMemoria()
        let ajustes = Ajustes(almacen: almacen)
        #expect(ajustes.tintadoDelVidrio == Ajustes.tintadoPorDefecto)
        ajustes.tintadoDelVidrio = 0.8
        #expect(Ajustes(almacen: almacen).tintadoDelVidrio == 0.8)
        #expect(Ajustes.limitarTintado(1.7) == 1)
        #expect(Ajustes.limitarTintado(-3) == 0)
        #expect(Ajustes.limitarTintado(.nan) == Ajustes.tintadoPorDefecto)
        ajustes.restablecerValoresPorDefecto()
        #expect(ajustes.tintadoDelVidrio == Ajustes.tintadoPorDefecto)
    }

    @Test func cadaNivelDeVidrioIncluyeAlAnterior() {
        #expect(!EstiloDeVidrio.apagado.pildoras)
        #expect(EstiloDeVidrio.pildoras.pildoras && !EstiloDeVidrio.pildoras.tarjetas)
        #expect(EstiloDeVidrio.pildorasYTarjetas.tarjetas && !EstiloDeVidrio.pildorasYTarjetas.fondo)
        #expect(EstiloDeVidrio.completo.pildoras && EstiloDeVidrio.completo.tarjetas && EstiloDeVidrio.completo.fondo)
    }

    @Test func tarjetasDeInicioPorDefectoYPersisten() {
        let almacen = AlmacenEnMemoria()
        let ajustes = Ajustes(almacen: almacen)
        #expect(ajustes.tarjetasDeInicio.map(\.tarjeta) == [.musica, .inbox, .bandeja])
        ajustes.agregarTarjeta(.agenda, ancho: .angosta)
        ajustes.moverTarjeta(.agenda, -1)
        ajustes.cambiarAncho(de: .musica, a: .media)
        let otra = Ajustes(almacen: almacen)
        #expect(otra.tarjetasDeInicio.map(\.tarjeta) == [.musica, .inbox, .agenda, .bandeja])
        #expect(otra.tarjetasDeInicio.first?.ancho == .media)
    }

    @Test func tarjetasDeInicioEntreUnaYCuatroSinRepetir() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.agregarTarjeta(.agenda)
        ajustes.agregarTarjeta(.monitor)
        #expect(ajustes.tarjetasDeInicio.count == 4)
        #expect(!ajustes.puedeAgregarTarjeta)
        ajustes.agregarTarjeta(.portapapeles)
        #expect(ajustes.tarjetasDeInicio.count == 4)
        ajustes.agregarTarjeta(.musica)
        #expect(ajustes.tarjetasDeInicio.filter { $0.tarjeta == .musica }.count == 1)
        for tarjeta in TarjetaDeInicio.allCases { ajustes.quitarTarjeta(tarjeta) }
        #expect(ajustes.tarjetasDeInicio.count == 1)
        ajustes.tarjetasDeInicio = []
        #expect(ajustes.tarjetasDeInicio == Ajustes.tarjetasPorDefecto)
    }

    @Test func losAnchosPorDefectoLlenanLaFila() {
        // 680 de la isla − 24 de márgenes − 38 de accesos − 8 de separación − 2 × 8 entre tarjetas.
        let pesos = Ajustes.tarjetasPorDefecto.map(\.ancho.peso).reduce(0, +)
        #expect(pesos == 594)
    }

    @Test func cambiarAUnAccesoRepetidoIntercambia() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.cambiarAcceso(en: 0, por: "grabadora")
        #expect(ajustes.accesosRapidos == ["grabadora", "espejo", "colorpicker"])
        ajustes.cambiarAcceso(en: 9, por: "clima")
        #expect(ajustes.accesosRapidos == ["grabadora", "espejo", "colorpicker"])
    }

    @Test func losAccesosSeNormalizan() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.accesosRapidos = ["clima", "clima", ""]
        #expect(ajustes.accesosRapidos == ["clima", "colorpicker", "espejo"])
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

    @Test func restableceTodosLosValoresPorDefecto() {
        let almacen = AlmacenEnMemoria()
        let ajustes = Ajustes(almacen: almacen)
        ajustes.pantalla = .principal
        ajustes.atajo = .ninguno
        ajustes.iconoEnBarraDeMenus = true
        ajustes.iniciarAlAbrirSesion = false
        ajustes.temaPanel = .bosque
        ajustes.estiloDeIsla = .tarjetas
        ajustes.vidrio = .completo
        ajustes.rutaVaultObsidian = "/Users/secreto/MiVault"
        ajustes.activar("agenda", false)

        ajustes.restablecerValoresPorDefecto()

        #expect(ajustes.pantalla == .conNotch)
        #expect(ajustes.atajo == .controlOpcionEspacio)
        #expect(ajustes.iconoEnBarraDeMenus == false)
        #expect(ajustes.iniciarAlAbrirSesion == true)
        #expect(ajustes.temaPanel == .obsidiana)
        #expect(ajustes.estiloDeIsla == .clasico)
        #expect(ajustes.vidrio == .apagado)
        #expect(ajustes.rutaVaultObsidian == Ajustes.rutaVaultPorDefecto)
        #expect(ajustes.estaActivo("agenda"))
    }
}
