import NotchyCore
import NotchyTestSupport
import Testing

@testable import NotchyIsland

@MainActor
@Suite struct ControladorDeAtajoTests {
    private func armar() -> (CoordinadorDeIsla, Ajustes, RegistradorDeAtajosFalso, ControladorDeAtajo) {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        let registro = RegistroDeModulos(ajustes: ajustes)
        registro.registrar(ModuloFalso("inicio"))
        let coordinador = CoordinadorDeIsla(registro: registro, dormir: { _ in })
        let registrador = RegistradorDeAtajosFalso()
        let controlador = ControladorDeAtajo(coordinador: coordinador, ajustes: ajustes, registrador: registrador)
        return (coordinador, ajustes, registrador, controlador)
    }

    @Test func registraElAtajoInicialYLoActualizaAlCambiarAjustes() {
        let (_, ajustes, registrador, controlador) = armar()
        #expect(controlador.atajoActivo)
        #expect(registrador.atajoRegistrado == .controlOpcionEspacio)

        ajustes.atajo = .opcionComandoN
        #expect(registrador.atajoRegistrado == .opcionComandoN)

        ajustes.atajo = .ninguno
        #expect(registrador.atajoRegistrado == .ninguno)
        controlador.detener()
    }

    @Test func elAtajoAbreYCierraLaIslaYPrendeEscapeSoloSinCursor() {
        let (coordinador, _, registrador, controlador) = armar()
        defer { controlador.detener() }
        #expect(coordinador.estado == .reposo)
        #expect(!registrador.escapeActivo)

        registrador.simularAtajo()
        #expect(coordinador.estado == .expandido(modulo: "inicio"))
        #expect(registrador.escapeActivo)

        registrador.simularEscape()
        #expect(coordinador.estado == .reposo)
        #expect(!registrador.escapeActivo)
    }

    @Test func abrirConCursorNoActivaEscapeGlobal() async {
        let (coordinador, _, registrador, controlador) = armar()
        defer { controlador.detener() }
        coordinador.recibir(.cursorEntro)
        for _ in 0..<50 where coordinador.estado == .reposo {
            await Task.yield()
        }
        #expect(coordinador.estado == .expandido(modulo: "inicio"))
        #expect(!registrador.escapeActivo)
    }
}
