import Foundation
import NotchyCore
import NotchyStorage
import Testing

@testable import NotchyFeatures

@Suite("Grabadora y reuniones (M4)")
@MainActor
struct GrabadoraYReunionesFeaturesTests {
    @Test
    func glosarioYEnsamblador() {
        let corrector = CorrectorDeGlosario()
        #expect(
            corrector.corregir("Vamos a migrar a supavase con open code en notchi")
                == "Vamos a migrar a Supabase con OpenCode en Notchy"
        )

        var ens = EnsambladorDeSegmentos(reunionID: "r1", corrector: corrector)
        _ = ens.recibir(fuente: .sistema, texto: "El servidor va en supavase", esFinal: false, enSegundos: 3)
        #expect(ens.segmentosEnVivo.count == 1)
        #expect(ens.segmentosEnVivo.first?.esFinal == false)
        #expect(ens.segmentosEnVivo.first?.texto == "El servidor va en Supabase")

        let final = ens.recibir(
            fuente: .sistema,
            texto: "El servidor va en supavase desde hoy.",
            esFinal: true,
            enSegundos: 5
        )
        #expect(final?.esFinal == true)
        #expect(final?.inicioSegundos == 3)
        #expect(final?.finSegundos == 5)
        #expect(ens.provisionalSistema == nil)

        let marca = ens.agregarMarca(etiqueta: "Acuerdo clave", enSegundos: 8)
        #expect(marca.fuente == .marca)
        #expect(ens.segmentosFinales.count == 2)
    }

    @Test
    func flujoCompletoDeReunion() async throws {
        let base = try BaseDeDatos.enMemoria()
        let repo = RepositorioDeGrabadoraYReuniones(base)
        let captura = CapturaDeAudioFalsa()
        let escritor = EscritorDeAudioFalso()
        let transcripcion = TranscripcionFalsa()
        let bus = BusDeEventos()
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "notchy-m4-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: carpeta) }

        let modelo = ModeloDeGrabadora(
            captura: captura,
            escritor: escritor,
            transcripcion: transcripcion,
            repositorio: repo,
            carpetaAudio: carpeta,
            bus: bus
        )
        modelo.iniciar()

        await modelo.iniciarReunion(tituloPersonalizado: "Sync de arquitectura")
        #expect(modelo.grabando == true)
        #expect(modelo.modoActivo == .reunion)

        // Llega audio de micrófono ("Tú") y sistema ("Otros")
        captura.emitirBloque(
            BloqueDeAudioPCM(fuente: .microfono, muestras: [0.25, -0.25, 0.3], marcaHostMs: 1000)
        )
        captura.emitirBloque(
            BloqueDeAudioPCM(fuente: .sistema, muestras: [0.15, -0.15, 0.2], marcaHostMs: 1020)
        )
        try await Task.sleep(for: .milliseconds(30))

        transcripcion.emitir(
            ResultadoDeTranscripcion(
                fuente: .sistema,
                texto: "Probamos supavase en la reunión",
                esFinal: true
            )
        )
        transcripcion.emitir(
            ResultadoDeTranscripcion(
                fuente: .microfono,
                texto: "De acuerdo, yo lo configuro",
                esFinal: true
            )
        )
        try await Task.sleep(for: .milliseconds(30))

        #expect(modelo.segmentosEnVivo.count == 2)
        #expect(modelo.segmentosEnVivo.first?.texto == "Probamos Supabase en la reunión")
        #expect(modelo.segmentosEnVivo.first?.fuente.etiqueta == "Otros")
        #expect(modelo.segmentosEnVivo.last?.fuente.etiqueta == "Tú")

        // Agregar marca (GRB-8)
        _ = modelo.agregarMarcaEnReunion(etiqueta: "Revisar desfase")
        #expect(modelo.segmentosEnVivo.count == 3)

        // Simular reposo del Mac y cambio de dispositivo (GRB-7)
        await modelo.manejarEventoDeEntorno(.reposoDelMacIniciado)
        await modelo.manejarEventoDeEntorno(.despertarDelMac)
        await modelo.manejarEventoDeEntorno(.cambioDeDispositivo(nombre: "Sony WH-1000XM5"))
        #expect(escritor.rotaciones >= 2)

        // Cambiar idioma en vivo de es-MX a en-US (GRB-3 / S4)
        await modelo.cambiarIdioma(.inglesEstadosUnidos)
        #expect(modelo.idiomaSeleccionado == .inglesEstadosUnidos)
        #expect(transcripcion.idiomaActivo == .inglesEstadosUnidos)

        await modelo.detenerGrabacion()
        #expect(modelo.grabando == false)
        #expect(modelo.reunionesGuardadas.count == 1)
        #expect(modelo.reunionesGuardadas.first?.estado == .finalizada)
        #expect(modelo.segmentosDeReunionSeleccionada.count == 3)

        // Retranscribir (GRB-4)
        if let guardada = modelo.reunionesGuardadas.first {
            transcripcion.resultadosRetranscripcion = [
                ResultadoDeTranscripcion(
                    fuente: .microfono,
                    texto: "Texto retranscrito con supavase",
                    esFinal: true
                )
            ]
            await modelo.retranscribirReunion(guardada)
            #expect(
                modelo.segmentosDeReunionSeleccionada.contains {
                    $0.texto == "Texto retranscrito con Supabase"
                }
            )
        }
    }

    @Test
    func notaDeVozYSinArchivoVacio() async throws {
        let base = try BaseDeDatos.enMemoria()
        let repo = RepositorioDeGrabadoraYReuniones(base)
        let captura = CapturaDeAudioFalsa()
        let escritor = EscritorDeAudioFalso()
        let transcripcion = TranscripcionFalsa()

        let modelo = ModeloDeGrabadora(
            captura: captura,
            escritor: escritor,
            transcripcion: transcripcion,
            repositorio: repo
        )
        modelo.iniciar()

        // Si se inicia y se detiene sin recibir bloques, escritor no devuelve rutas y no se crea fila vacía.
        escritor.devolverRutasVaciasSiNoHayBloques = true
        await modelo.iniciarNotaDeVoz()
        await modelo.detenerGrabacion()
        #expect(modelo.notasDeVoz.isEmpty)
        #expect(modelo.mensajeDeError?.contains("archivo vacío") == true)

        // Ahora con bloques reales y transcripción:
        await modelo.iniciarNotaDeVoz()
        captura.emitirBloque(BloqueDeAudioPCM(fuente: .microfono, muestras: [0.4, -0.4]))
        transcripcion.emitir(
            ResultadoDeTranscripcion(
                fuente: .microfono,
                texto: "Recordar prueba con supavase",
                esFinal: true
            )
        )
        try await Task.sleep(for: .milliseconds(30))
        await modelo.detenerGrabacion()

        #expect(modelo.notasDeVoz.count == 1)
        #expect(modelo.notasDeVoz.first?.transcripcion == "Recordar prueba con Supabase")
    }

    @Test
    func resumenAPedidoEdicionYExportacionDeNotaEnHistorial() async throws {
        let base = try BaseDeDatos.enMemoria()
        let repo = RepositorioDeGrabadoraYReuniones(base)
        let captura = CapturaDeAudioFalsa()
        let escritor = EscritorDeAudioFalso()
        let transcripcion = TranscripcionFalsa()
        let resumenFalso = ResumenDeTextoFalso()

        let inicio = Date(timeIntervalSince1970: 1_763_683_200)
        let reunion = ReunionGrabada(
            id: "reu-m5",
            titulo: "Diseño de Notas: M5",
            inicio: inicio,
            fin: inicio.addingTimeInterval(20 * 60),
            estado: .finalizada
        )
        try repo.guardarReunion(reunion)
        try repo.guardarSegmento(
            SegmentoDeTranscripcion(
                id: "seg-m5-1",
                reunionID: "reu-m5",
                fuente: .microfono,
                inicioSegundos: 12,
                finSegundos: 18,
                texto: "Vamos a guardar las notas de reunión en SQLite."
            )
        )

        let modelo = ModeloDeGrabadora(
            captura: captura,
            escritor: escritor,
            transcripcion: transcripcion,
            resumenDeTexto: resumenFalso,
            repositorio: repo
        )
        modelo.iniciar()
        #expect(modelo.reunionSeleccionadaID == "reu-m5")
        #expect(modelo.notaDeReunionSeleccionada == nil)
        #expect(modelo.seccionDetalleHistorial == .transcripcion)
        #expect(modelo.idsDeReunionesConNota.isEmpty)

        // Si Apple Intelligence no está disponible, muestra error
        resumenFalso.listo = false
        let fallida = await modelo.resumirReunion(reunion)
        #expect(fallida == nil)
        #expect(modelo.errorDeResumen?.contains("Apple Intelligence") == true)

        // Cuando está disponible, resume, guarda en la base y abre la pestaña Notas
        resumenFalso.listo = true
        let generada = try #require(await modelo.resumirReunion(reunion))
        #expect(modelo.errorDeResumen == nil)
        #expect(generada.markdown.contains("## Resumen"))
        #expect(generada.markdown.contains("## Decisiones"))
        #expect(generada.markdown.contains("## Tareas"))
        #expect(modelo.notaDeReunionSeleccionada?.editadaEn == nil)
        #expect(modelo.seccionDetalleHistorial == .notas)
        #expect(modelo.tieneNotaGuardada("reu-m5"))

        // Al cambiar a una reunión sin nota abre en Transcripción; al volver a una con nota abre en Notas
        let reunionSinNota = ReunionGrabada(
            id: "reu-sin-nota",
            titulo: "Sin nota",
            inicio: inicio.addingTimeInterval(3600),
            estado: .finalizada
        )
        try repo.guardarReunion(reunionSinNota)
        modelo.recargarDatos()
        modelo.reunionSeleccionadaID = "reu-sin-nota"
        #expect(modelo.seccionDetalleHistorial == .transcripcion)
        modelo.reunionSeleccionadaID = "reu-m5"
        #expect(modelo.seccionDetalleHistorial == .notas)

        // Editar nota actualiza editada_en
        let fechaEdicion = Date(timeIntervalSince1970: 1_763_690_000)
        let editada = try #require(
            modelo.guardarEdicionNota(
                reunionID: "reu-m5",
                markdown:
                    "## Resumen\n- Nota editada a mano\n\n## Decisiones\n- Ninguna\n\n## Tareas\n- [ ] Exportar — Darian",
                ahora: fechaEdicion
            )
        )
        #expect(editada.editadaEn == fechaEdicion)
        #expect(modelo.notaDeReunionSeleccionada?.editadaEn == fechaEdicion)

        // Exportación a Markdown
        let exportacion = modelo.construirExportacionMarkdown(para: reunion)
        #expect(exportacion.nombreArchivo.hasSuffix("-diseno-de-notas-m5.md"))
        #expect(exportacion.contenido.contains("tipo: reunion"))
        #expect(exportacion.contenido.contains("# Diseño de Notas: M5"))
        #expect(exportacion.contenido.contains("- Nota editada a mano"))
        #expect(
            exportacion.contenido.contains(
                "## Transcripción\n**[00:12] Tú:** Vamos a guardar las notas de reunión en SQLite."))
    }

    @Test
    func diarizaPrimeroYResumeDespuesConNombresDeHablante() async throws {
        let base = try BaseDeDatos.enMemoria()
        let repo = RepositorioDeGrabadoraYReuniones(base)
        let captura = CapturaDeAudioFalsa()
        let escritor = EscritorDeAudioFalso()
        let transcripcion = TranscripcionFalsa()
        let diarizacion = DiarizacionFalsa()
        let resumenFalso = ResumenDeTextoFalso()
        let bus = BusDeEventos()
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "notchy-diar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: carpeta) }

        let modelo = ModeloDeGrabadora(
            captura: captura,
            escritor: escritor,
            transcripcion: transcripcion,
            diarizacion: diarizacion,
            resumenDeTexto: resumenFalso,
            repositorio: repo,
            carpetaAudio: carpeta,
            bus: bus
        )
        let resumidor = ResumidorDeReuniones(
            bus: bus,
            modelo: resumenFalso,
            ajustes: Ajustes(almacen: AlmacenEnMemoriaGrabadoraTests()),
            repositorio: repo,
            segmentosDe: { id in (try? repo.listarSegmentos(reunionID: id)) ?? [] },
            escribirEnInbox: { _ in true },
            alGuardarNota: { _ in modelo.recargarNotaDeReunionSeleccionada() }
        )
        resumidor.arrancar()
        defer { resumidor.detener() }

        modelo.iniciar()
        await modelo.iniciarReunion(tituloPersonalizado: "Reunión en persona")

        // Crear el archivo ficticio en la ruta del escritor para que la diarización lo encuentre
        if let rutaMic = escritor.rutasMicrofono.first {
            FileManager.default.createFile(atPath: rutaMic, contents: Data([0, 1, 2]))
        }

        diarizacion.tramos = [
            TramoDeHablante(hablanteID: "spk-a", inicio: 0, fin: 6),
            TramoDeHablante(hablanteID: "spk-b", inicio: 6, fin: 15),
        ]

        transcripcion.emitir(
            ResultadoDeTranscripcion(
                fuente: .microfono,
                texto: String(
                    repeating: "Revisamos la arquitectura completa de la aplicación y los módulos. ", count: 3),
                esFinal: true
            )
        )
        try await Task.sleep(for: .milliseconds(20))

        await modelo.detenerGrabacion()
        try await Task.sleep(for: .milliseconds(80))

        #expect(diarizacion.llamadas == 1)
        #expect(modelo.segmentosDeReunionSeleccionada.first?.hablante == "Persona 1")
        #expect(resumenFalso.ultimoTextoRecibido?.contains("Persona 1:") == true)
        #expect(modelo.notaDeReunionSeleccionada != nil)
        #expect(modelo.seccionDetalleHistorial == .notas)

        if let reunionGuardada = modelo.reunionesGuardadas.first {
            modelo.renombrarHablante(reunionID: reunionGuardada.id, hablanteID: "Persona 1", nuevoNombre: "Darian")
            #expect(modelo.nombresHablantesDeReunionSeleccionada["Persona 1"] == "Darian")
            if let seg = modelo.segmentosDeReunionSeleccionada.first {
                #expect(modelo.nombreVisibleDeHablante(para: seg) == "Darian")
            }
        }
    }
}

private final class AlmacenEnMemoriaGrabadoraTests: AlmacenDeAjustes, @unchecked Sendable {
    private var datos: [String: Data] = [:]
    func leer(_ clave: String) -> Data? { datos[clave] }
    func guardar(_ dato: Data?, en clave: String) { datos[clave] = dato }
}

private final class DiarizacionFalsa: PuertoDeDiarizacion, @unchecked Sendable {
    var listo = true
    var tramos: [TramoDeHablante] = []
    var llamadas = 0

    func disponible() async -> Bool { listo }
    func diarizar(archivos: [URL]) async throws -> [TramoDeHablante] {
        llamadas += 1
        return tramos
    }
}

private final class ResumenDeTextoFalso: PuertoDeResumenDeTexto, @unchecked Sendable {
    var listo = true
    var ultimoTextoRecibido: String?
    func disponible() async -> Bool { listo }
    func resumir(_ texto: String, instrucciones: String) async throws -> String {
        ultimoTextoRecibido = texto
        return """
            ## Resumen
            - Se acordó guardar en SQLite.

            ## Decisiones
            - Tabla meeting_note con cascada.

            ## Tareas
            - [ ] Escribir pruebas — Darian
            """
    }
}

@MainActor
private final class CapturaDeAudioFalsa: PuertoDeCapturaDeAudio {
    var capturando = false
    var permiso: EstadoDePermiso = .concedido
    var estadisticas = EstadisticasDeCapturaDeAudio(
        nombreMicrofono: "MacBook Air Microphone",
        usaMicrofonoInterno: true,
        formatoMicrofono: "48000 Hz, 1 ch",
        formatoSistema: "48000 Hz, 2 ch",
        bloquesMicrofono: 10,
        cortesMicrofono: 0,
        bloquesSistema: 10,
        cortesSistema: 0,
        desfaseInicialMs: 18.5
    )
    private var alBloque: (@Sendable (BloqueDeAudioPCM) -> Void)?
    private var alEntorno: (@Sendable (EventoDeEntornoDeAudio) -> Void)?

    func estadoDePermisoMicrofono() -> EstadoDePermiso { permiso }
    func pedirPermisoMicrofono() async -> EstadoDePermiso { permiso }

    func iniciarCaptura(
        incluirSistema: Bool,
        preferirMicrofonoInterno: Bool,
        alRecibirBloque: @escaping @Sendable (BloqueDeAudioPCM) -> Void,
        alCambiarEntorno: @escaping @Sendable (EventoDeEntornoDeAudio) -> Void
    ) async throws {
        capturando = true
        alBloque = alRecibirBloque
        alEntorno = alCambiarEntorno
    }

    func detenerCaptura() async {
        capturando = false
    }

    func emitirBloque(_ bloque: BloqueDeAudioPCM) {
        alBloque?(bloque)
    }
}

@MainActor
private final class EscritorDeAudioFalso: PuertoDeEscritorDeAudio {
    var rutasMicrofono: [String] = []
    var rutasSistema: [String] = []
    var rotaciones = 0
    var bloquesEscritos = 0
    var devolverRutasVaciasSiNoHayBloques = false
    private var carpeta: URL?
    private var prefijo = ""

    func iniciarSesion(
        carpetaBase: URL,
        prefijo: String,
        incluirSistema: Bool,
        duracionTrozoSegundos: Double
    ) throws {
        self.carpeta = carpetaBase
        self.prefijo = prefijo
        self.bloquesEscritos = 0
        if !devolverRutasVaciasSiNoHayBloques {
            rutasMicrofono = [carpetaBase.appending(path: "\(prefijo)-mic-001.m4a").path]
            rutasSistema =
                incluirSistema ? [carpetaBase.appending(path: "\(prefijo)-sistema-001.m4a").path] : []
        } else {
            rutasMicrofono = []
            rutasSistema = []
        }
    }

    func escribir(_ bloque: BloqueDeAudioPCM) throws {
        bloquesEscritos += 1
        if let carpeta {
            let ruta = carpeta.appending(path: "\(prefijo)-mic-001.m4a").path
            if !rutasMicrofono.contains(ruta) {
                rutasMicrofono.append(ruta)
            }
        }
    }

    func rotarTrozo() throws {
        rotaciones += 1
        if let carpeta {
            rutasMicrofono.append(
                carpeta.appending(path: "\(prefijo)-mic-00\(rotaciones + 1).m4a").path
            )
        }
    }

    func finalizarSesion() -> (rutasMicrofono: [String], rutasSistema: [String]) {
        (rutasMicrofono, rutasSistema)
    }
}

@MainActor
private final class TranscripcionFalsa: PuertoDeTranscripcion {
    var idiomaActivo: IdiomaDeTranscripcion = .espanolMexico
    var resultadosRetranscripcion: [ResultadoDeTranscripcion] = []
    private var callback: (@Sendable (ResultadoDeTranscripcion) -> Void)?

    func iniciar(
        idioma: IdiomaDeTranscripcion,
        incluirSistema: Bool,
        alRecibirResultado: @escaping @Sendable (ResultadoDeTranscripcion) -> Void
    ) async throws {
        idiomaActivo = idioma
        callback = alRecibirResultado
    }

    func alimentar(_ bloque: BloqueDeAudioPCM) {}

    func cambiarIdioma(_ nuevo: IdiomaDeTranscripcion) async throws {
        idiomaActivo = nuevo
    }

    func detener() async {}

    func retranscribir(
        archivos: [(fuente: FuenteDeAudio, url: URL)],
        idioma: IdiomaDeTranscripcion
    ) async throws -> [ResultadoDeTranscripcion] {
        resultadosRetranscripcion
    }

    func emitir(_ resultado: ResultadoDeTranscripcion) {
        callback?(resultado)
    }
}
