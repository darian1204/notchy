import Foundation
import NotchyCore
import Testing

struct AgendaYAhoraSuenaCoreTests {
    @Test func detectaEnlacesDeLlamada() {
        let meet = EnlaceDeLlamada.detectar(en: [
            nil,
            "Reunión en https://meet.google.com/abc-defg-hij con el equipo",
        ])
        #expect(meet?.plataforma == .googleMeet)
        #expect(meet?.url.absoluteString == "https://meet.google.com/abc-defg-hij")

        let zoom = EnlaceDeLlamada.detectar(en: [
            "https://itesm.zoom.us/j/1234567890?pwd=xyz"
        ])
        #expect(zoom?.plataforma == .zoom)

        let teams = EnlaceDeLlamada.detectar(en: [
            "Unirse: https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0?context=1"
        ])
        #expect(teams?.plataforma == .teams)

        let ninguno = EnlaceDeLlamada.detectar(en: ["https://github.com/darian1204/notchy"])
        #expect(ninguno == nil)
    }

    @Test func progresoDeAhoraSuena() {
        let inicio = Date(timeIntervalSince1970: 1_000)
        let sonando = EstadoDeAhoraSuena(
            titulo: "Intro",
            artista: "The xx",
            reproduciendo: true,
            duracionSegundos: 180,
            transcurridoSegundos: 30,
            fechaDeMuestra: inicio
        )
        #expect(sonando.transcurridoActual(en: inicio.addingTimeInterval(15)) == 45)
        #expect(sonando.transcurridoActual(en: inicio.addingTimeInterval(500)) == 180)
        #expect(sonando.fraccionDeProgreso(en: inicio.addingTimeInterval(60)) == 0.5)

        let pausado = EstadoDeAhoraSuena(
            titulo: "Intro",
            artista: "The xx",
            reproduciendo: false,
            duracionSegundos: 180,
            transcurridoSegundos: 30,
            fechaDeMuestra: inicio
        )
        #expect(pausado.transcurridoActual(en: inicio.addingTimeInterval(50)) == 30)
    }
}
