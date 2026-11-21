import AppKit
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

        modeloDeAgenda = ModeloDeAgenda(
            calendario: adaptadorDeCalendario,
            recordatorios: adaptadorDeRecordatorios,
            bus: bus,
            alAbrirURL: abrirURL
        )
        modeloDeGrabadora = ModeloDeGrabadora(
            captura: adaptadorDeCapturaDeAudio,
            escritor: adaptadorDeEscritorDeAudio,
            transcripcion: adaptadorDeTranscripcion,
            repositorio: baseAbierta.map(RepositorioDeGrabadoraYReuniones.init),
            carpetaAudio: rutasAbiertas?.audio,
            ajustes: ajustes,
            bus: bus,
            alAbrirURL: abrirURL
        )
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
        modeloDeAgente = ModeloDeAgente(
            puerto: adaptadorDeAgente,
            ajustes: ajustes
        )
        modeloDeTraductor = ModeloDeTraductor(agente: adaptadorDeAgente)
        modeloDeWindowSnap = ModeloDeWindowSnap(puerto: adaptadorDeWindowSnap)
        modeloDeMonitorSistema = ModeloDeMonitorSistema(puerto: adaptadorDeMonitor)
        gestorDeInbox = GestorDeInboxObsidian(
            ajustes: ajustes,
            alAbrirURL: abrirURL
        )
        let repositorioDeResumen = baseAbierta.map(RepositorioDeGrabadoraYReuniones.init)
        let inboxParaResumen = gestorDeInbox
        resumidorDeReuniones = ResumidorDeReuniones(
            bus: bus,
            modelo: AdaptadorDeResumenLocal(),
            ajustes: ajustes,
            segmentosDe: { id in (try? repositorioDeResumen?.listarSegmentos(reunionID: id)) ?? [] },
            escribirEnInbox: { nota in inboxParaResumen.agregarLinea(nota) }
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
            bus: bus
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
                        modeloCapturado.refrescar()
                    }
                },
                alSalir: salir
            )
        }
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
