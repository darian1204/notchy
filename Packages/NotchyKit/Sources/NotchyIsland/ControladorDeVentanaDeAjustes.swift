import AppKit
import SwiftUI

/// Abre y trae al frente la ventana de Ajustes y Diagnóstico desde un agente sin Dock (`LSUIElement`).
@MainActor
public final class ControladorDeVentanaDeAjustes {
    private let crearVista: @MainActor () -> AnyView
    private var ventana: NSWindow?

    public init<Contenido: View>(@ViewBuilder _ crearVista: @escaping @MainActor () -> Contenido) {
        self.crearVista = { AnyView(crearVista()) }
    }

    public var estaVisible: Bool { ventana?.isVisible == true }

    public func mostrar() {
        let ventana = obtenerOCrearVentana()
        NSApp.activate()
        ventana.makeKeyAndOrderFront(nil)
        ventana.orderFrontRegardless()
    }

    public func cerrar() {
        ventana?.close()
    }

    private func obtenerOCrearVentana() -> NSWindow {
        if let ventana {
            return ventana
        }
        let controlador = NSHostingController(rootView: crearVista())
        let nueva = NSWindow(contentViewController: controlador)
        nueva.title = "Ajustes de Notchy"
        nueva.styleMask = [.titled, .closable, .miniaturizable]
        nueva.isReleasedWhenClosed = false
        nueva.setContentSize(NSSize(width: 520, height: 420))
        nueva.center()
        ventana = nueva
        return nueva
    }
}
