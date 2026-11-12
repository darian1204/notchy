import Foundation
import NotchyCore
import Testing

@testable import NotchyStorage

@Suite struct PortapapelesYBandejaStorageTests {
    @Test func buscaSinAcentosYFiltraPorTipoOrdenandoFijadosPrimero() throws {
        let repo = RepositorioDePortapapeles(try BaseDeDatos.enMemoria())
        let t0 = Date(timeIntervalSince1970: 1_000)

        try repo.registrar(
            ElementoDePortapapeles(
                id: "1",
                creado: t0,
                tipo: .texto,
                texto: "Reunión de planeación del jueves",
                huella: "h1",
                appOrigen: "Notas",
                bytes: 32
            ))
        try repo.registrar(
            ElementoDePortapapeles(
                id: "2",
                creado: t0.addingTimeInterval(10),
                tipo: .enlace,
                texto: "https://supabase.com/dashboard",
                huella: "h2",
                appOrigen: "Safari",
                bytes: 30
            ))

        let porTexto = try repo.listar(busqueda: "reunion planeacion")
        #expect(porTexto.map(\.id) == ["1"])

        let soloEnlaces = try repo.listar(tipo: .enlace)
        #expect(soloEnlaces.map(\.id) == ["2"])

        // Fijar el elemento más viejo lo pone primero.
        #expect(try repo.alternarFijado("1"))
        #expect(try repo.listar().map(\.id) == ["1", "2"])
    }

    @Test func deduplicaPorHuellaConservandoElFijado() throws {
        let repo = RepositorioDePortapapeles(try BaseDeDatos.enMemoria())
        let t0 = Date(timeIntervalSince1970: 1_000)

        try repo.registrar(
            ElementoDePortapapeles(
                id: "1", creado: t0, tipo: .texto, texto: "Hola", huella: "misma", fijado: true, bytes: 4))
        try repo.registrar(
            ElementoDePortapapeles(
                id: "2", creado: t0.addingTimeInterval(30), tipo: .texto, texto: "Hola", huella: "misma",
                fijado: false, bytes: 4))

        let todos = try repo.listar()
        #expect(todos.count == 1)
        #expect(todos.first?.id == "1")
        #expect(todos.first?.fijado == true)
        #expect(todos.first?.creado == t0.addingTimeInterval(30))
    }

    @Test func laRetencionBorraVencidosYSobrantesPeroRespetaFijados() throws {
        let repo = RepositorioDePortapapeles(try BaseDeDatos.enMemoria())
        let ahora = Date(timeIntervalSince1970: 100 * 86_400)
        let hace40Dias = ahora.addingTimeInterval(-40 * 86_400)

        // Vencido pero fijado: sobrevive.
        try repo.registrar(
            ElementoDePortapapeles(
                id: "fijo", creado: hace40Dias, tipo: .texto, texto: "Fijo", huella: "hf", fijado: true, bytes: 4))
        // Vencido no fijado: se borra.
        try repo.registrar(
            ElementoDePortapapeles(
                id: "viejo", creado: hace40Dias, tipo: .imagen, texto: "Vieja", rutaArchivo: "/tmp/vieja.png",
                huella: "hv", bytes: 10))
        // Tres recientes no fijados, con límite de 2: el más antiguo de los tres se borra.
        for indice in 1...3 {
            try repo.registrar(
                ElementoDePortapapeles(
                    id: "r\(indice)",
                    creado: ahora.addingTimeInterval(Double(indice)),
                    tipo: .texto,
                    texto: "Reciente \(indice)",
                    huella: "hr\(indice)",
                    bytes: 10
                ))
        }

        let rutasBorradas = try repo.aplicarRetencion(diasMaximos: 30, elementosMaximos: 2, ahora: ahora)
        #expect(rutasBorradas == ["/tmp/vieja.png"])
        #expect(try repo.listar().map(\.id) == ["fijo", "r3", "r2"])
    }

    @Test func bandejaGuardaQuitaYVacia() throws {
        let repo = RepositorioDeBandeja(try BaseDeDatos.enMemoria())
        let e1 = ElementoDeBandeja(
            id: "b1", creado: Date(timeIntervalSince1970: 10), nombre: "a.pdf",
            rutaOriginal: "/orig/a.pdf", rutaCopia: "/tray/a.pdf", bytes: 100)
        let e2 = ElementoDeBandeja(
            id: "b2", creado: Date(timeIntervalSince1970: 20), nombre: "b.png",
            rutaOriginal: "/orig/b.png", rutaCopia: "/tray/b.png", bytes: 200)

        try repo.agregar(e1)
        try repo.agregar(e2)
        #expect(try repo.listar().map(\.id) == ["b2", "b1"])

        let quitada = try repo.quitar("b1")
        #expect(quitada == "/tray/a.pdf")
        #expect(try repo.listar().map(\.id) == ["b2"])

        let vaciadas = try repo.vaciar()
        #expect(vaciadas == ["/tray/b.png"])
        #expect(try repo.listar().isEmpty)
    }
}
