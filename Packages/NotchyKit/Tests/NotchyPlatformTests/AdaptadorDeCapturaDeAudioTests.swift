import Foundation
import Testing

@testable import NotchyPlatform

@Suite("Captura de audio: freno contra bucles de reinicio")
struct AdaptadorDeCapturaDeAudioTests {
    @Test
    func ignoraElDispositivoAgregadoPropio() {
        #expect(
            !FiltroDeDispositivosDeAudio.ameritaReinicio(
                nombre: "NotchySystemTap",
                uid: "NotchySystemTap-1234",
                tieneAudio: true
            )
        )
        #expect(
            !FiltroDeDispositivosDeAudio.ameritaReinicio(
                nombre: "NotchySystemTap",
                uid: "8F1C-sin-prefijo",
                tieneAudio: true
            )
        )
    }

    @Test
    func ignoraDispositivosSinAudio() {
        #expect(
            !FiltroDeDispositivosDeAudio.ameritaReinicio(
                nombre: "Cámara FaceTime HD",
                uid: "camara",
                tieneAudio: false
            )
        )
    }

    @Test
    func reiniciaConDispositivosDeAudioAjenos() {
        #expect(
            FiltroDeDispositivosDeAudio.ameritaReinicio(
                nombre: "Micrófono USB",
                uid: "AppleUSBAudioEngine:1",
                tieneAudio: true
            )
        )
    }

    @Test
    func limitadorFrenaAlPasarseDelMaximo() {
        var limitador = LimitadorDeReinicios(maximo: 3, ventana: 20)
        let resultados = [0.0, 1, 2, 3, 19].map { limitador.permitir(en: $0) }
        #expect(resultados == [true, true, true, false, false])
    }

    @Test
    func limitadorVuelveAPermitirAlPasarLaVentana() {
        var limitador = LimitadorDeReinicios(maximo: 2, ventana: 10)
        let resultados = [0.0, 1, 5, 10.5].map { limitador.permitir(en: $0) }
        #expect(resultados == [true, true, false, true])
    }

    @Test
    func limitadorSeReiniciaAlEmpezarOtraGrabacion() {
        var limitador = LimitadorDeReinicios(maximo: 1, ventana: 60)
        let antes = [0.0, 1].map { limitador.permitir(en: $0) }
        limitador.reiniciar()
        let despues = limitador.permitir(en: 2)
        #expect(antes == [true, false])
        #expect(despues)
    }
}
