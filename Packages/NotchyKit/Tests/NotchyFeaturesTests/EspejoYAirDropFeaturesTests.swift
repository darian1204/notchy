import Foundation
import NotchyCore
import NotchyFeatures
import NotchyTestSupport
import Testing

@MainActor
struct EspejoYAirDropFeaturesTests {
    @Test func espejoSeEnciendeAlAbrirYSeApagaAlCerrar() async {
        let camara = CamaraFalsa(permiso: .sinPedir)
        let bus = BusDeEventos()
        let modelo = ModeloDeEspejo(puerto: camara, bus: bus)
        modelo.iniciar()

        #expect(camara.encendida == false)
        #expect(camara.peticionesDePermiso == 0)

        camara.permiso = .concedido
        await modelo.abrirEspejo()
        #expect(camara.encendida == true)
        #expect(camara.encendidos == 1)

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

    @Test func airDropDetectaRecibidosMandaArchivosYReportaCarpetaFaltante() async {
        let inicial = ArchivoRecibidoAirDrop(
            nombre: "boleto.pdf",
            ruta: "/Users/prueba/Downloads/boleto.pdf",
            fechaRecibido: Date(timeIntervalSince1970: 1_000),
            bytes: 2048
        )
        let puerto = AirDropFalso(archivos: [inicial])
        let bus = BusDeEventos()
        let flujo = await bus.suscribir(a: ArchivoAirDropDetectado.self)

        let modelo = ModeloDeAirDrop(puerto: puerto, bus: bus)
        modelo.iniciar()
        #expect(modelo.recibidos.map(\.nombre) == ["boleto.pdf"])

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
}
