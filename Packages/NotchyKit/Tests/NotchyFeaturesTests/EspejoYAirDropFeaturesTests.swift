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

@MainActor
private final class MuestreadorDeColorFalso: PuertoMuestreadorDeColor {
    var colorSimulado: ColorMuestreado? = ColorMuestreado(rojo: 1.0, verde: 1.0, azul: 1.0)
    var copiados: [String] = []

    func muestrearColorEnPantalla() async -> ColorMuestreado? {
        colorSimulado
    }

    func copiarAlPortapapeles(_ texto: String) {
        copiados.append(texto)
    }
}

extension EspejoYAirDropFeaturesTests {
    @Test func colorPickerCalculaFormatosYContrasteWCAG() async {
        let blanco = ColorMuestreado(rojo: 1.0, verde: 1.0, azul: 1.0)
        let negro = ColorMuestreado(rojo: 0.0, verde: 0.0, azul: 0.0)
        #expect(blanco.hex == "#FFFFFF")
        #expect(blanco.rgbTexto == "rgb(255, 255, 255)")
        #expect(blanco.contrasteWCAG(contra: negro) > 20.9)

        let muestreador = MuestreadorDeColorFalso()
        let suiteName = "notchy.colorpicker.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let modelo = ModeloDeColorPicker(muestreador: muestreador, defaults: defaults)
        await modelo.muestrearColorPrimario()
        #expect(modelo.colorPrimario.hex == "#FFFFFF")
        #expect(modelo.cumpleAA == true)
        #expect(modelo.cumpleAAA == true)
        #expect(modelo.cumpleLarge == true)

        modelo.intercambiarColores()
        #expect(modelo.colorFondo.hex == "#FFFFFF")
    }

    @Test func ahoraSuenaParseaLetrasSincronizadasLRC() {
        let lrc = """
            [00:12.00] Primera línea de la canción
            [00:18.50] Segunda línea cantando
            [00:25.00] Tercera línea del coro
            """
        let lineas = ModeloDeAhoraSuena.parsearLRC(lrc)
        #expect(lineas.count == 3)
        #expect(lineas[0].tiempoSegundos == 12.0)
        #expect(lineas[1].texto == "Segunda línea cantando")

        let letra = LetraDeCancion(titulo: "Canción", artista: "Artista", lineas: lineas)
        #expect(letra.indiceActivo(en: 10.0) == 0)
        #expect(letra.indiceActivo(en: 19.0) == 1)
        #expect(letra.indiceActivo(en: 30.0) == 2)
    }

    @Test func screenTimeCategorizaYOrdenaPorTiempo() {
        let suiteName = "notchy.screentime.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let modelo = ModeloDeScreenTime(defaults: defaults)
        modelo.registrarTiempoManual(
            bundleID: "com.apple.dt.Xcode",
            nombre: "Xcode",
            segundos: 5400,
            cambios: 8
        )
        #expect(ModeloDeScreenTime.categorizar(bundleID: "com.apple.dt.Xcode", nombre: "Xcode") == .desarrollo)
        #expect(ModeloDeScreenTime.categorizar(bundleID: "md.obsidian", nombre: "Obsidian") == .productividad)
        #expect(modelo.appsOrdenadas.first?.bundleId == "com.apple.dt.Xcode")
    }

    @Test func ajustesGuardaSieteTemasDePanelYNueveDeBarra() {
        #expect(TemaDePanel.allCases.count == 7)
        #expect(TemaDeBarra.allCases.count == 9)

        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        #expect(ajustes.temaPanel == .obsidiana)
        #expect(ajustes.temaBarra == .clasico)

        ajustes.temaPanel = .ciruela
        ajustes.temaBarra = .caratula
        #expect(ajustes.temaPanel == .ciruela)
        #expect(ajustes.temaBarra == .caratula)
    }
}

@MainActor
private final class AgenteOpenCodeFalso: PuertoAgenteOpenCode {
    var disponible = true
    var respuestaSimulada = "Respuesta desde OpenCode"

    func estaDisponible() -> Bool { disponible }

    func modelosDisponibles() async -> [String] {
        ["openai/gpt-5.4-fast", "opencode/glm-5.3-flash-free"]
    }

    func enviarMensaje(
        prompt: String,
        modelo: String?,
        sesionID: String?,
        directorio: String?,
        alRecibirFragmento: @escaping @MainActor (String, String?) -> Void
    ) async throws -> (textoFinal: String, sesionID: String?) {
        alRecibirFragmento(respuestaSimulada, "ses_prueba_123")
        return (respuestaSimulada, "ses_prueba_123")
    }
}

@MainActor
private final class WindowSnapFalso: PuertoWindowSnap {
    var nombreAppObjetivo: String = "Safari"
    var bundleIdObjetivo: String? = "com.apple.Safari"
    var tienePermisoAccesibilidad: Bool = true
    var disposicionesAplicadas: [DisposicionDeVentana] = []

    func pedirPermisoAccesibilidad() {}

    func aplicar(_ disposicion: DisposicionDeVentana) -> Bool {
        disposicionesAplicadas.append(disposicion)
        return true
    }
}

@MainActor
private final class MonitorSistemaFalso: PuertoMonitorDelSistema {
    func leerMetricas() -> MetricasDelSistema {
        MetricasDelSistema(
            usoCPUPorcentaje: 12.0,
            memoriaUsadaGB: 14.0,
            memoriaTotalGB: 24.0,
            almacenamientoUsadoPorcentaje: 25.0,
            discoLibreGB: 384.0,
            discoTotalGB: 512.0,
            redBytesPorSegundo: 15_360,
            bateriaPorcentaje: 82,
            bateriaCargando: true
        )
    }
}

extension EspejoYAirDropFeaturesTests {
    @Test func climaFormateaCelsiusYFahrenheit() {
        let suite = "notchy.clima.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let modelo = ModeloDeClima(defaults: defaults)
        #expect(modelo.formatearTemp(20) == "20°C")
        modelo.usarFahrenheit = true
        #expect(modelo.formatearTemp(20) == "68°F")
        #expect(EstadoDelClima.iconoWMO(codigo: 0, esDeDia: false) == "moon.stars.fill")
    }

    @Test func notificacionesFiltraDescartaYMarcaLeidas() {
        let suite = "notchy.notif.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let modelo = ModeloDeNotificaciones(defaults: defaults)
        let nueva = NotificacionReciente(
            id: "n-1",
            bundleId: "com.tinyspeck.slackmacgap",
            nombreApp: "Slack",
            titulo: "#eng-notchy: 12 new messages",
            cuerpo: "Morgan: Quick heads up"
        )
        modelo.registrar(nueva)
        #expect(modelo.notificaciones.first?.id == "n-1")
        modelo.marcarLeida("n-1")
        #expect(modelo.notificaciones.first?.leida == true)
        modelo.descartar("n-1")
        #expect(!modelo.notificaciones.contains(where: { $0.id == "n-1" }))
    }

    @Test func agenteOpenCodeEnviaYRecibeRespuestaConSesion() async throws {
        let puerto = AgenteOpenCodeFalso()
        let modelo = ModeloDeAgente(puerto: puerto)
        modelo.enviarPrompt("Hola OpenCode")
        try await Task.sleep(for: .milliseconds(80))
        #expect(modelo.mensajes.last?.texto == "Respuesta desde OpenCode")
        #expect(modelo.sesionID == "ses_prueba_123")
    }

    @Test func windowSnapYMonitorSistemaAplicanDisposicionYLeenMetricas() {
        let snap = WindowSnapFalso()
        let modeloSnap = ModeloDeWindowSnap(puerto: snap)
        modeloSnap.aplicar(.mitadIzquierda)
        #expect(snap.disposicionesAplicadas == [.mitadIzquierda])
        #expect(modeloSnap.ultimaDisposicion == .mitadIzquierda)

        let monitor = MonitorSistemaFalso()
        let modeloMonitor = ModeloDeMonitorSistema(puerto: monitor)
        #expect(modeloMonitor.metricas.bateriaPorcentaje == 82)
        #expect(MetricasDelSistema.formatearVelocidadRed(15_360) == "15.00 KB/s")
    }
}
