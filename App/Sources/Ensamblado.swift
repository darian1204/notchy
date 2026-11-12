import AppKit
import NotchyCore
import NotchyFeatures
import NotchyIsland
import NotchyPlatform

/// Crea las piezas y las conecta. Es el único lugar que conoce todas las capas.
final class Ensamblado {
    let ajustes: Ajustes
    let bus = BusDeEventos()
    let registro: RegistroDeModulos
    let coordinador: CoordinadorDeIsla
    let panel: ControladorDePanel

    init() {
        ajustes = Ajustes(almacen: AlmacenUserDefaults())
        registro = RegistroDeModulos(ajustes: ajustes)
        registro.registrar(ModuloDeInicio())
        coordinador = CoordinadorDeIsla(registro: registro, bus: bus)
        coordinador.alSalir = { NSApp.terminate(nil) }
        panel = ControladorDePanel(coordinador: coordinador, ajustes: ajustes)
    }

    func arrancar() {
        panel.mostrar()
    }

    func detener() {
        panel.ocultar()
        registro.detenerTodo()
    }
}
