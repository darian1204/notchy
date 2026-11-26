import AppKit
import Foundation
import ImageIO
import NotchyCore
import NotchyStorage
import Observation

@MainActor
@Observable
public final class ModeloDeBandeja {
    /// Lo que se deja en el Shelf se borra solo después de este tiempo.
    public static let vidaEnShelf: TimeInterval = 10 * 60

    public private(set) var elementos: [ElementoDeBandeja] = []
    public var formatoConversion: String = "PNG"
    public var mostrarSegundaFila = false
    public private(set) var mensajeEstado: String?
    /// Miniaturas de 64 px ya decodificadas; la vista nunca abre el archivo completo.
    public private(set) var miniaturas: [String: NSImage] = [:]
    public private(set) var trabajando = false

    @ObservationIgnored private let repositorio: RepositorioDeBandeja?
    @ObservationIgnored private let carpetaBandeja: URL?
    @ObservationIgnored private var tareaLimpieza: Task<Void, Never>?
    @ObservationIgnored private var miniaturasPedidas: Set<String> = []

    @ObservationIgnored private let bus: BusDeEventos?

    public init(repositorio: RepositorioDeBandeja?, carpetaBandeja: URL?, bus: BusDeEventos? = nil) {
        self.repositorio = repositorio
        self.carpetaBandeja = carpetaBandeja
        self.bus = bus
        recargar()
    }

    public func recargar() {
        guard let repositorio else {
            elementos = []
            return
        }
        elementos = (try? repositorio.listar()) ?? []
        let vivos = Set(elementos.map(\.id))
        miniaturas = miniaturas.filter { vivos.contains($0.key) }
        miniaturasPedidas.formIntersection(vivos)
        for elemento in elementos where !miniaturasPedidas.contains(elemento.id) {
            pedirMiniatura(de: elemento)
        }
    }

    // MARK: - Limpieza automática (cada elemento vive 10 minutos)

    public func iniciarLimpiezaAutomatica() {
        guard tareaLimpieza == nil else { return }
        limpiarVencidos()
        tareaLimpieza = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.limpiarVencidos()
            }
        }
    }

    public func detenerLimpiezaAutomatica() {
        tareaLimpieza?.cancel()
        tareaLimpieza = nil
    }

    /// Quita del Shelf lo que lleva más de `vidaEnShelf` (borra solo la copia interna).
    @discardableResult
    public func limpiarVencidos(ahora: Date = .now) -> Int {
        guard let repositorio else { return 0 }
        let vencidos = elementos.filter { ahora.timeIntervalSince($0.creado) >= Self.vidaEnShelf }
        guard !vencidos.isEmpty else { return 0 }
        for elemento in vencidos {
            if let rutaCopia = try? repositorio.quitar(elemento.id) {
                borrarCopiaInterna(rutaCopia)
            }
        }
        recargar()
        return vencidos.count
    }

    // MARK: - Agregar y quitar

    /// Aviso breve en las orejas de la isla cerrada: "3 archivos".
    private func avisarEnLasOrejas(_ cantidad: Int) {
        guard let bus else { return }
        Task { await bus.publicar(ActividadBreveSolicitada(.archivos(cantidad))) }
    }

    /// Agrega archivos copiándolos a la carpeta de la bandeja (BND-1). Síncrono; la vista usa `agregarEnSegundoPlano`.
    @discardableResult
    public func agregarArchivos(_ urls: [URL]) -> Int {
        guard let repositorio, let carpetaBandeja else { return 0 }
        let copias = Self.copiar(urls, a: carpetaBandeja)
        let agregados = copias.filter { (try? repositorio.agregar($0)) != nil }.count
        recargar()
        if agregados > 0 {
            mostrarAvisoTemporal("Guardado en Shelf (\(agregados))")
            avisarEnLasOrejas(agregados)
        }
        return agregados
    }

    /// Copia fuera del hilo principal (archivos grandes no congelan la isla) y luego registra.
    public func agregarEnSegundoPlano(_ urls: [URL]) {
        guard let repositorio, let carpetaBandeja, !urls.isEmpty else { return }
        trabajando = true
        Task { [weak self] in
            let copias = await Task.detached(priority: .userInitiated) {
                Self.copiar(urls, a: carpetaBandeja)
            }.value
            guard let self else { return }
            let agregados = copias.filter { (try? repositorio.agregar($0)) != nil }.count
            self.trabajando = false
            self.recargar()
            if agregados > 0 {
                self.mostrarAvisoTemporal("Guardado en Shelf (\(agregados))")
                self.avisarEnLasOrejas(agregados)
            }
        }
    }

    nonisolated private static func copiar(_ urls: [URL], a carpeta: URL) -> [ElementoDeBandeja] {
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        var resultado: [ElementoDeBandeja] = []
        for url in urls where url.isFileURL {
            let rutaOriginal = url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: rutaOriginal) else { continue }
            let id = UUID().uuidString
            let nombre = url.lastPathComponent
            let destino = carpeta.appending(path: "\(id)-\(nombre)")
            guard (try? FileManager.default.copyItem(at: url, to: destino)) != nil else { continue }
            let bytes = (try? destino.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            resultado.append(
                ElementoDeBandeja(
                    id: id,
                    nombre: nombre,
                    rutaOriginal: rutaOriginal,
                    rutaCopia: destino.path,
                    bytes: bytes
                )
            )
        }
        return resultado
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

    // MARK: - Miniaturas

    private func pedirMiniatura(de elemento: ElementoDeBandeja) {
        miniaturasPedidas.insert(elemento.id)
        let url = elemento.urlParaArrastrar
        let id = elemento.id
        Task { [weak self] in
            let imagen = await Task.detached(priority: .utility) { Self.miniatura(de: url) }.value
            guard let self, self.miniaturasPedidas.contains(id) else { return }
            self.miniaturas[id] = imagen ?? NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    /// Decodifica solo una versión de 64 px con ImageIO (no la imagen completa).
    nonisolated static func miniatura(de url: URL, lado: Int = 64) -> NSImage? {
        guard let fuente = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opciones: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: lado,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let imagen = CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: imagen, size: NSSize(width: imagen.width, height: imagen.height))
    }

    // MARK: - Acciones sobre archivos soltados o en la bandeja

    public var urlsEnBandeja: [URL] {
        elementos.map(\.urlParaArrastrar).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func guardarEnICloud(_ urls: [URL]) {
        let archivos = urls.isEmpty ? urlsEnBandeja : urls
        guard !archivos.isEmpty else {
            elegirArchivosYEjecutar { self.guardarEnICloud($0) }
            return
        }
        ejecutarEnSegundoPlano(
            {
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
                return ([], copiados > 0 ? "Guardado en iCloud Drive (\(copiados))" : "No se pudo copiar a iCloud")
            })
    }

    public func convertirImagenes(_ urls: [URL]) {
        let archivos = urls.isEmpty ? urlsEnBandeja : urls
        guard !archivos.isEmpty else {
            elegirArchivosYEjecutar { self.convertirImagenes($0) }
            return
        }
        let formato = formatoConversion
        ejecutarEnSegundoPlano(
            {
                let descargas = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
                let ext = formato.lowercased()
                let tipo: NSBitmapImageRep.FileType = (ext == "jpg" || ext == "jpeg") ? .jpeg : .png
                var salidas: [URL] = []
                for url in archivos {
                    guard let fuente = CGImageSourceCreateWithURL(url as CFURL, nil),
                        let imagen = CGImageSourceCreateImageAtIndex(fuente, 0, nil),
                        let datos = NSBitmapImageRep(cgImage: imagen).representation(using: tipo, properties: [:])
                    else { continue }
                    let base = url.deletingPathExtension().lastPathComponent
                    let salida = descargas.appending(path: "\(base)-converted.\(ext)")
                    if (try? datos.write(to: salida, options: .atomic)) != nil {
                        salidas.append(salida)
                    }
                }
                return (
                    salidas,
                    salidas.isEmpty ? "Suelta una imagen para convertir" : "Convertidas a \(formato) (\(salidas.count))"
                )
            })
    }

    public func comprimirEnZip(_ urls: [URL]) {
        let archivos = urls.isEmpty ? urlsEnBandeja : urls
        guard let primero = archivos.first else {
            elegirArchivosYEjecutar { self.comprimirEnZip($0) }
            return
        }
        ejecutarEnSegundoPlano(
            {
                let descargas = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
                let nombreZip = "\(primero.deletingPathExtension().lastPathComponent).zip"
                let salidaZip = descargas.appending(path: nombreZip)
                try? FileManager.default.removeItem(at: salidaZip)
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                proc.arguments = ["-j", "-q", salidaZip.path] + archivos.map(\.path)
                try? proc.run()
                proc.waitUntilExit()
                guard FileManager.default.fileExists(atPath: salidaZip.path) else {
                    return ([], "No se pudo crear el zip")
                }
                return ([salidaZip], "Creado \(nombreZip)")
            })
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

    /// Corre `trabajo` fuera del hilo principal; lo que devuelva en `nuevos` entra al Shelf.
    private func ejecutarEnSegundoPlano(
        _ trabajo: @escaping @Sendable () -> (nuevos: [URL], aviso: String)
    ) {
        trabajando = true
        Task { [weak self] in
            let resultado = await Task.detached(priority: .userInitiated, operation: trabajo).value
            guard let self else { return }
            self.trabajando = false
            if !resultado.nuevos.isEmpty {
                self.agregarEnSegundoPlano(resultado.nuevos)
            }
            self.mostrarAvisoTemporal(resultado.aviso)
        }
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
