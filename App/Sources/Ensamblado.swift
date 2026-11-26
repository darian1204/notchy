import AppKit
import NotchyAgent
import NotchyCore
import NotchyFeatures
import NotchyIsland
import NotchyPlatform
import NotchyStorage
import OSLog
import SwiftUI

/// Crea las piezas y las conecta. Es el único lugar que conoce todas las capas.
@MainActor
final class Ensamblado {
    let ajustes: Ajustes
    let bus = BusDeEventos()
    let rutas: RutasDeDatos?
    let base: BaseDeDatos?
    let registro: RegistroDeModulos
    let coordinador: CoordinadorDeIsla
    let panel: ControladorDePanel
    let atajo: ControladorDeAtajo
    let modeloDeAgenda: ModeloDeAgenda
    let modeloDeGrabadora: ModeloDeGrabadora
    let modeloDeAhoraSuena: ModeloDeAhoraSuena
    let modeloDeEspejo: ModeloDeEspejo
    let modeloDePortapapeles: ModeloDePortapapeles
    let modeloDeBandeja: ModeloDeBandeja
    let modeloDeAirDrop: ModeloDeAirDrop
    let modeloDeColorPicker: ModeloDeColorPicker
    let modeloDeScreenTime: ModeloDeScreenTime
    let modeloDeClima: ModeloDeClima
    let modeloDeNotificaciones: ModeloDeNotificaciones
    let modeloDeAgente: ModeloDeAgente
    let modeloDeTraductor: ModeloDeTraductor
    let modeloDeWindowSnap: ModeloDeWindowSnap
    let modeloDeMonitorSistema: ModeloDeMonitorSistema
    let vigilanteDeHUD: VigilanteDeHUDSistema
    let gestorDeInbox: GestorDeInboxObsidian
    let resumidorDeReuniones: ResumidorDeReuniones
    let modeloDeAjustes: ModeloDeAjustesYDiagnostico
    private var ventanaDeAjustes: ControladorDeVentanaDeAjustes?
    private var barraDeMenus: ControladorDeBarraDeMenus?
    private let registradorCarbon = RegistradorDeAtajosCarbon()
    private let adaptadorDeCalendario = AdaptadorDeCalendarioEventKit()
    private let adaptadorDeCapturaDeAudio = AdaptadorDeCapturaDeAudio()
    private let adaptadorDeEscritorDeAudio = AdaptadorDeEscritorDeAudio()
    private let adaptadorDeTranscripcion = AdaptadorDeTranscripcion()
    private let adaptadorDeRecordatorios = AdaptadorDeRecordatoriosEventKit()
    private let adaptadorDeAhoraSuena = AdaptadorDeAhoraSuena()
    private let adaptadorDeCamara = AdaptadorDeCamara()
    private let adaptadorDePortapapeles = AdaptadorDePortapapeles()
    private let adaptadorDeAirDrop = AdaptadorDeAirDrop()
    private let adaptadorDeColor = AdaptadorMuestreadorDeColor()
    private let adaptadorDeAgente = AdaptadorAgenteOpenCode()
    private let adaptadorDeWindowSnap = AdaptadorWindowSnap()
    private let adaptadorDeMonitor = AdaptadorMonitorDelSistema()
    private let log = Registro.de(.arranque)

    init() {
        ajustes = Ajustes(almacen: AlmacenUserDefaults())
        let (rutasAbiertas, baseAbierta) = Self.abrirRutasYBase(log: log)
        rutas = rutasAbiertas
        base = baseAbierta

        let abrirURL: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
        let adaptadorDeResumen = AdaptadorDeResumenLocal()
        let adaptadorDeDiarizacion = AdaptadorDeDiarizacion(carpetaModelos: rutasAbiertas?.modelos)
        let repositorioDeGrabadora = baseAbierta.map(RepositorioDeGrabadoraYReuniones.init)
        let llavero = AdaptadorDeLlavero()
        gestorDeInbox = GestorDeInboxObsidian(
            ajustes: ajustes,
            alAbrirURL: abrirURL,
            secretos: llavero
        )
        let inboxParaResumen = gestorDeInbox

        modeloDeAgenda = ModeloDeAgenda(
            calendario: adaptadorDeCalendario,
            recordatorios: adaptadorDeRecordatorios,
            bus: bus,
            alAbrirURL: abrirURL
        )
        let grabadora = ModeloDeGrabadora(
            captura: adaptadorDeCapturaDeAudio,
            escritor: adaptadorDeEscritorDeAudio,
            transcripcion: adaptadorDeTranscripcion,
            diarizacion: adaptadorDeDiarizacion,
            resumenDeTexto: adaptadorDeResumen,
            escribirEnInbox: { nota in (try? await inboxParaResumen.agregar(nota)) != nil },
            repositorio: repositorioDeGrabadora,
            carpetaAudio: rutasAbiertas?.audio,
            ajustes: ajustes,
            bus: bus,
            alAbrirURL: abrirURL
        )
        modeloDeGrabadora = grabadora
        modeloDeAhoraSuena = ModeloDeAhoraSuena(
            puerto: adaptadorDeAhoraSuena,
            bus: bus
        )
        modeloDeEspejo = ModeloDeEspejo(
            puerto: adaptadorDeCamara,
            ajustes: ajustes,
            bus: bus,
            alAbrirURL: abrirURL
        )
        modeloDePortapapeles = ModeloDePortapapeles(
            puerto: adaptadorDePortapapeles,
            repositorio: baseAbierta.map(RepositorioDePortapapeles.init),
            carpetaImagenes: rutasAbiertas?.portapapeles,
            ajustes: ajustes,
            bus: bus,
            alAbrirURL: abrirURL
        )
        modeloDeBandeja = ModeloDeBandeja(
            repositorio: baseAbierta.map(RepositorioDeBandeja.init),
            carpetaBandeja: rutasAbiertas?.bandeja
        )
        modeloDeAirDrop = ModeloDeAirDrop(
            puerto: adaptadorDeAirDrop,
            bus: bus,
            alAbrirArchivo: abrirURL,
            alRevelarArchivo: { url in
                var esCarpeta: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &esCarpeta),
                    esCarpeta.boolValue
                {
                    NSWorkspace.shared.open(url)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        )
        modeloDeColorPicker = ModeloDeColorPicker(
            muestreador: adaptadorDeColor
        )
        modeloDeScreenTime = ModeloDeScreenTime()
        modeloDeClima = ModeloDeClima()
        modeloDeNotificaciones = ModeloDeNotificaciones(
            bus: bus, sistema: AdaptadorDeNotificacionesDelSistema())
        let corredorPermisosAgente = CorredorDePermisos(ajustes: ajustes)
        let herramientasDelAgente = AdaptadorHerramientasDelAgente(
            agenda: modeloDeAgenda,
            portapapeles: modeloDePortapapeles,
            puertoPortapapeles: adaptadorDePortapapeles,
            bandeja: modeloDeBandeja,
            grabadora: grabadora,
            repositorioGrabadora: repositorioDeGrabadora,
            ahoraSuena: modeloDeAhoraSuena,
            inbox: gestorDeInbox
        )
        let servidorMCP = ServidorMCPDeNotchy(
            herramientas: herramientasDelAgente,
            corredorDePermisos: corredorPermisosAgente
        )
        let adaptadorAgenteCapturado = adaptadorDeAgente
        let coordinadorMCP = CoordinadorServidorMCPAgente(
            servidor: servidorMCP,
            rutas: rutasAbiertas,
            alConfigurarOpenCode: { urlConfig in
                adaptadorAgenteCapturado.rutaConfigOpenCode = urlConfig.path
            }
        )
        let herramientasParaContextoLocal = herramientasDelAgente
        modeloDeAgente = ModeloDeAgente(
            puerto: adaptadorDeAgente,
            chatLocal: AdaptadorDeChatLocal(),
            repositorio: baseAbierta.map(RepositorioDeAgente.init),
            contextoLocal: {
                let items = await herramientasParaContextoLocal.agendaHoy()
                guard !items.isEmpty else { return "Sin eventos ni recordatorios para hoy." }
                return
                    items
                    .map { item in
                        let ubicacion = item.ubicacion.map { " (\($0))" } ?? ""
                        return "- [\(item.tipo)] \(item.hora): \(item.titulo)\(ubicacion)"
                    }
                    .joined(separator: "\n")
            },
            ajustes: ajustes,
            corredorDePermisos: corredorPermisosAgente,
            servidorMCP: coordinadorMCP
        )
        modeloDeTraductor = ModeloDeTraductor(agente: adaptadorDeAgente)
        modeloDeWindowSnap = ModeloDeWindowSnap(puerto: adaptadorDeWindowSnap)
        modeloDeMonitorSistema = ModeloDeMonitorSistema(puerto: adaptadorDeMonitor)
        resumidorDeReuniones = ResumidorDeReuniones(
            bus: bus,
            modelo: adaptadorDeResumen,
            ajustes: ajustes,
            repositorio: repositorioDeGrabadora,
            segmentosDe: { id in (try? repositorioDeGrabadora?.listarSegmentos(reunionID: id)) ?? [] },
            escribirEnInbox: { nota in (try? await inboxParaResumen.agregar(nota)) != nil },
            alGuardarNota: { _ in grabadora.recargarNotaDeReunionSeleccionada() }
        )

        registro = RegistroDeModulos(ajustes: ajustes)
        coordinador = CoordinadorDeIsla(registro: registro, bus: bus)
        let ajustesParaHUD = ajustes
        let coordinadorParaHUD = coordinador
        vigilanteDeHUD = VigilanteDeHUDSistema { estado in
            guard ajustesParaHUD.hudSistemaActivo else { return }
            coordinadorParaHUD.mostrarHUD(estado)
        }

        let coordinadorCapturado = coordinador
        registro.registrar(
            ModuloDeInicio(
                agenda: modeloDeAgenda,
                ahoraSuena: modeloDeAhoraSuena,
                portapapeles: modeloDePortapapeles,
                bandeja: modeloDeBandeja,
                airdrop: modeloDeAirDrop,
                inbox: gestorDeInbox,
                alAbrirModulo: { id in coordinadorCapturado.recibir(.elegirModulo(id)) },
                ajustes: ajustes,
                clima: modeloDeClima,
                screenTime: modeloDeScreenTime,
                monitor: modeloDeMonitorSistema,
                grabadora: modeloDeGrabadora,
                modulosDisponibles: { [registro] in registro.activos.map(\.identidad) }
            ))
        registro.registrar(
            ModuloDeFlujo(
                agenda: modeloDeAgenda,
                grabadora: modeloDeGrabadora,
                bandeja: modeloDeBandeja,
                portapapeles: modeloDePortapapeles,
                ahoraSuena: modeloDeAhoraSuena,
                alAbrirModulo: { id in coordinadorCapturado.recibir(.elegirModulo(id)) }
            ))
        registro.registrar(ModuloDeAgenda(modelo: modeloDeAgenda))
        registro.registrar(ModuloDeGrabadora(modelo: modeloDeGrabadora))
        registro.registrar(ModuloDeAhoraSuena(modelo: modeloDeAhoraSuena))
        registro.registrar(ModuloDeClima(modelo: modeloDeClima))
        registro.registrar(ModuloDeNotificaciones(modelo: modeloDeNotificaciones))
        registro.registrar(ModuloDeAgente(modelo: modeloDeAgente))
        registro.registrar(ModuloDeEspejo(modelo: modeloDeEspejo))
        registro.registrar(ModuloDeBandeja(modelo: modeloDeBandeja))
        registro.registrar(ModuloDePortapapeles(modelo: modeloDePortapapeles))
        registro.registrar(ModuloDeAirDrop(modelo: modeloDeAirDrop))
        registro.registrar(ModuloDeTraductor(modelo: modeloDeTraductor))
        registro.registrar(ModuloDeWindowSnap(modelo: modeloDeWindowSnap))
        registro.registrar(ModuloDeColorPicker(modelo: modeloDeColorPicker))
        registro.registrar(ModuloDeScreenTime(modelo: modeloDeScreenTime))
        registro.registrar(ModuloDeMonitorSistema(modelo: modeloDeMonitorSistema))

        panel = ControladorDePanel(coordinador: coordinador, ajustes: ajustes)
        atajo = ControladorDeAtajo(coordinador: coordinador, ajustes: ajustes, registrador: registradorCarbon)

        let baseCapturada = base
        let registroCapturado = registro
        let ajustesCapturados = ajustes
        let portapapelesCapturado = modeloDePortapapeles
        let bandejaCapturada = modeloDeBandeja
        let grabadoraCapturada = modeloDeGrabadora
        let agenteCapturado = modeloDeAgente
        let colorPickerCapturado = modeloDeColorPicker
        let notificacionesCapturadas = modeloDeNotificaciones
        let traductorCapturado = modeloDeTraductor
        modeloDeAjustes = ModeloDeAjustesYDiagnostico(
            ajustes: ajustes,
            modulosDisponibles: registro.todos.map(\.identidad),
            proveedorDePermisos: ProveedorDePermisosReal(),
            servicioDeInicio: AdaptadorDeInicioAlAbrirSesion(),
            consultarBase: { ModeloDeAjustesYDiagnostico.diagnosticarBase(baseCapturada) },
            consultarOpenCode: { DetectorDeOpenCode.detectar() },
            consultarModulos: {
                registroCapturado.todos.map { modulo in
                    DiagnosticoDeModulo(
                        id: modulo.identidad.id,
                        nombre: modulo.identidad.nombre,
                        activo: ajustesCapturados.estaActivo(modulo.identidad.id),
                        salud: modulo.salud
                    )
                }
            },
            consultarConteos: {
                ConteosDeDiagnostico(
                    portapapeles: portapapelesCapturado.totalGuardados,
                    bandeja: bandejaCapturada.elementos.count,
                    reuniones: grabadoraCapturada.reunionesGuardadas.count,
                    notasDeVoz: grabadoraCapturada.notasDeVoz.count
                )
            },
            bus: bus,
            secretos: llavero
        )

        let modeloCapturado = modeloDeAjustes
        let salir: @MainActor () -> Void = { NSApp.terminate(nil) }
        let ventana = ControladorDeVentanaDeAjustes {
            VistaDeAjustesYDiagnostico(
                modelo: modeloCapturado,
                alAbrirEnlace: abrirURL,
                alBorrarHistorialPortapapeles: { portapapelesCapturado.borrarTodo() },
                alBorrarTodosLosDatos: {
                    Task { @MainActor in
                        // Una grabación en curso escribe en la carpeta de audio: se cierra antes de vaciarla.
                        if grabadoraCapturada.grabando { await grabadoraCapturada.detenerGrabacion() }
                        portapapelesCapturado.borrarTodo()
                        bandejaCapturada.vaciar()
                        grabadoraCapturada.borrarTodo()
                        agenteCapturado.borrarHistorial()
                        colorPickerCapturado.limpiarHistorial()
                        notificacionesCapturadas.limpiarTodas()
                        traductorCapturado.limpiar()
                        ajustesCapturados.restablecerValoresPorDefecto()
                        modeloCapturado.borrarTokenNotion()
                        modeloCapturado.refrescar()
                    }
                },
                alSalir: salir
            )
        }
        // Con Ajustes abiertos la isla se queda abierta para ver los cambios al momento, y la ventana
        // sale debajo de ella para no taparla.
        let coordinadorDeAjustes = coordinador
        ventana.alCambiarVisibilidad = { visible in coordinadorDeAjustes.recibir(.fijar(visible)) }
        ventana.marcoDeLaIsla = { coordinadorDeAjustes.geometria.zona(coordinadorDeAjustes.tamano) }
        ventanaDeAjustes = ventana

        let abrirAjustes: @MainActor () -> Void = { [weak self] in
            self?.modeloDeAjustes.refrescar()
            self?.ventanaDeAjustes?.mostrar()
        }
        coordinador.alAbrirAjustes = abrirAjustes
        resumidorDeReuniones.arrancar()
        modeloDeBandeja.iniciarLimpiezaAutomatica()
        coordinador.alSalir = salir

        barraDeMenus = ControladorDeBarraDeMenus(
            coordinador: coordinador,
            ajustes: ajustes,
            alAbrirAjustes: abrirAjustes,
            alSalir: salir
        )
    }

    func arrancar() {
        vigilanteDeHUD.iniciar()
        panel.mostrar()
    }

    func detener() {
        vigilanteDeHUD.detener()
        ventanaDeAjustes?.cerrar()
        barraDeMenus?.ocultar()
        atajo.detener()
        registradorCarbon.detener()
        panel.ocultar()
        registro.detenerTodo()
    }

    private static func abrirRutasYBase(log: Logger) -> (RutasDeDatos?, BaseDeDatos?) {
        do {
            let rutas = try RutasDeDatos.porDefecto()
            try rutas.crearCarpetas()
            let base = try BaseDeDatos.abrir(en: rutas.baseDeDatos)
            return (rutas, base)
        } catch {
            log.error("No se pudo abrir la base de datos: \(error.localizedDescription, privacy: .public)")
            return (nil, nil)
        }
    }
}

/// Implementación en la capa de ensamblado de las herramientas de lectura y escritura del agente MCP (AGT-3, AGT-4).
@MainActor
final class AdaptadorHerramientasDelAgente: PuertoDeHerramientasDelAgente {
    private let agenda: ModeloDeAgenda
    private let portapapeles: ModeloDePortapapeles
    private let puertoPortapapeles: AdaptadorDePortapapeles
    private let bandeja: ModeloDeBandeja
    private let grabadora: ModeloDeGrabadora
    private let repositorioGrabadora: RepositorioDeGrabadoraYReuniones?
    private let ahoraSuenaModelo: ModeloDeAhoraSuena
    private let inbox: GestorDeInboxObsidian

    init(
        agenda: ModeloDeAgenda,
        portapapeles: ModeloDePortapapeles,
        puertoPortapapeles: AdaptadorDePortapapeles,
        bandeja: ModeloDeBandeja,
        grabadora: ModeloDeGrabadora,
        repositorioGrabadora: RepositorioDeGrabadoraYReuniones?,
        ahoraSuena: ModeloDeAhoraSuena,
        inbox: GestorDeInboxObsidian
    ) {
        self.agenda = agenda
        self.portapapeles = portapapeles
        self.puertoPortapapeles = puertoPortapapeles
        self.bandeja = bandeja
        self.grabadora = grabadora
        self.repositorioGrabadora = repositorioGrabadora
        self.ahoraSuenaModelo = ahoraSuena
        self.inbox = inbox
    }

    func agendaHoy() async -> [ItemAgendaHoyAgente] {
        if agenda.eventosDelMes.isEmpty && agenda.pendientes.isEmpty {
            await agenda.recargar()
        }
        let formateadorHora = DateFormatter()
        formateadorHora.locale = Locale(identifier: "es_MX")
        formateadorHora.dateFormat = "HH:mm"

        var items: [ItemAgendaHoyAgente] = agenda.eventosDeHoy.map { evento in
            let hora = evento.todoElDia ? "Todo el día" : formateadorHora.string(from: evento.inicio)
            return ItemAgendaHoyAgente(
                tipo: "evento",
                hora: hora,
                titulo: evento.titulo,
                ubicacion: evento.ubicacion
            )
        }

        for pendiente in agenda.pendientes where !pendiente.completado {
            let hora = pendiente.vencimiento.map { formateadorHora.string(from: $0) } ?? "Pendiente"
            items.append(
                ItemAgendaHoyAgente(
                    tipo: "recordatorio",
                    hora: hora,
                    titulo: pendiente.titulo,
                    ubicacion: pendiente.lista
                )
            )
        }
        return items
    }

    func portapapelesRecientes(limite: Int) -> [String] {
        let tope = min(max(limite, 1), 20)
        return
            portapapeles.elementos
            .filter { $0.tipo == .texto || $0.tipo == .enlace }
            .prefix(tope)
            .map(\.texto)
    }

    func bandejaArchivos() -> [String] {
        bandeja.elementos.map { URL(fileURLWithPath: $0.nombre).lastPathComponent }
    }

    func reunionesRecientes(limite: Int) -> [ReunionRecienteAgente] {
        let tope = min(max(limite, 1), 20)
        let formateador = ISO8601DateFormatter()
        let lista = Array(grabadora.reunionesGuardadas.prefix(tope))
        return lista.map { reunion in
            let nota = (try? repositorioGrabadora?.obtenerNotaDeReunion(reunionID: reunion.id))?.markdown
            return ReunionRecienteAgente(
                titulo: reunion.titulo,
                fecha: formateador.string(from: reunion.inicio),
                duracionSegundos: Int(reunion.duracionSegundos.rounded()),
                notaMarkdown: nota
            )
        }
    }

    func ahoraSuena() -> AhoraSuenaAgente? {
        guard let estado = ahoraSuenaModelo.estadoActual else { return nil }
        return AhoraSuenaAgente(
            titulo: estado.titulo,
            artista: estado.artista,
            album: estado.album,
            appOrigen: estado.appOrigen,
            reproduciendo: estado.reproduciendo
        )
    }

    func inboxAgregar(texto: String) async throws -> String {
        try await inbox.agregar(texto)
    }

    func portapapelesCopiar(texto: String) throws -> String {
        let elemento = ElementoDePortapapeles(
            tipo: .texto,
            texto: texto,
            huella: "agente:\(texto.hashValue)",
            bytes: texto.utf8.count
        )
        puertoPortapapeles.escribir(elemento)
        portapapeles.revisarSiCambio()
        return "Copiado al portapapeles"
    }

    func recordatorioCrear(titulo: String, fechaISO8601: String?) async throws -> String {
        var fechaVencimiento: Date?
        if let fechaISO8601, !fechaISO8601.isEmpty {
            if let f = try? Date(fechaISO8601, strategy: .iso8601) {
                fechaVencimiento = f
            } else {
                let iso = ISO8601DateFormatter()
                fechaVencimiento = iso.date(from: fechaISO8601)
            }
        }
        let creado = try await agenda.crearRecordatorio(titulo: titulo, fecha: fechaVencimiento)
        return "Recordatorio creado en \(creado.lista): \(creado.titulo)"
    }
}
