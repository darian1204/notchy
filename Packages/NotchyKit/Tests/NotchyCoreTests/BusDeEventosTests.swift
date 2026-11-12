import Testing

@testable import NotchyCore

private struct Saludo: Evento, Equatable {
    let texto: String
}

private struct Otro: Evento {}

@Suite struct BusDeEventosTests {
    @Test func entregaSoloElTipoPedido() async {
        let bus = BusDeEventos()
        let flujo = await bus.suscribir(a: Saludo.self)
        await bus.publicar(Otro())
        await bus.publicar(Saludo(texto: "hola"))
        var iterador = flujo.makeAsyncIterator()
        #expect(await iterador.next() == Saludo(texto: "hola"))
    }

    @Test func variosSuscriptoresRecibenLoMismo() async {
        let bus = BusDeEventos()
        let uno = await bus.suscribir(a: Saludo.self)
        let dos = await bus.suscribir(a: Saludo.self)
        await bus.publicar(Saludo(texto: "a"))
        var primero = uno.makeAsyncIterator()
        var segundo = dos.makeAsyncIterator()
        #expect(await primero.next()?.texto == "a")
        #expect(await segundo.next()?.texto == "a")
    }

    @Test func publicarSinSuscriptoresNoFalla() async {
        let bus = BusDeEventos()
        await bus.publicar(Saludo(texto: "nadie"))
        #expect(await bus.cantidadDeSuscriptores(de: Saludo.self) == 0)
    }

    @Test func alSoltarElFlujoSeQuitaLaSuscripcion() async throws {
        let bus = BusDeEventos()
        do {
            let flujo = await bus.suscribir(a: Saludo.self)
            #expect(await bus.cantidadDeSuscriptores(de: Saludo.self) == 1)
            _ = flujo
        }
        for _ in 0..<50 where await bus.cantidadDeSuscriptores(de: Saludo.self) != 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await bus.cantidadDeSuscriptores(de: Saludo.self) == 0)
    }
}
