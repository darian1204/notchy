import Foundation
import NotchyCore
import NotchyFeatures
import NotchyTestSupport
import Testing

@MainActor
struct EspejoYAirDropFeaturesTests {
    @Test func espejoSeEnciendeAlAbrirTomaFotoYSeApagaAlCerrar() async throws {
        let camara = CamaraFalsa(permiso: .sinPedir)
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        let carpetaTemp = FileManager.default.temporaryDirectory
            .appending(path: "NotchyEspejoTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: carpetaTemp) }
        ajustes.carpetaFotosEspejo = carpetaTemp.path

        let bus = BusDeEventos()
        let modelo = ModeloDeEspejo(puerto: camara, ajustes: ajustes, bus: bus)
        modelo.iniciar()

        #expect(camara.encendida == false)
        #expect(camara.peticionesDePermiso == 0)

        camara.permiso = .concedido
        await modelo.abrirEspejo()
        #expect(camara.encendida == true)
        #expect(camara.encendidos == 1)

        let fotoURL = await modelo.tomarFoto(ahora: Date(timeIntervalSince1970: 1_700_000_000))
        let urlGuardada = try #require(fotoURL)
        #expect(FileManager.default.fileExists(atPath: urlGuardada.path))
        #expect(modelo.ultimaFotoGuardada == urlGuardada)

        await modelo.cerrarEspejo()
        #expect(camara.encendida == false)
        #expect(camara.apagados == 1)
    }

    @Test func espejoReportaErrorSiLaCamaraEstaOcupadaSinReintentar() async {
        let camara = CamaraFalsa(permiso: .concedido, fallaAlEncender: "La cámara está ocupada por otra app")
        let modelo = ModeloDeEspejo(puerto: camara)
        await modelo.abrirEspejo()

        #expect(modelo.encendida == false)
        #expect(modelo.mensajeDeError?.contains("ocupada") == true)
    }

    @Test func airDropDetectaRecibidosAbreEnAppPredeterminadaYMandaArchivos() async {
        let inicial = ArchivoRecibidoAirDrop(
            nombre: "boleto.pdf",
            ruta: "/Users/prueba/Downloads/boleto.pdf",
            fechaRecibido: Date(timeIntervalSince1970: 1_000),
            bytes: 2048
        )
        let puerto = AirDropFalso(archivos: [inicial])
        let bus = BusDeEventos()
        let flujo = await bus.suscribir(a: ArchivoAirDropDetectado.self)
        var abiertos: [URL] = []
        var revelados: [URL] = []

        let modelo = ModeloDeAirDrop(
            puerto: puerto,
            bus: bus,
            alAbrirArchivo: { abiertos.append($0) },
            alRevelarArchivo: { revelados.append($0) }
        )
        modelo.iniciar()
        #expect(modelo.recibidos.map(\.nombre) == ["boleto.pdf"])

        modelo.abrirRecibido(inicial)
        #expect(abiertos == [inicial.url])
        modelo.revelarRecibido(inicial)
        #expect(revelados == [inicial.url])

        let nuevo = ArchivoRecibidoAirDrop(
            nombre: "IMG_2041.heic",
            ruta: "/Users/prueba/Downloads/IMG_2041.heic",
            fechaRecibido: Date(timeIntervalSince1970: 2_000),
            bytes: 4096
        )
        puerto.simularLlegada(nuevo)
        #expect(modelo.recibidos.map(\.nombre) == ["IMG_2041.heic", "boleto.pdf"])

        var iterador = flujo.makeAsyncIterator()
        let evento = await iterador.next()
        #expect(evento?.archivo == nuevo)

        let archivoAEnviar = URL(fileURLWithPath: "/tmp/informe.pdf")
        modelo.enviar(archivos: [archivoAEnviar])
        #expect(puerto.lotesEnviados == [[archivoAEnviar]])

        puerto.errorAlListar = "Carpeta no existe"
        modelo.recargar()
        #expect(modelo.mensajeDeError?.contains("/Users/prueba/Downloads") == true)
    }

    @Test func gestorDeInboxEscribeYExtraeLineasEnVaultDeObsidian() throws {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        let vaultTemp = FileManager.default.temporaryDirectory
            .appending(path: "NotchyVaultTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vaultTemp) }
        ajustes.rutaVaultObsidian = vaultTemp.path

        var urlsAbiertas: [URL] = []
        let gestor = GestorDeInboxObsidian(ajustes: ajustes, alAbrirURL: { urlsAbiertas.append($0) })
        #expect(gestor.lineasRecientes.isEmpty)

        gestor.borrador = "Comprar pilas recargables"
        #expect(gestor.guardarBorrador() == true)
        #expect(gestor.borrador.isEmpty)
        #expect(gestor.lineasRecientes == ["Comprar pilas recargables"])

        let contenido = try String(contentsOf: gestor.urlNotaInbox, encoding: .utf8)
        #expect(contenido.contains("Comprar pilas recargables"))

        gestor.abrirEnObsidian()
        #expect(urlsAbiertas.first?.scheme == "obsidian")
    }
}
