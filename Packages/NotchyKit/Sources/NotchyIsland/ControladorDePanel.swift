import AppKit
import NotchyCore
import NotchyDesign
import OSLog
import SwiftUI

/// Panel que permite editar campos de texto dentro de la isla sin activar la app ni quitar el foco global (ISL-4).
final class PanelDeIsla: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Deja que el primer clic llegue a los botones y campos de texto aunque la app no esté activa.
final class AnfitrionDeIsla<Contenido: View>: NSHostingView<Contenido> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// La ventana de la isla: un panel fijo del tamaño mayor (D-04), pegado arriba al centro, sobre
/// pantalla completa y en todos los Spaces. Sigue al cursor para avisarle al coordinador cuándo
/// entra y sale, y solo recibe clics cuando el cursor está sobre la isla visible: fuera de ella
/// los clics pasan a lo que haya debajo, incluida la barra de menús.
@MainActor
public final class ControladorDePanel {
    private let coordinador: CoordinadorDeIsla
    private let ajustes: Ajustes
    private let log = Registro.de(.isla)
    private var panel: PanelDeIsla?
    private var monitores: [Any] = []
    private var observadores: [(NotificationCenter, any NSObjectProtocol)] = []
    private var cursorDentro = false

    public init(coordinador: CoordinadorDeIsla, ajustes: Ajustes) {
        self.coordinador = coordinador
        self.ajustes = ajustes
        coordinador.observar { [weak self] in self?.revisarCursor() }
        ajustes.observar { [weak self] in self?.reubicar() }
    }

    public var estaVisible: Bool { panel != nil }

    public func mostrar() {
        guard panel == nil else { return }
        let panel = PanelDeIsla(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.setAccessibilityLabel("Notchy")

        // El NSHostingView va dentro de un contenedor normal: si fuera el contentView directo,
        // controlaría el tamaño de la ventana y AppKit entra en un ciclo de restricciones (S2).
        let anfitrion = AnfitrionDeIsla(rootView: VistaDeIsla(coordinador: coordinador))
        anfitrion.sizingOptions = []
        anfitrion.translatesAutoresizingMaskIntoConstraints = true
        anfitrion.autoresizingMask = [.width, .height]
        let contenedor = NSView()
        anfitrion.frame = contenedor.bounds
        contenedor.addSubview(anfitrion)
        panel.contentView = contenedor
        self.panel = panel

        vigilarCursor()
        vigilarPantallas()
        reubicar()
        panel.orderFrontRegardless()
    }

    public func ocultar() {
        monitores.forEach(NSEvent.removeMonitor)
        monitores.removeAll()
        for (centro, observador) in observadores {
            centro.removeObserver(observador)
        }
        observadores.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: Pantalla

    /// Lee la pantalla elegida en los ajustes y coloca el panel. Se repite al conectar o quitar
    /// un monitor, al cambiar la resolución y al despertar (ISL-1).
    private func reubicar() {
        guard let panel, let pantalla = Self.pantalla(ajustes.pantalla) else { return }
        let geometria = GeometriaDeIsla(pantalla: Self.describir(pantalla))
        if geometria != coordinador.geometria {
            coordinador.geometria = geometria
            let notch = geometria.pantalla.notch.map { "\(Int($0.width))x\(Int($0.height))" } ?? "sin notch"
            log.info("Pantalla \(Int(pantalla.frame.width))x\(Int(pantalla.frame.height)), \(notch, privacy: .public)")
        }
        panel.setFrame(geometria.marcoDelPanel, display: true)
        panel.orderFrontRegardless()
        revisarCursor()
    }

    static func pantalla(_ preferida: PantallaPreferida) -> NSScreen? {
        // La primera pantalla de la lista es la principal: la que tiene la barra de menús.
        let principal = NSScreen.screens.first
        switch preferida {
        case .principal: return principal
        case .conNotch: return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? principal
        }
    }

    static func describir(_ pantalla: NSScreen) -> PantallaDeIsla {
        let marco = pantalla.frame
        var notch: CGSize?
        if pantalla.safeAreaInsets.top > 0,
            let izquierda = pantalla.auxiliaryTopLeftArea,
            let derecha = pantalla.auxiliaryTopRightArea
        {
            notch = CGSize(width: marco.width - izquierda.width - derecha.width, height: pantalla.safeAreaInsets.top)
        }
        let barra = marco.maxY - pantalla.visibleFrame.maxY
        return PantallaDeIsla(marco: marco, notch: notch, altoDeBarraDeMenus: barra > 0 ? barra : 24)
    }

    private func vigilarPantallas() {
        let avisos: [(NotificationCenter, Notification.Name)] = [
            (.default, NSApplication.didChangeScreenParametersNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
        ]
        for (centro, nombre) in avisos {
            let observador = centro.addObserver(forName: nombre, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reubicar() }
            }
            observadores.append((centro, observador))
        }
    }

    // MARK: Cursor

    private func vigilarCursor() {
        let movimiento: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let clics: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        let globales = [
            NSEvent.addGlobalMonitorForEvents(matching: movimiento) { [weak self] _ in
                MainActor.assumeIsolated { self?.revisarCursor() }
            },
            NSEvent.addGlobalMonitorForEvents(matching: clics) { [weak self] _ in
                MainActor.assumeIsolated { self?.clicFuera() }
            },
        ]
        let local = NSEvent.addLocalMonitorForEvents(matching: movimiento) { [weak self] evento in
            MainActor.assumeIsolated { self?.revisarCursor() }
            return evento
        }
        monitores = (globales + [local]).compactMap { $0 }
    }

    private func revisarCursor() {
        guard let panel else { return }
        let geometria = coordinador.geometria
        let zona = geometria.zonaDeCursor(estado: coordinador.estado, tamano: coordinador.tamano)
        let dentro = GeometriaDeIsla.contiene(zona, NSEvent.mouseLocation)
        // En reposo no hay nada que pulsar: los clics sobre el notch pasan a la barra de menús.
        let interactivo = dentro && coordinador.estado != .reposo
        panel.ignoresMouseEvents = !interactivo
        if case .expandido = coordinador.estado, dentro, !panel.isKeyWindow {
            panel.makeKey()
        } else if (!dentro || coordinador.estado == .reposo) && panel.isKeyWindow {
            panel.resignKey()
        }
        guard dentro != cursorDentro else { return }
        cursorDentro = dentro
        coordinador.recibir(dentro ? .cursorEntro : .cursorSalio)
    }

    private func clicFuera() {
        guard case .expandido = coordinador.estado, !cursorDentro else { return }
        panel?.resignKey()
        coordinador.recibir(.clicFuera)
    }
}
