// Herramienta de los scripts: renderiza un HTML a PNG (con transparencia) o a PDF con WebKit.
// renderizar png <html> <salida.png> <lado>   |   renderizar pdf <html> <salida.pdf>
import AppKit
import WebKit

let args = CommandLine.arguments
let modo = args[1], entrada = URL(fileURLWithPath: args[2]), salida = URL(fileURLWithPath: args[3])
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

final class Cargador: NSObject, WKNavigationDelegate {
    var listo: () -> Void = {}
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.listo() }
    }
}

let lado = args.count > 4 ? CGFloat(Double(args[4])!) : 1024
let tamano = modo == "png" ? NSSize(width: lado, height: lado) : NSSize(width: 595, height: 842)
let ventana = NSWindow(contentRect: NSRect(origin: .zero, size: tamano), styleMask: [.borderless], backing: .buffered, defer: false)
let web = WKWebView(frame: NSRect(origin: .zero, size: tamano))
web.setValue(false, forKey: "drawsBackground")
ventana.contentView = web
let cargador = Cargador()
web.navigationDelegate = cargador
cargador.listo = {
    if modo == "png" {
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: tamano)
        config.snapshotWidth = NSNumber(value: Double(lado))
        web.takeSnapshot(with: config) { imagen, error in
            guard let imagen, let tiff = imagen.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { print("error", error as Any); exit(1) }
            try! png.write(to: salida); exit(0)
        }
    } else {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595.28, height: 841.89)
        info.topMargin = 40; info.bottomMargin = 40; info.leftMargin = 0; info.rightMargin = 0
        info.horizontalPagination = .fit; info.verticalPagination = .automatic
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = salida
        let op = web.printOperation(with: info)
        op.showsPrintPanel = false; op.showsProgressPanel = false
        op.view?.frame = web.bounds
        op.runModal(for: ventana, delegate: nil, didRun: nil, contextInfo: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
    }
}
web.loadFileURL(entrada, allowingReadAccessTo: entrada.deletingLastPathComponent())
app.run()
