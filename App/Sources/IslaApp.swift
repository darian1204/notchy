import AppKit
import IslaCore
import OSLog
import SwiftUI

/// Punto de entrada. La app solo ensambla; todo lo demás vive en el paquete IslaKit.
@main
struct IslaApp: App {
    @NSApplicationDelegateAdaptor(Arranque.self) private var arranque

    var body: some Scene {
        // Sin ventana propia: en M1 aquí se monta el panel del notch.
        Settings {
            EmptyView()
        }
    }
}

final class Arranque: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: IslaInfo.identificador, category: "arranque")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let carpeta = IslaInfo.carpetaDeDatos(IslaInfo.compilacionActual)
        log.info("Isla arrancó. Carpeta de datos: \(carpeta, privacy: .public)")
    }
}
