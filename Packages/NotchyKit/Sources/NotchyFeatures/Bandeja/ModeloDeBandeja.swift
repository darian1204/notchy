import AppKit
import Foundation
import NotchyCore
import NotchyStorage
import Observation

@MainActor
@Observable
public final class ModeloDeBandeja {
    public private(set) var elementos: [ElementoDeBandeja] = []
    public var formatoConversion: String = "PNG"
    public var mostrarSegundaFila = false
    public private(set) var mensajeEstado: String?

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
        if agregados > 0 {
            mostrarAvisoTemporal("Guardado en Shelf (\(agregados))")
        }
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

    // MARK: - Acciones de Drop Actions sobre archivos soltados o en la bandeja

    public var urlsEnBandeja: [URL] {
        elementos.map(\.urlParaArrastrar).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func guardarEnICloud(_ urls: [URL]) {
        let archivos = urls.isEmpty ? urlsEnBandeja : urls
        guard !archivos.isEmpty else {
            elegirArchivosYEjecutar { self.guardarEnICloud($0) }
            return
        }
        let carpetaICloud = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs")
        let destinoBase =
            FileManager.default.fileExists(atPath: carpetaICloud.path)
            ? carpetaICloud
            : FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")

        var copiados = 0
        for url in archivos {
            let destino = destinoBase.appending(path: url.lastPathComponent)
            try? FileManager.default.removeItem(at: destino)
            if (try? FileManager.default.copyItem(at: url, to: destino)) != nil {
                copiados += 1
            }
        }
        mostrarAvisoTemporal(copiados > 0 ? "Guardado en iCloud Drive (\(copiados))" : "No se pudo copiar a iCloud")
    }

    public func enviarPorAirDrop(_ urls: [URL]) {
        let archivos = urls.isEmpty ? urlsEnBandeja : urls
        guard !archivos.isEmpty else {
            elegirArchivosYEjecutar { self.enviarPorAirDrop($0) }
            return
        }
        if let servicio = NSSharingService(named: .sendViaAirDrop) {
            servicio.perform(withItems: archivos)
            mostrarAvisoTemporal("Enviando por AirDrop…")
        }
    }

    public func abrirConAppPredeterminada(_ urls: [URL]) {
        let archivos = urls.isEmpty ? urlsEnBandeja : urls
        guard !archivos.isEmpty else {
            elegirArchivosYEjecutar { self.abrirConAppPredeterminada($0) }
            return
        }
        for url in archivos {
            NSWorkspace.shared.open(url)
        }
        mostrarAvisoTemporal("Abierto (\(archivos.count))")
    }

    public func convertirImagenes(_ urls: [URL]) {
        let archivos = urls.isEmpty ? urlsEnBandeja : urls
        guard !archivos.isEmpty else {
            elegirArchivosYEjecutar { self.convertirImagenes($0) }
            return
        }
        let descargas = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
        var convertidas = 0
        for url in archivos {
            guard let img = NSImage(contentsOf: url),
                let tiff = img.tiffRepresentation,
                let rep = NSBitmapImageRep(data: tiff)
            else { continue }

            let ext = formatoConversion.lowercased()
            let tipo: NSBitmapImageRep.FileType = (ext == "jpg" || ext == "jpeg") ? .jpeg : .png
            guard let datos = rep.representation(using: tipo, properties: [:]) else { continue }
            let base = url.deletingPathExtension().lastPathComponent
            let salida = descargas.appending(path: "\(base)-converted.\(ext)")
            if (try? datos.write(to: salida, options: .atomic)) != nil {
                convertidas += 1
                _ = agregarArchivos([salida])
            }
        }
        mostrarAvisoTemporal(
            convertidas > 0 ? "Convertidas a \(formatoConversion) (\(convertidas))" : "Suelta una imagen para convertir"
        )
    }

    public func comprimirEnZip(_ urls: [URL]) {
        let archivos = urls.isEmpty ? urlsEnBandeja : urls
        guard let primero = archivos.first else {
            elegirArchivosYEjecutar { self.comprimirEnZip($0) }
            return
        }
        let descargas = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
        let nombreZip = "\(primero.deletingPathExtension().lastPathComponent).zip"
        let salidaZip = descargas.appending(path: nombreZip)
        try? FileManager.default.removeItem(at: salidaZip)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.arguments = ["-j", salidaZip.path] + archivos.map(\.path)
        try? proc.run()
        proc.waitUntilExit()
        if FileManager.default.fileExists(atPath: salidaZip.path) {
            _ = agregarArchivos([salidaZip])
            mostrarAvisoTemporal("Creado \(nombreZip)")
        }
    }

    public func moverAPapelera(_ urls: [URL]) {
        if urls.isEmpty {
            vaciar()
            mostrarAvisoTemporal("Shelf vaciado")
            return
        }
        for url in urls {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        mostrarAvisoTemporal("Movido a la Papelera")
    }

    private func elegirArchivosYEjecutar(_ accion: @escaping @MainActor ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            accion(panel.urls)
        }
    }

    private func mostrarAvisoTemporal(_ texto: String) {
        mensajeEstado = texto
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            if self?.mensajeEstado == texto {
                self?.mensajeEstado = nil
            }
        }
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
