import AppKit
import NotchyCore
import OSLog
import SwiftUI

/// Punto de entrada. La app solo ensambla; todo lo demás vive en el paquete NotchyKit.
@main
struct NotchyApp: App {
    @NSApplicationDelegateAdaptor(Arranque.self) private var arranque

    var body: some Scene {
        // Sin ventana propia: la isla es un panel que crea el ensamblado.
        Settings {
            EmptyView()
        }
    }
}

final class Arranque: NSObject, NSApplicationDelegate {
    private let log = Registro.de(.arranque)
    private var ensamblado: Ensamblado?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let ensamblado = Ensamblado()
        ensamblado.arrancar()
        self.ensamblado = ensamblado
        let carpeta = NotchyInfo.carpetaDeDatos(NotchyInfo.compilacionActual)
        log.info("Notchy arrancó. Carpeta de datos: \(carpeta, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        ensamblado?.detener()
    }
}
