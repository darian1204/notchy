import NotchyCore
import NotchyDesign
import NotchyTestSupport
import Testing

@testable import NotchyIsland

@MainActor
@Suite struct RegistroDeModulosTests {
    @Test func arrancaLosActivosEnElOrdenDeLosAjustes() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.ordenDeModulos = ["agenda", "inicio"]
        let registro = RegistroDeModulos(ajustes: ajustes)
        let (inicio, agenda) = (ModuloFalso("inicio"), ModuloFalso("agenda"))
        registro.registrar(inicio)
        registro.registrar(agenda)
        #expect(registro.activos.map(\.identidad.id) == ["agenda", "inicio"])
        #expect(inicio.arranques == 1 && agenda.arranques == 1)
    }

    @Test func apagarYEncenderSeAplicaSinReiniciar() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        let registro = RegistroDeModulos(ajustes: ajustes)
        let agenda = ModuloFalso("agenda")
        registro.registrar(ModuloFalso("inicio"))
        registro.registrar(agenda)

        ajustes.activar("agenda", false)
        #expect(registro.activos.map(\.identidad.id) == ["inicio"])
        #expect(registro.todos.count == 2)
        #expect(agenda.detenciones == 1)

        ajustes.activar("agenda", true)
        #expect(registro.activos.count == 2)
        #expect(agenda.arranques == 2)
    }

    @Test func noRegistraDosVecesElMismoModulo() {
        let registro = RegistroDeModulos(ajustes: Ajustes(almacen: AlmacenEnMemoria()))
        registro.registrar(ModuloFalso("inicio"))
        registro.registrar(ModuloFalso("inicio"))
        #expect(registro.todos.count == 1)
    }

    @Test func detenerTodoDetieneSoloLoArrancado() {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.activar("agenda", false)
        let registro = RegistroDeModulos(ajustes: ajustes)
        let (inicio, agenda) = (ModuloFalso("inicio"), ModuloFalso("agenda"))
        registro.registrar(inicio)
        registro.registrar(agenda)
        registro.detenerTodo()
        #expect(inicio.detenciones == 1)
        #expect(agenda.detenciones == 0)
    }
}

@MainActor
@Suite struct CoordinadorDeIslaTests {
    private func coordinador(bus: BusDeEventos? = nil) -> (CoordinadorDeIsla, Ajustes) {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        let registro = RegistroDeModulos(ajustes: ajustes)
        registro.registrar(ModuloFalso("inicio", tamano: Medidas.inicio))
        registro.registrar(ModuloFalso("agenda"))
        // Los temporizadores vencen de inmediato: la prueba no depende del reloj.
        return (CoordinadorDeIsla(registro: registro, bus: bus, dormir: { _ in }), ajustes)
    }

    private func esperar(_ condicion: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condicion() {
            await Task.yield()
        }
    }

    @Test func elCursorAbreYCierraConSusTemporizadores() async {
        let (coordinador, _) = coordinador()
        coordinador.recibir(.cursorEntro)
        await esperar { coordinador.estado != .reposo }
        #expect(coordinador.estado == .expandido(modulo: "inicio"))
        #expect(coordinador.tamano == Medidas.inicio)

        coordinador.recibir(.cursorSalio)
        await esperar { coordinador.estado == .reposo }
        #expect(coordinador.estado == .reposo)
        #expect(coordinador.tamano == Medidas.notch)
    }

    @Test func salirAntesDeTiempoCancelaLaApertura() async {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        let registro = RegistroDeModulos(ajustes: ajustes)
        registro.registrar(ModuloFalso("inicio"))
        let coordinador = CoordinadorDeIsla(registro: registro, dormir: { try await Task.sleep(for: $0) })
        coordinador.recibir(.cursorEntro)
        coordinador.recibir(.cursorSalio)
        try? await Task.sleep(for: .milliseconds(250))
        #expect(coordinador.estado == .reposo)
    }

    @Test func apagarElModuloAbiertoLoCierraSinReiniciar() {
        let (coordinador, ajustes) = coordinador()
        coordinador.recibir(.elegirModulo("agenda"))
        #expect(coordinador.moduloAbierto?.identidad.id == "agenda")
        ajustes.activar("agenda", false)
        #expect(coordinador.estado == .expandido(modulo: "inicio"))
    }

    @Test func avisaYPublicaCadaCambioDeEstado() async {
        let bus = BusDeEventos()
        let eventos = await bus.suscribir(a: IslaCambioDeEstado.self)
        let (coordinador, _) = coordinador(bus: bus)
        var avisos = 0
        coordinador.observar { avisos += 1 }

        coordinador.recibir(.atajo)
        #expect(avisos == 1)
        #expect(coordinador.abiertaSinCursor)
        var iterador = eventos.makeAsyncIterator()
        #expect(await iterador.next() == IslaCambioDeEstado(moduloAbierto: "inicio"))
    }
}
