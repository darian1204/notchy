import Carbon.HIToolbox
import NotchyCore
import Testing

@testable import NotchyPlatform

@MainActor
@Suite struct AtajosYOpenCodeTests {
    @Test func cadaAtajoTieneSuCombinacionDeCarbon() {
        #expect(RegistradorDeAtajosCarbon.combinacion(para: .ninguno) == nil)

        let espacio = RegistradorDeAtajosCarbon.combinacion(para: .controlOpcionEspacio)
        #expect(espacio?.codigo == UInt32(kVK_Space))
        #expect(espacio?.modificadores == UInt32(controlKey | optionKey))

        let controlN = RegistradorDeAtajosCarbon.combinacion(para: .controlOpcionN)
        #expect(controlN?.codigo == UInt32(kVK_ANSI_N))
        #expect(controlN?.modificadores == UInt32(controlKey | optionKey))

        let comandoN = RegistradorDeAtajosCarbon.combinacion(para: .opcionComandoN)
        #expect(comandoN?.codigo == UInt32(kVK_ANSI_N))
        #expect(comandoN?.modificadores == UInt32(optionKey | cmdKey))
    }

    @Test func detectorDeOpenCodeEligeLaPrimeraRutaEjecutable() {
        let encontrado = DetectorDeOpenCode.detectar(
            rutas: ["/no/existe", "/opt/homebrew/bin/opencode"],
            esEjecutable: { $0 == "/opt/homebrew/bin/opencode" }
        )
        #expect(encontrado == .instalado(ruta: "/opt/homebrew/bin/opencode"))

        let ausente = DetectorDeOpenCode.detectar(
            rutas: ["/no/existe"],
            esEjecutable: { _ in false }
        )
        #expect(ausente == .noEncontrado)
    }
}
