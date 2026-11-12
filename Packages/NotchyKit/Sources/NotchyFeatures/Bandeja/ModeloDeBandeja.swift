import Foundation
import NotchyCore
import NotchyStorage
import Observation

/// Modelo de vista de la Bandeja de archivos (BND-1 a BND-3).
/// Copia los archivos soltados dentro de la carpeta `tray/` de Application Support y nunca borra los originales.
@MainActor
@Observable
public final class ModeloDeBandeja {
    public private(set) var elementos: [ElementoDeBandeja] = []

    @ObservationIgnored private let repositorio: RepositorioDeBandeja?
    @ObservationIgnored private let carpetaBandeja: URL?

    public init(repositorio: RepositorioDeBandeja?, carpetaBandeja: URL?) {
        self.repositorio = repositorio
        self.carpetaBandeja = carpetaBandeja
        recargar()
    }

    public func recargar() {
        guard let repositorio else {
            elementos = []
            return
        }
        elementos = (try? repositorio.listar()) ?? []
    }

    /// Agrega archivos soltados en la isla copiándolos a la carpeta de la bandeja (BND-1).
    @discardableResult
    public func agregarArchivos(_ urls: [URL]) -> Int {
        guard let repositorio, let carpetaBandeja else { return 0 }
        try? FileManager.default.createDirectory(at: carpetaBandeja, withIntermediateDirectories: true)
        var agregados = 0

        for url in urls where url.isFileURL {
            let rutaOriginal = url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: rutaOriginal) else { continue }
            let id = UUID().uuidString
            let nombre = url.lastPathComponent
            let destino = carpetaBandeja.appending(path: "\(id)-\(nombre)")
            do {
                try FileManager.default.copyItem(at: url, to: destino)
            } catch {
                continue
            }
            let bytes =
                (try? destino.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                ?? (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                ?? 0
            let elemento = ElementoDeBandeja(
                id: id,
                nombre: nombre,
                rutaOriginal: rutaOriginal,
                rutaCopia: destino.path,
                bytes: bytes
            )
            if (try? repositorio.agregar(elemento)) != nil {
                agregados += 1
            }
        }
        recargar()
        return agregados
    }

    /// Quita un elemento de la bandeja borrando solo su copia interna, nunca el archivo original (BND-3).
    public func quitar(_ id: String) {
        guard let repositorio else { return }
        if let rutaCopia = try? repositorio.quitar(id) {
            borrarCopiaInterna(rutaCopia)
        }
        recargar()
    }

    /// Vacía toda la bandeja borrando solo las copias internas, nunca los archivos originales (BND-3).
    public func vaciar() {
        guard let repositorio else { return }
        let copias = (try? repositorio.vaciar()) ?? []
        for rutaCopia in copias {
            borrarCopiaInterna(rutaCopia)
        }
        recargar()
    }

    private func borrarCopiaInterna(_ rutaCopia: String) {
        guard let carpetaBandeja else { return }
        let url = URL(fileURLWithPath: rutaCopia)
        guard url.deletingLastPathComponent().standardizedFileURL == carpetaBandeja.standardizedFileURL else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
}
