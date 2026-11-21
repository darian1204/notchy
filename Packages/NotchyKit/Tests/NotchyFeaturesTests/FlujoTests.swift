import Foundation
import NotchyCore
import Testing

@testable import NotchyFeatures

@Suite struct FlujoTests {
    private let ahora = Date(timeIntervalSince1970: 1_800_000_000)

    private func evento(en minutos: Double, titulo: String = "Clase", todoElDia: Bool = false) -> EventoDeCalendario {
        let inicio = ahora.addingTimeInterval(minutos * 60)
        return EventoDeCalendario(
            id: titulo, titulo: titulo, inicio: inicio, fin: inicio.addingTimeInterval(3600),
            todoElDia: todoElDia, calendario: "Escuela", ubicacion: "Aula 4")
    }

    private func copiado(haceMinutos: Double) -> ElementoDePortapapeles {
        ElementoDePortapapeles(
            creado: ahora.addingTimeInterval(-haceMinutos * 60), tipo: .texto, texto: " #002060 ", huella: "h",
            bytes: 7)
    }

    @Test func sinNadaActivoNoHayElementos() {
        #expect(CalculoDeFlujo.elementos(.init(ahora: ahora)).isEmpty)
    }

    @Test func juntaLoActivoEnOrden() {
        let elementos = CalculoDeFlujo.elementos(
            .init(
                grabando: true, segundosGrabando: 768, eventos: [evento(en: 14)], archivosEnBandeja: 4,
                ultimoCopiado: copiado(haceMinutos: 2), cancion: "HEAVY", artista: "Omar Courtz", ahora: ahora))
        #expect(elementos.map(\.id) == ["grabando", "evento", "bandeja", "portapapeles", "musica"])
        #expect(elementos[0].valor == "12:48")
        #expect(elementos[1].valor == "en 14 min")
        #expect(elementos[2].detalle == "4 archivos")
        #expect(elementos[3].detalle == "#002060")
        #expect(elementos[3].valor == "hace 2 min")
    }

    @Test func ignoraEventosLejanosDeTodoElDiaOTerminados() {
        let elementos = CalculoDeFlujo.elementos(
            .init(
                eventos: [evento(en: 600), evento(en: 5, todoElDia: true), evento(en: -120)], ahora: ahora))
        #expect(elementos.isEmpty)
    }

    @Test func eligeElEventoMasCercano() {
        let elementos = CalculoDeFlujo.elementos(
            .init(eventos: [evento(en: 90, titulo: "Tarde"), evento(en: -10, titulo: "En curso")], ahora: ahora))
        #expect(elementos.first?.titulo == "En curso")
        #expect(elementos.first?.valor == "ahora")
    }

    @Test func loCopiadoViejoNoCuenta() {
        let elementos = CalculoDeFlujo.elementos(.init(ultimoCopiado: copiado(haceMinutos: 30), ahora: ahora))
        #expect(elementos.isEmpty)
    }

    @Test func copiadoDeImagenSinTextoMuestraRutaOImagen() {
        let conRuta = ElementoDePortapapeles(
            creado: ahora.addingTimeInterval(-60), tipo: .imagen, texto: "",
            rutaArchivo: "/tmp/captura.png", huella: "h1", bytes: 120)
        let sinRuta = ElementoDePortapapeles(
            creado: ahora.addingTimeInterval(-60), tipo: .imagen, texto: "   ",
            rutaArchivo: nil, huella: "h2", bytes: 120)
        let elemRuta = CalculoDeFlujo.elementos(.init(ultimoCopiado: conRuta, ahora: ahora))
        let elemSinRuta = CalculoDeFlujo.elementos(.init(ultimoCopiado: sinRuta, ahora: ahora))
        #expect(elemRuta.first?.detalle == "captura.png")
        #expect(elemSinRuta.first?.detalle == "Imagen")
    }

    @Test func cronometroConHoras() {
        #expect(CalculoDeFlujo.cronometro(3725) == "1:02:05")
        #expect(CalculoDeFlujo.cronometro(-3) == "0:00")
    }
}
