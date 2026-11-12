import AppKit
import NotchyCore

/// Ícono opcional en la barra de menús (SIS-1). Apagado por defecto; se enciende o apaga al instante desde Ajustes.
/// Siempre ofrece mostrar u ocultar la isla, abrir Ajustes y Salir de Notchy.
@MainActor
public final class ControladorDeBarraDeMenus: NSObject {
    private let coordinador: CoordinadorDeIsla
    private let ajustes: Ajustes
    private let alAbrirAjustes: @MainActor () -> Void
    private let alSalir: @MainActor () -> Void
    private var item: NSStatusItem?

    public init(
        coordinador: CoordinadorDeIsla,
        ajustes: Ajustes,
        alAbrirAjustes: @escaping @MainActor () -> Void,
        alSalir: @escaping @MainActor () -> Void
    ) {
        self.coordinador = coordinador
        self.ajustes = ajustes
        self.alAbrirAjustes = alAbrirAjustes
        self.alSalir = alSalir
        super.init()

        ajustes.observar { [weak self] in self?.sincronizar() }
        coordinador.observar { [weak self] in self?.actualizarMenu() }
        sincronizar()
    }

    public var estaVisible: Bool { item != nil }

    public func ocultar() {
        if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func sincronizar() {
        if ajustes.iconoEnBarraDeMenus {
            mostrarSiHaceFalta()
        } else {
            ocultar()
        }
    }

    private func mostrarSiHaceFalta() {
        guard item == nil else { return }
        let nuevo = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let boton = nuevo.button {
            boton.image = NSImage(
                systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notchy")
            boton.setAccessibilityLabel("Notchy")
        }
        item = nuevo
        actualizarMenu()
    }

    private func actualizarMenu() {
        guard let item else { return }
        let menu = NSMenu()

        let estadoTexto =
            switch coordinador.estado {
            case .reposo: "Estado: en reposo"
            case .compacto: "Estado: compacto"
            case .aviso: "Estado: aviso"
            case .expandido: "Estado: abierta"
            }
        let filaEstado = NSMenuItem(title: estadoTexto, action: nil, keyEquivalent: "")
        filaEstado.isEnabled = false
        menu.addItem(filaEstado)
        menu.addItem(.separator())

        let tituloAlternar: String =
            if case .expandido = coordinador.estado {
                "Cerrar la isla"
            } else {
                "Abrir la isla"
            }
        let itemAlternar = NSMenuItem(title: tituloAlternar, action: #selector(alternarIsla), keyEquivalent: "")
        itemAlternar.target = self
        menu.addItem(itemAlternar)

        let itemAjustes = NSMenuItem(title: "Ajustes…", action: #selector(abrirAjustes), keyEquivalent: ",")
        itemAjustes.target = self
        menu.addItem(itemAjustes)

        menu.addItem(.separator())

        let itemSalir = NSMenuItem(title: "Salir de Notchy", action: #selector(salir), keyEquivalent: "q")
        itemSalir.target = self
        menu.addItem(itemSalir)

        item.menu = menu
    }

    @objc private func alternarIsla() {
        coordinador.recibir(.atajo)
    }

    @objc private func abrirAjustes() {
        alAbrirAjustes()
    }

    @objc private func salir() {
        alSalir()
    }
}
