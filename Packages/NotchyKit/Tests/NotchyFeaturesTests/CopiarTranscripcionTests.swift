import NotchyCore
import Testing

@testable import NotchyFeatures

@Suite("Copiar transcripción de reunión")
struct CopiarTranscripcionTests {
    @Test
    func armaTextoConTituloHoraYFuente() {
        let segmentos = [
            SegmentoDeTranscripcion(
                reunionID: "r", fuente: .microfono, inicioSegundos: 5, finSegundos: 8, texto: " Hola equipo "),
            SegmentoDeTranscripcion(
                reunionID: "r", fuente: .sistema, inicioSegundos: 72, finSegundos: 75, texto: "Buenas"),
            SegmentoDeTranscripcion(
                reunionID: "r", fuente: .sistema, inicioSegundos: 80, finSegundos: 81, texto: "   "),
        ]
        let texto = ModeloDeGrabadora.textoDeTranscripcion(segmentos, titulo: "Sync")
        let tu = FuenteDeAudio.microfono.etiqueta
        let otros = FuenteDeAudio.sistema.etiqueta
        #expect(texto == "Sync\n\n[00:05] \(tu): Hola equipo\n[01:12] \(otros): Buenas")
    }

    @Test
    func sinTituloNiSegmentosQuedaVacio() {
        #expect(ModeloDeGrabadora.textoDeTranscripcion([], titulo: "  ").isEmpty)
    }
}
