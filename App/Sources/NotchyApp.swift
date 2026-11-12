import AppKit
import NotchyCore
import OSLog
import SwiftUI

/// Punto de entrada. La app solo ensambla; todo lo demás vive en el paquete NotchyKit.
@main
struct NotchyApp: App {
    @NSApplicationDelegateAdaptor(Arranque.self) private var arranque

    var body: some Scene {
        // Sin ventana propia: en M1 aquí se monta el panel del notch.
        Settings {
            EmptyView()
        }
    }
}

final class Arranque: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: NotchyInfo.identificador, category: "arranque")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let carpeta = NotchyInfo.carpetaDeDatos(NotchyInfo.compilacionActual)
        log.info("Notchy arrancó. Carpeta de datos: \(carpeta, privacy: .public)")
    }
}
