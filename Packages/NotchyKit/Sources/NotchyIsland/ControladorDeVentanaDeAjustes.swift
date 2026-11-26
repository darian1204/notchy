import AppKit
import SwiftUI

/// Abre y trae al frente la ventana de Ajustes y Diagnóstico desde un agente sin Dock (`LSUIElement`).
@MainActor
public final class ControladorDeVentanaDeAjustes {
    private let crearVista: @MainActor () -> AnyView
    private var ventana: NSWindow?
    private var observadorDeCierre: (any NSObjectProtocol)?
    /// Separación entre el borde inferior de la isla abierta y la ventana.
    static let separacionDeLaIsla: CGFloat = 24

    /// Avisa cuando la ventana aparece (`true`) o se cierra (`false`), para fijar la isla.
    public var alCambiarVisibilidad: (@MainActor (Bool) -> Void)?
    /// Marco de la isla abierta en coordenadas de pantalla. Si está, la ventana sale debajo de ella.
    public var marcoDeLaIsla: (@MainActor () -> CGRect?)?

    public init<Contenido: View>(@ViewBuilder _ crearVista: @escaping @MainActor () -> Contenido) {
        self.crearVista = { AnyView(crearVista()) }
    }

    public var estaVisible: Bool { ventana?.isVisible == true }

    public func mostrar() {
        let ventana = obtenerOCrearVentana()
        let yaVisible = ventana.isVisible
        alCambiarVisibilidad?(true)
        // Solo al aparecer: si ya estaba abierta, se respeta donde la dejó.
        if !yaVisible, let isla = marcoDeLaIsla?() {
            ventana.setFrameOrigin(Self.origenDebajo(de: isla, tamano: ventana.frame.size))
        }
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
        observadorDeCierre = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nueva,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.alCambiarVisibilidad?(false) }
        }
        ventana = nueva
        return nueva
    }

    /// Centrada bajo la isla y sin salirse del área visible de esa pantalla.
    static func origenDebajo(de isla: CGRect, tamano: CGSize) -> CGPoint {
        let centro = CGPoint(x: isla.midX, y: isla.minY)
        let pantalla = NSScreen.screens.first { $0.frame.contains(CGPoint(x: centro.x, y: isla.maxY - 1)) }
        var origen = CGPoint(
            x: isla.midX - tamano.width / 2,
            y: isla.minY - separacionDeLaIsla - tamano.height
        )
        if let visible = pantalla?.visibleFrame {
            origen.x = min(max(origen.x, visible.minX), visible.maxX - tamano.width)
            origen.y = min(max(origen.y, visible.minY), visible.maxY - tamano.height)
        }
        return origen
    }
}
