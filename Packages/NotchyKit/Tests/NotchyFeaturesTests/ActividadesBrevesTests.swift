import Foundation
import NotchyCore
import NotchyFeatures
import NotchyStorage
import NotchyTestSupport
import Testing

@MainActor
struct ActividadesBrevesTests {
    private func archivo(_ nombre: String) -> ArchivoRecibidoAirDrop {
        ArchivoRecibidoAirDrop(
            nombre: nombre, ruta: "/Users/prueba/Downloads/\(nombre)", fechaRecibido: .now, bytes: 10)
    }

    @Test func airDropRecibidoAvisaUnaVezPorTanda() async {
        let puerto = AirDropFalso(archivos: [archivo("viejo.pdf")])
        let bus = BusDeEventos()
        let flujo = await bus.suscribir(a: ActividadBreveSolicitada.self)
        let modelo = ModeloDeAirDrop(puerto: puerto, bus: bus)
        modelo.iniciar()
        puerto.simularLlegada(archivo("uno.heic"))
        puerto.simularLlegada(archivo("dos.jpg"))
        puerto.simularLlegada(archivo("tres.png"))
        var iterador = flujo.makeAsyncIterator()
        let aviso = await iterador.next()
        #expect(aviso?.actividad.tipo == .airdropRecibido)
        #expect(aviso?.actividad.simbolo == ClaseDeArchivo.imagen.simbolo)
        #expect(aviso?.actividad.cantidad == 3)
    }

    @Test func airDropEnviadoAvisaAlTerminar() async {
        let puerto = AirDropFalso(archivos: [])
        let bus = BusDeEventos()
        let flujo = await bus.suscribir(a: ActividadBreveSolicitada.self)
        let modelo = ModeloDeAirDrop(puerto: puerto, bus: bus)
        modelo.enviar(archivos: [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.pdf")])
        var iterador = flujo.makeAsyncIterator()
        let aviso = await iterador.next()
        #expect(aviso?.actividad.tipo == .airdropEnviado)
        #expect(aviso?.actividad.simbolo == ClaseDeArchivo.pdf.simbolo)
        #expect(aviso?.actividad.cantidad == 2)
    }

    @Test func laBandejaAvisaAlGuardarArchivos() async throws {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "notchy-orejas-\(UUID().uuidString)")
        let bandeja = raiz.appending(path: "bandeja")
        try FileManager.default.createDirectory(at: bandeja, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: raiz) }
        let origen = raiz.appending(path: "nota.txt")
        try Data("hola".utf8).write(to: origen)

        let bus = BusDeEventos()
        let flujo = await bus.suscribir(a: ActividadBreveSolicitada.self)
        let modelo = ModeloDeBandeja(
            repositorio: RepositorioDeBandeja(try BaseDeDatos.enMemoria()), carpetaBandeja: bandeja, bus: bus)
        #expect(modelo.agregarArchivos([origen]) == 1)
        var iterador = flujo.makeAsyncIterator()
        let aviso = await iterador.next()
        #expect(aviso?.actividad.tipo == .archivos)
        #expect(aviso?.actividad.simbolo == ClaseDeArchivo.texto.simbolo)
    }

    @Test func cadaArchivoTieneElIconoDeSuClase() {
        #expect(ClaseDeArchivo.de(nombre: "IMG_2041.HEIC") == .imagen)
        #expect(ClaseDeArchivo.de(nombre: "clip.mov") == .video)
        #expect(ClaseDeArchivo.de(nombre: "nota.m4a") == .audio)
        #expect(ClaseDeArchivo.de(nombre: "boleto.pdf") == .pdf)
        #expect(ClaseDeArchivo.de(nombre: "datos.xlsx") == .hojaDeCalculo)
        #expect(ClaseDeArchivo.de(nombre: "fotos.zip") == .comprimido)
        #expect(ClaseDeArchivo.de(nombre: "main.swift") == .codigo)
        #expect(ClaseDeArchivo.de(nombre: "sin-extension") == .otro)
        #expect(ClaseDeArchivo.comun(de: ["a.png", "b.jpg"]) == .imagen)
        #expect(ClaseDeArchivo.comun(de: ["a.png", "b.pdf"]) == .otro)
    }
}
