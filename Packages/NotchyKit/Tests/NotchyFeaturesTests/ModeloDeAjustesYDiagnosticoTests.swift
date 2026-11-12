import NotchyCore
import NotchyStorage
import NotchyTestSupport
import Testing

@testable import NotchyFeatures

@MainActor
@Suite struct ModeloDeAjustesYDiagnosticoTests {
    private let modulos = [
        IdentidadDeModulo(id: "inicio", nombre: "Inicio", icono: "house.fill", color: 0xFFFFFF, lado: .izquierda),
        IdentidadDeModulo(id: "agenda", nombre: "Agenda", icono: "calendar", color: 0x5AA9FF, lado: .izquierda),
        IdentidadDeModulo(id: "musica", nombre: "Música", icono: "music.note", color: 0x3DDC97, lado: .izquierda),
    ]

    @Test func reordenaYActivaModulosEnAjustes() throws {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        let permisos = ProveedorDePermisosFalso()
        let base = try BaseDeDatos.enMemoria()
        let modelo = ModeloDeAjustesYDiagnostico(
            ajustes: ajustes,
            modulosDisponibles: modulos,
            proveedorDePermisos: permisos,
            consultarBase: { ModeloDeAjustesYDiagnostico.diagnosticarBase(base) },
            consultarOpenCode: { .instalado(ruta: "/opt/homebrew/bin/opencode") }
        )

        #expect(modelo.modulosOrdenados.map(\.id) == ["inicio", "agenda", "musica"])
        modelo.moverModuloAbajo("inicio")
        #expect(modelo.modulosOrdenados.map(\.id) == ["agenda", "inicio", "musica"])
        #expect(ajustes.ordenDeModulos == ["agenda", "inicio", "musica"])

        modelo.moverModuloArriba("musica")
        #expect(modelo.modulosOrdenados.map(\.id) == ["agenda", "musica", "inicio"])

        modelo.cambiarModuloActivo("agenda", false)
        #expect(!modelo.estaModuloActivo("agenda"))
        #expect(!ajustes.estaActivo("agenda"))
    }

    @Test func pidePermisosYPublicaEvento() async throws {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        let permisos = ProveedorDePermisosFalso(
            iniciales: [.microfono: .sinPedir, .camara: .denegado],
            alPedir: [.microfono: .concedido]
        )
        let bus = BusDeEventos()
        let flujo = await bus.suscribir(a: CambioDePermiso.self)
        let base = try BaseDeDatos.enMemoria()

        let modelo = ModeloDeAjustesYDiagnostico(
            ajustes: ajustes,
            modulosDisponibles: modulos,
            proveedorDePermisos: permisos,
            consultarBase: { ModeloDeAjustesYDiagnostico.diagnosticarBase(base) },
            consultarOpenCode: { .noEncontrado },
            bus: bus
        )

        #expect(modelo.estado(de: .microfono) == .sinPedir)
        #expect(modelo.estado(de: .camara) == .denegado)
        #expect(modelo.diagnosticoDeBase.estaBien)
        #expect(!modelo.estadoDeOpenCode.estaListo)

        await modelo.pedirPermiso(.microfono)
        #expect(modelo.estado(de: .microfono) == .concedido)
        #expect(permisos.permisosPedidos == [.microfono])

        var iterador = flujo.makeAsyncIterator()
        let evento = await iterador.next()
        #expect(evento == CambioDePermiso(permiso: .microfono, estado: .concedido))
    }

    @Test func diagnosticaBaseAusente() {
        let diagnostico = ModeloDeAjustesYDiagnostico.diagnosticarBase(nil)
        #expect(!diagnostico.estaBien)
        #expect(diagnostico.comoArreglarlo != nil)
    }
}
