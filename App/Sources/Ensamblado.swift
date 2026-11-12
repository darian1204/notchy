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
    let base: BaseDeDatos?
    let registro: RegistroDeModulos
    let coordinador: CoordinadorDeIsla
    let panel: ControladorDePanel
    let atajo: ControladorDeAtajo
    let modeloDeAjustes: ModeloDeAjustesYDiagnostico
    private var ventanaDeAjustes: ControladorDeVentanaDeAjustes?
    private var barraDeMenus: ControladorDeBarraDeMenus?
    private let registradorCarbon = RegistradorDeAtajosCarbon()
    private let log = Registro.de(.arranque)

    init() {
        ajustes = Ajustes(almacen: AlmacenUserDefaults())
        base = Self.abrirBase(log: log)
        registro = RegistroDeModulos(ajustes: ajustes)
        registro.registrar(ModuloDeInicio())
        coordinador = CoordinadorDeIsla(registro: registro, bus: bus)
        panel = ControladorDePanel(coordinador: coordinador, ajustes: ajustes)
        atajo = ControladorDeAtajo(coordinador: coordinador, ajustes: ajustes, registrador: registradorCarbon)

        let baseCapturada = base
        let registroCapturado = registro
        let ajustesCapturados = ajustes
        modeloDeAjustes = ModeloDeAjustesYDiagnostico(
            ajustes: ajustes,
            modulosDisponibles: registro.todos.map(\.identidad),
            proveedorDePermisos: ProveedorDePermisosReal(),
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
            bus: bus
        )

        let modeloCapturado = modeloDeAjustes
        let salir: @MainActor () -> Void = { NSApp.terminate(nil) }
        let ventana = ControladorDeVentanaDeAjustes {
            VistaDeAjustesYDiagnostico(
                modelo: modeloCapturado,
                alAbrirEnlace: { NSWorkspace.shared.open($0) },
                alSalir: salir
            )
        }
        ventanaDeAjustes = ventana

        let abrirAjustes: @MainActor () -> Void = { [weak self] in
            self?.modeloDeAjustes.refrescar()
            self?.ventanaDeAjustes?.mostrar()
        }
        coordinador.alAbrirAjustes = abrirAjustes
        coordinador.alSalir = salir

        barraDeMenus = ControladorDeBarraDeMenus(
            coordinador: coordinador,
            ajustes: ajustes,
            alAbrirAjustes: abrirAjustes,
            alSalir: salir
        )
    }

    func arrancar() {
        panel.mostrar()
    }

    func detener() {
        ventanaDeAjustes?.cerrar()
        barraDeMenus?.ocultar()
        atajo.detener()
        registradorCarbon.detener()
        panel.ocultar()
        registro.detenerTodo()
    }

    private static func abrirBase(log: Logger) -> BaseDeDatos? {
        do {
            let rutas = try RutasDeDatos.porDefecto()
            try rutas.crearCarpetas()
            return try BaseDeDatos.abrir(en: rutas.baseDeDatos)
        } catch {
            log.error("No se pudo abrir la base de datos: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
