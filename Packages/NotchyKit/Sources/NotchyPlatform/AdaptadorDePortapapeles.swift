import AppKit
import NotchyCore

/// Adaptador real de `NSPasteboard.general` (CLP-1, CLP-2, CLP-4, CLP-7).
@MainActor
public final class AdaptadorDePortapapeles: PuertoDePortapapeles {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var conteoDeCambios: Int {
        pasteboard.changeCount
    }

    public func leerActual() -> MuestraDePortapapeles {
        let conteo = pasteboard.changeCount
        let tipos = (pasteboard.types ?? []).map(\.rawValue)
        let appActiva = NSWorkspace.shared.frontmostApplication
        let appOrigen = appActiva?.localizedName
        let bundleOrigen = appActiva?.bundleIdentifier

        if tipos.contains(where: { Self.tiposSensibles.contains($0) }) {
            return MuestraDePortapapeles(
                conteo: conteo, tipos: tipos, appOrigen: appOrigen, bundleOrigen: bundleOrigen, carga: .sensible)
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL],
            !urls.isEmpty
        {
            return MuestraDePortapapeles(
                conteo: conteo, tipos: tipos, appOrigen: appOrigen, bundleOrigen: bundleOrigen, carga: .archivos(urls))
        }

        if let texto = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !texto.isEmpty
        {
            return MuestraDePortapapeles(
                conteo: conteo, tipos: tipos, appOrigen: appOrigen, bundleOrigen: bundleOrigen, carga: .texto(texto))
        }

        if let png = pasteboard.data(forType: .png) {
            return MuestraDePortapapeles(
                conteo: conteo, tipos: tipos, appOrigen: appOrigen, bundleOrigen: bundleOrigen, carga: .imagenPNG(png))
        }

        if let tiff = pasteboard.data(forType: .tiff),
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        {
            return MuestraDePortapapeles(
                conteo: conteo, tipos: tipos, appOrigen: appOrigen, bundleOrigen: bundleOrigen, carga: .imagenPNG(png))
        }

        return MuestraDePortapapeles(
            conteo: conteo, tipos: tipos, appOrigen: appOrigen, bundleOrigen: bundleOrigen, carga: .vacia)
    }

    @discardableResult
    public func escribir(_ elemento: ElementoDePortapapeles) -> Int {
        pasteboard.clearContents()
        switch elemento.tipo {
        case .texto, .enlace:
            pasteboard.setString(elemento.texto, forType: .string)
        case .archivo:
            if let ruta = elemento.rutaArchivo {
                let url = URL(fileURLWithPath: ruta)
                pasteboard.writeObjects([url as NSURL])
            } else {
                pasteboard.setString(elemento.texto, forType: .string)
            }
        case .imagen:
            if let ruta = elemento.rutaArchivo,
                let datos = try? Data(contentsOf: URL(fileURLWithPath: ruta))
            {
                pasteboard.setData(datos, forType: .png)
            }
        }
        return pasteboard.changeCount
    }

    public func limpiar() {
        pasteboard.clearContents()
    }
}
