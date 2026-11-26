import CoreGraphics
import NotchyCore
import NotchyDesign
import NotchyTestSupport
import Testing

@testable import NotchyIsland

@MainActor
@Suite struct OrejasTests {
    private let musica = PeticionCompacta(modulo: "musica", prioridad: .musica)
    private let grabando = PeticionCompacta(modulo: "grabadora", prioridad: .grabando)

    private func maquina() -> MaquinaDeIsla {
        var maquina = MaquinaDeIsla()
        _ = maquina.recibir(.modulosDisponibles(["inicio", "musica", "grabadora"]))
        return maquina
    }

    @Test func laSegundaActividadVaALaBurbuja() {
        var maquina = maquina()
        _ = maquina.recibir(.pedirCompacto(musica))
        #expect(maquina.secundaria == nil)
        _ = maquina.recibir(.pedirCompacto(grabando))
        #expect(maquina.estado == .compacto(grabando))
        #expect(maquina.secundaria == musica)
        _ = maquina.recibir(.elegirModulo("inicio"))
        #expect(maquina.secundaria == nil)
    }

    @Test func conActividadElCursorAsomaAntesDeAbrir() {
        var maquina = maquina()
        _ = maquina.recibir(.pedirCompacto(musica))
        let efectos = maquina.recibir(.cursorEntro)
        #expect(maquina.asomando)
        #expect(efectos.contains(.programar(.abrir, MaquinaDeIsla.retardoAlAbrirDesdeCompacto)))
        _ = maquina.recibir(.cursorSalio)
        #expect(!maquina.asomando)
    }

    @Test func enReposoElCursorAbreRapidoYNoAsoma() {
        var maquina = maquina()
        let efectos = maquina.recibir(.cursorEntro)
        #expect(!maquina.asomando)
        #expect(efectos.contains(.programar(.abrir, MaquinaDeIsla.retardoAlAbrir)))
    }

    @Test func lasOrejasCrecenConLaActividad() {
        let geometria = GeometriaDeIsla(pantalla: .porDefecto)
        let tamano = geometria.tamano(de: .compacto(musica), expandido: nil, anchoDeOreja: 140)
        #expect(tamano == CGSize(width: 179 + 280, height: 32))
    }

    @Test func laBurbujaCabeEnElPanelAunConOrejasAmpliadas() {
        let geometria = GeometriaDeIsla(pantalla: .porDefecto)
        let cuerpo = geometria.tamano(de: .compacto(musica), expandido: nil, anchoDeOreja: 140)
        let burbuja = geometria.zonaDeBurbuja(cuerpo: cuerpo)
        #expect(geometria.marcoDelPanel.contains(burbuja))
        #expect(burbuja.width == 32 && burbuja.height == 32)
        #expect(burbuja.minX > geometria.zona(cuerpo).maxX + Medidas.hombro)
    }

    @Test func cadaActividadBreveDuraLoQueDebe() {
        #expect(TipoDeHUD.volumen.duracion == .milliseconds(1600))
        #expect(TipoDeHUD.cargando.duracion == .seconds(3))
        #expect(TipoDeHUD.airdropRecibido.modulo == "bandeja")
    }

    private func coordinador() -> CoordinadorDeIsla {
        let registro = RegistroDeModulos(ajustes: Ajustes(almacen: AlmacenEnMemoria()))
        for id in ["inicio", "musica", "grabadora"] { registro.registrar(ModuloFalso(id)) }
        return CoordinadorDeIsla(registro: registro, dormir: { _ in try await Task.sleep(for: .seconds(60)) })
    }

    @Test func laActividadBreveTomaLasOrejasYLaFijaPasaALaBurbuja() {
        let coordinador = coordinador()
        coordinador.recibir(.pedirCompacto(musica))
        coordinador.mostrarHUD(EstadoDeHUDSistema(tipo: .volumen, nivel: 0.5))
        guard case .breve = coordinador.orejas, case .modulo(let enBurbuja) = coordinador.burbuja else {
            Issue.record("Se esperaba la breve en las orejas y la música en la burbuja")
            return
        }
        #expect(enBurbuja.identidad.id == "musica")
    }

    @Test func laGrabacionNuncaSeOculta() {
        let coordinador = coordinador()
        coordinador.recibir(.pedirCompacto(grabando))
        coordinador.mostrarHUD(EstadoDeHUDSistema(tipo: .cargando, nivel: 0.8))
        guard case .modulo(let enOrejas, _) = coordinador.orejas, case .breve = coordinador.burbuja else {
            Issue.record("Se esperaba la grabación en las orejas y la breve en la burbuja")
            return
        }
        #expect(enOrejas.identidad.id == "grabadora")
    }
}
