import NotchyCore
import Testing

@testable import NotchyIsland

@Suite struct MaquinaDeIslaTests {
    private func maquina(_ modulos: [String] = ["inicio", "agenda"]) -> MaquinaDeIsla {
        var maquina = MaquinaDeIsla()
        _ = maquina.recibir(.modulosDisponibles(modulos))
        return maquina
    }

    // MARK: Hover (ISL-3)

    @Test func elCursorAbreTrasElRetardo() {
        var maquina = maquina()
        #expect(maquina.recibir(.cursorEntro).contains(.programar(.abrir, .milliseconds(120))))
        #expect(maquina.estado == .reposo)
        _ = maquina.recibir(.vencio(.abrir))
        #expect(maquina.estado == .expandido(modulo: "inicio"))
    }

    @Test func pasarDeLargoNoAbre() {
        var maquina = maquina()
        _ = maquina.recibir(.cursorEntro)
        #expect(maquina.recibir(.cursorSalio).contains(.cancelar(.abrir)))
        // Aunque el temporizador alcanzara a vencer, el cursor ya no está.
        _ = maquina.recibir(.vencio(.abrir))
        #expect(maquina.estado == .reposo)
    }

    @Test func cierraTrasElRetardoAlSalir() {
        var maquina = maquina()
        _ = maquina.recibir(.cursorEntro)
        _ = maquina.recibir(.vencio(.abrir))
        #expect(maquina.recibir(.cursorSalio).contains(.programar(.cerrar, .milliseconds(350))))
        #expect(maquina.estado == .expandido(modulo: "inicio"))
        _ = maquina.recibir(.vencio(.cerrar))
        #expect(maquina.estado == .reposo)
    }

    @Test func espejoSeQuedaAbiertoDosSegundosAlPerderElCursor() {
        var maquina = maquina(["inicio", "espejo"])
        _ = maquina.recibir(.cursorEntro)
        _ = maquina.recibir(.vencio(.abrir))
        _ = maquina.recibir(.elegirModulo("espejo"))
        #expect(maquina.recibir(.cursorSalio).contains(.programar(.cerrar, .seconds(2))))
        #expect(maquina.estado == .expandido(modulo: "espejo"))
        _ = maquina.recibir(.vencio(.cerrar))
        #expect(maquina.estado == .reposo)
    }

    @Test func volverAEntrarCancelaElCierre() {
        var maquina = maquina()
        _ = maquina.recibir(.cursorEntro)
        _ = maquina.recibir(.vencio(.abrir))
        _ = maquina.recibir(.cursorSalio)
        #expect(maquina.recibir(.cursorEntro) == [.cancelar(.cerrar)])
        _ = maquina.recibir(.vencio(.cerrar))
        #expect(maquina.estado == .expandido(modulo: "inicio"))
    }

    @Test func clicFueraYEscCierranAlInstante() {
        for entrada in [MaquinaDeIsla.Entrada.clicFuera, .escape] {
            var maquina = maquina()
            _ = maquina.recibir(.cursorEntro)
            _ = maquina.recibir(.vencio(.abrir))
            #expect(
                maquina.recibir(entrada) == [
                    .cancelar(.abrir), .cancelar(.cerrar), .programar(.olvidar, .seconds(10)),
                ])
            #expect(maquina.estado == .reposo)
        }
    }

    @Test func abrirYCerrarVeinteVecesTerminaEnReposo() {
        var maquina = maquina()
        for _ in 0..<20 {
            _ = maquina.recibir(.cursorEntro)
            _ = maquina.recibir(.vencio(.abrir))
            #expect(maquina.estado == .expandido(modulo: "inicio"))
            _ = maquina.recibir(.cursorSalio)
            _ = maquina.recibir(.vencio(.cerrar))
            #expect(maquina.estado == .reposo)
        }
    }

    @Test func sinModulosElCursorNoHaceNada() {
        var maquina = maquina([])
        #expect(maquina.recibir(.cursorEntro).isEmpty)
        _ = maquina.recibir(.vencio(.abrir))
        _ = maquina.recibir(.atajo)
        #expect(maquina.estado == .reposo)
    }

    @Test func sinInicioAbreElPrimerModulo() {
        var maquina = maquina(["agenda", "musica"])
        _ = maquina.recibir(.cursorEntro)
        _ = maquina.recibir(.vencio(.abrir))
        #expect(maquina.estado == .expandido(modulo: "agenda"))
    }

    // MARK: Atajo

    @Test func elAtajoAbreYCierra() {
        var maquina = maquina()
        _ = maquina.recibir(.atajo)
        #expect(maquina.estado == .expandido(modulo: "inicio"))
        #expect(maquina.abiertaSinCursor)
        _ = maquina.recibir(.atajo)
        #expect(maquina.estado == .reposo)
        #expect(!maquina.abiertaSinCursor)
    }

    @Test func abiertaConAtajoSigueAlCursorCuandoLaVisita() {
        var maquina = maquina()
        _ = maquina.recibir(.atajo)
        _ = maquina.recibir(.cursorEntro)
        #expect(!maquina.abiertaSinCursor)
        _ = maquina.recibir(.cursorSalio)
        _ = maquina.recibir(.vencio(.cerrar))
        #expect(maquina.estado == .reposo)
    }

    // MARK: Módulos

    @Test func elegirModuloCambiaSinCerrar() {
        var maquina = maquina()
        _ = maquina.recibir(.cursorEntro)
        _ = maquina.recibir(.vencio(.abrir))
        _ = maquina.recibir(.elegirModulo("agenda"))
        #expect(maquina.estado == .expandido(modulo: "agenda"))
        _ = maquina.recibir(.elegirModulo("no-existe"))
        #expect(maquina.estado == .expandido(modulo: "agenda"))
    }

    @Test func apagarElModuloAbiertoCaeAlInicioOCierra() {
        var maquina = maquina()
        _ = maquina.recibir(.elegirModulo("agenda"))
        _ = maquina.recibir(.modulosDisponibles(["inicio"]))
        #expect(maquina.estado == .expandido(modulo: "inicio"))
        _ = maquina.recibir(.modulosDisponibles([]))
        #expect(maquina.estado == .reposo)
    }

    // MARK: Último módulo

    @Test func reabrirAntesDeDiezSegundosVuelveAlUltimoModulo() {
        var maquina = maquina()
        _ = maquina.recibir(.atajo)
        _ = maquina.recibir(.elegirModulo("agenda"))
        #expect(maquina.recibir(.escape).contains(.programar(.olvidar, .seconds(10))))
        _ = maquina.recibir(.cursorEntro)
        #expect(maquina.recibir(.vencio(.abrir)).contains(.cancelar(.olvidar)))
        #expect(maquina.estado == .expandido(modulo: "agenda"))
    }

    @Test func despuesDeDiezSegundosVuelveAlInicio() {
        var maquina = maquina()
        _ = maquina.recibir(.atajo)
        _ = maquina.recibir(.elegirModulo("agenda"))
        _ = maquina.recibir(.escape)
        _ = maquina.recibir(.vencio(.olvidar))
        _ = maquina.recibir(.atajo)
        #expect(maquina.estado == .expandido(modulo: "inicio"))
    }

    @Test func elUltimoModuloApagadoSeOlvida() {
        var maquina = maquina()
        _ = maquina.recibir(.atajo)
        _ = maquina.recibir(.elegirModulo("agenda"))
        _ = maquina.recibir(.escape)
        _ = maquina.recibir(.modulosDisponibles(["inicio"]))
        _ = maquina.recibir(.atajo)
        #expect(maquina.estado == .expandido(modulo: "inicio"))
    }

    @Test func abrirOtroModuloDirectoReemplazaElRecordado() {
        var maquina = maquina(["inicio", "agenda", "musica"])
        _ = maquina.recibir(.atajo)
        _ = maquina.recibir(.elegirModulo("agenda"))
        _ = maquina.recibir(.escape)
        _ = maquina.recibir(.elegirModulo("musica"))
        _ = maquina.recibir(.escape)
        _ = maquina.recibir(.atajo)
        #expect(maquina.estado == .expandido(modulo: "musica"))
    }

    // MARK: Compacto (ISL-6)

    @Test func enCompactoGanaLaMayorPrioridad() {
        var maquina = maquina(["musica", "agenda", "grabadora", "agente"])
        let musica = PeticionCompacta(modulo: "musica", prioridad: .musica)
        let reunion = PeticionCompacta(modulo: "agenda", prioridad: .reunionProxima)
        let grabando = PeticionCompacta(modulo: "grabadora", prioridad: .grabando)
        let agente = PeticionCompacta(modulo: "agente", prioridad: .agenteEscuchando)

        _ = maquina.recibir(.pedirCompacto(musica))
        #expect(maquina.estado == .compacto(musica))
        _ = maquina.recibir(.pedirCompacto(grabando))
        _ = maquina.recibir(.pedirCompacto(reunion))
        #expect(maquina.estado == .compacto(grabando))
        _ = maquina.recibir(.pedirCompacto(agente))
        #expect(maquina.estado == .compacto(agente))

        _ = maquina.recibir(.retirarCompacto(modulo: "agente"))
        _ = maquina.recibir(.retirarCompacto(modulo: "grabadora"))
        #expect(maquina.estado == .compacto(reunion))
        _ = maquina.recibir(.retirarCompacto(modulo: "agenda"))
        _ = maquina.recibir(.retirarCompacto(modulo: "musica"))
        #expect(maquina.estado == .reposo)
    }

    @Test func unModuloSoloTieneUnaPeticionCompacta() {
        var maquina = maquina(["grabadora"])
        _ = maquina.recibir(.pedirCompacto(PeticionCompacta(modulo: "grabadora", prioridad: .grabando)))
        _ = maquina.recibir(.pedirCompacto(PeticionCompacta(modulo: "grabadora", prioridad: .musica)))
        _ = maquina.recibir(.retirarCompacto(modulo: "grabadora"))
        #expect(maquina.estado == .reposo)
    }

    @Test func alCerrarVuelveAlCompactoPendiente() {
        var maquina = maquina(["inicio", "grabadora"])
        let grabando = PeticionCompacta(modulo: "grabadora", prioridad: .grabando)
        _ = maquina.recibir(.pedirCompacto(grabando))
        _ = maquina.recibir(.atajo)
        #expect(maquina.estado == .expandido(modulo: "inicio"))
        _ = maquina.recibir(.escape)
        #expect(maquina.estado == .compacto(grabando))
    }

    @Test func apagarUnModuloRetiraSuCompacto() {
        var maquina = maquina(["inicio", "musica"])
        _ = maquina.recibir(.pedirCompacto(PeticionCompacta(modulo: "musica", prioridad: .musica)))
        _ = maquina.recibir(.modulosDisponibles(["inicio"]))
        #expect(maquina.estado == .reposo)
    }

    // MARK: Aviso

    @Test func elAvisoSeMuestraSeisSegundos() {
        var maquina = maquina(["inicio", "agenda"])
        #expect(maquina.recibir(.mostrarAviso(modulo: "agenda")) == [.programar(.aviso, .seconds(6))])
        #expect(maquina.estado == .aviso(modulo: "agenda"))
        _ = maquina.recibir(.vencio(.aviso))
        #expect(maquina.estado == .reposo)
    }

    @Test func fijadaSeAbreYNoSeCierraConCursorClicNiEsc() {
        var maquina = maquina()
        _ = maquina.recibir(.fijar(true))
        #expect(maquina.estado == .expandido(modulo: "inicio"))
        _ = maquina.recibir(.cursorEntro)
        let efectos = maquina.recibir(.cursorSalio)
        #expect(!efectos.contains(.programar(.cerrar, MaquinaDeIsla.retardoAlCerrar)))
        _ = maquina.recibir(.vencio(.cerrar))
        _ = maquina.recibir(.clicFuera)
        _ = maquina.recibir(.escape)
        #expect(maquina.estado == .expandido(modulo: "inicio"))
    }

    @Test func fijadaRespetaElModuloAbierto() {
        var maquina = maquina()
        _ = maquina.recibir(.elegirModulo("agenda"))
        _ = maquina.recibir(.fijar(true))
        #expect(maquina.estado == .expandido(modulo: "agenda"))
    }

    @Test func elAtajoCierraAunqueEsteFijada() {
        var maquina = maquina()
        _ = maquina.recibir(.fijar(true))
        _ = maquina.recibir(.atajo)
        #expect(maquina.estado == .reposo)
    }

    @Test func alSoltarlaSinCursorProgramaElCierre() {
        var maquina = maquina()
        _ = maquina.recibir(.fijar(true))
        let efectos = maquina.recibir(.fijar(false))
        #expect(efectos.contains(.programar(.cerrar, MaquinaDeIsla.retardoAlCerrar)))
        _ = maquina.recibir(.vencio(.cerrar))
        #expect(maquina.estado == .reposo)
    }

    @Test func alSoltarlaConElCursorEncimaSigueAbierta() {
        var maquina = maquina()
        _ = maquina.recibir(.fijar(true))
        _ = maquina.recibir(.cursorEntro)
        #expect(maquina.recibir(.fijar(false)).isEmpty)
        #expect(maquina.estado == .expandido(modulo: "inicio"))
    }
}
