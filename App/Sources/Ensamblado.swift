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
    let modeloDePortapapeles: ModeloDePortapapeles
    let modeloDeBandeja: ModeloDeBandeja
    let modeloDeAjustes: ModeloDeAjustesYDiagnostico
    private var ventanaDeAjustes: ControladorDeVentanaDeAjustes?
    private var barraDeMenus: ControladorDeBarraDeMenus?
    private let registradorCarbon = RegistradorDeAtajosCarbon()
    private let adaptadorDePortapapeles = AdaptadorDePortapapeles()
    private let log = Registro.de(.arranque)

    init() {
        ajustes = Ajustes(almacen: AlmacenUserDefaults())
        let (rutasAbiertas, baseAbierta) = Self.abrirRutasYBase(log: log)
        rutas = rutasAbiertas
        base = baseAbierta

        modeloDePortapapeles = ModeloDePortapapeles(
            puerto: adaptadorDePortapapeles,
            repositorio: baseAbierta.map(RepositorioDePortapapeles.init),
            carpetaImagenes: rutasAbiertas?.portapapeles,
            ajustes: ajustes,
            bus: bus
        )
        modeloDeBandeja = ModeloDeBandeja(
            repositorio: baseAbierta.map(RepositorioDeBandeja.init),
            carpetaBandeja: rutasAbiertas?.bandeja
        )

        registro = RegistroDeModulos(ajustes: ajustes)
        coordinador = CoordinadorDeIsla(registro: registro, bus: bus)

        let coordinadorCapturado = coordinador
        registro.registrar(
            ModuloDeInicio(
                portapapeles: modeloDePortapapeles,
                alAbrirModulo: { id in coordinadorCapturado.recibir(.elegirModulo(id)) }
            ))
        registro.registrar(ModuloDeBandeja(modelo: modeloDeBandeja))
        registro.registrar(ModuloDePortapapeles(modelo: modeloDePortapapeles))

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
        let portapapelesCapturado = modeloDePortapapeles
        let salir: @MainActor () -> Void = { NSApp.terminate(nil) }
        let ventana = ControladorDeVentanaDeAjustes {
            VistaDeAjustesYDiagnostico(
                modelo: modeloCapturado,
                alAbrirEnlace: { NSWorkspace.shared.open($0) },
                alBorrarHistorialPortapapeles: { portapapelesCapturado.borrarTodo() },
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
