import CryptoKit
import Foundation
import NotchyCore
import NotchyStorage
import Observation

/// Modelo de vista y coordinador del módulo de Portapapeles (CLP-1 a CLP-7).
@MainActor
@Observable
public final class ModeloDePortapapeles {
    public private(set) var elementos: [ElementoDePortapapeles] = []
    public private(set) var totalGuardados = 0
    public private(set) var idSeleccionado: String?
    public var busqueda = "" {
        didSet {
            guard busqueda != oldValue else { return }
            recargar()
        }
    }
    public var filtroTipo: TipoDePortapapeles? {
        didSet {
            guard filtroTipo != oldValue else { return }
            recargar()
        }
    }

    @ObservationIgnored private let puerto: any PuertoDePortapapeles
    @ObservationIgnored private let repositorio: RepositorioDePortapapeles?
    @ObservationIgnored private let carpetaImagenes: URL?
    @ObservationIgnored private let ajustes: Ajustes
    @ObservationIgnored private let bus: BusDeEventos?
    @ObservationIgnored private let dormir: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var tareaVigilancia: Task<Void, Never>?
    @ObservationIgnored private var ultimoConteo: Int
    @ObservationIgnored private var ultimaHuellaEnPortapapeles: String?

    public init(
        puerto: any PuertoDePortapapeles,
        repositorio: RepositorioDePortapapeles?,
        carpetaImagenes: URL?,
        ajustes: Ajustes,
        bus: BusDeEventos? = nil,
        dormir: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.puerto = puerto
        self.repositorio = repositorio
        self.carpetaImagenes = carpetaImagenes
        self.ajustes = ajustes
        self.bus = bus
        self.dormir = dormir
        self.ultimoConteo = puerto.conteoDeCambios

        ajustes.observar { [weak self] in
            self?.aplicarRetencionYRecargar()
        }
        recargar()
    }

    public func iniciarVigilancia() {
        guard tareaVigilancia == nil else { return }
        ultimoConteo = puerto.conteoDeCambios
        let dormir = self.dormir
        tareaVigilancia = Task { [weak self] in
            while !Task.isCancelled {
                guard (try? await dormir(.milliseconds(500))) != nil, !Task.isCancelled else { break }
                self?.revisarSiCambio()
            }
        }
    }

    public func detenerVigilancia() {
        tareaVigilancia?.cancel()
        tareaVigilancia = nil
    }

    /// Revisa el contador del portapapeles; solo lee el contenido y publica si hubo una copia nueva (S8).
    public func revisarSiCambio() {
        let conteo = puerto.conteoDeCambios
        guard conteo != ultimoConteo else { return }
        ultimoConteo = conteo
        procesarMuestra(puerto.leerActual())
    }

    public func recargar() {
        guard let repositorio else {
            elementos = []
            totalGuardados = 0
            idSeleccionado = nil
            return
        }
        do {
            elementos = try repositorio.listar(busqueda: busqueda, tipo: filtroTipo, limite: 100)
            totalGuardados = try repositorio.total()
            if let actual = idSeleccionado, elementos.contains(where: { $0.id == actual }) {
                // Conserva la selección actual.
            } else {
                idSeleccionado = elementos.first?.id
            }
        } catch {
            elementos = []
        }
    }

    public func seleccionar(_ id: String) {
        idSeleccionado = id
    }

    /// Vuelve a copiar el elemento al portapapeles del sistema sin duplicar ni alterar su origen (CLP-4).
    public func copiarAlSistema(_ elemento: ElementoDePortapapeles) {
        ultimoConteo = puerto.escribir(elemento)
        ultimaHuellaEnPortapapeles = elemento.huella
        idSeleccionado = elemento.id
    }

    public func copiarSeleccionado() {
        guard let id = idSeleccionado, let elemento = elementos.first(where: { $0.id == id }) else { return }
        copiarAlSistema(elemento)
    }

    /// Fija o desfija un elemento para que no lo borre la retención (CLP-6).
    public func alternarFijado(_ id: String) {
        guard let repositorio else { return }
        _ = try? repositorio.alternarFijado(id)
        recargar()
    }

    /// Borra un elemento del historial y, si es lo que está actualmente en el portapapeles, también de ahí (CLP-7).
    public func borrar(_ elemento: ElementoDePortapapeles) {
        guard let repositorio else { return }
        if let ruta = try? repositorio.borrar(elemento.id) {
            borrarArchivoSiEstaEnCarpetaPropia(ruta)
        }
        if ultimaHuellaEnPortapapeles == elemento.huella {
            puerto.limpiar()
            ultimoConteo = puerto.conteoDeCambios
            ultimaHuellaEnPortapapeles = nil
        }
        recargar()
    }

    /// Vacía la base y los archivos guardados del portapapeles (CLP-5).
    public func borrarTodo() {
        guard let repositorio else { return }
        let rutas = (try? repositorio.borrarTodo()) ?? []
        for ruta in rutas {
            borrarArchivoSiEstaEnCarpetaPropia(ruta)
        }
        recargar()
    }

    public func aplicarRetencionYRecargar(ahora: Date = .now) {
        guard let repositorio else { return }
        let rutas =
            (try? repositorio.aplicarRetencion(
                diasMaximos: ajustes.diasRetencionPortapapeles,
                elementosMaximos: ajustes.limiteElementosPortapapeles,
                ahora: ahora
            )) ?? []
        for ruta in rutas {
            borrarArchivoSiEstaEnCarpetaPropia(ruta)
        }
        recargar()
    }

    // MARK: Procesamiento de copias

    private func procesarMuestra(_ muestra: MuestraDePortapapeles) {
        if let bundle = muestra.bundleOrigen, ajustes.appsExcluidasPortapapeles.contains(bundle) {
            return
        }
        guard let repositorio else { return }

        let candidato: ElementoDePortapapeles?
        switch muestra.carga {
        case .sensible, .vacia:
            return
        case .texto(let texto):
            let tipo: TipoDePortapapeles = Self.esEnlace(texto) ? .enlace : .texto
            let huella = Self.sha256("texto:\(texto)")
            candidato = ElementoDePortapapeles(
                tipo: tipo,
                texto: texto,
                huella: huella,
                appOrigen: muestra.appOrigen,
                bundleOrigen: muestra.bundleOrigen,
                bytes: texto.utf8.count
            )
        case .archivos(let urls):
            guard let primera = urls.first else { return }
            let nombres = urls.map(\.lastPathComponent).joined(separator: ", ")
            let rutasUnidas = urls.map(\.path).joined(separator: "\n")
            let huella = Self.sha256("archivos:\(rutasUnidas)")
            let tamano =
                (try? primera.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? rutasUnidas.utf8.count
            candidato = ElementoDePortapapeles(
                tipo: .archivo,
                texto: nombres,
                rutaArchivo: primera.path,
                huella: huella,
                appOrigen: muestra.appOrigen,
                bundleOrigen: muestra.bundleOrigen,
                bytes: tamano
            )
        case .imagenPNG(let datos):
            let huella = Self.sha256(datos)
            let id = UUID().uuidString
            var rutaGuardada: String?
            if let carpetaImagenes {
                try? FileManager.default.createDirectory(at: carpetaImagenes, withIntermediateDirectories: true)
                let destino = carpetaImagenes.appending(path: "\(id).png")
                if (try? datos.write(to: destino, options: .atomic)) != nil {
                    rutaGuardada = destino.path
                }
            }
            let etiquetaTamano = ByteCountFormatter.string(fromByteCount: Int64(datos.count), countStyle: .file)
            candidato = ElementoDePortapapeles(
                id: id,
                tipo: .imagen,
                texto: "Imagen (\(etiquetaTamano))",
                rutaArchivo: rutaGuardada,
                huella: huella,
                appOrigen: muestra.appOrigen,
                bundleOrigen: muestra.bundleOrigen,
                bytes: datos.count
            )
        }

        guard let candidato else { return }
        ultimaHuellaEnPortapapeles = candidato.huella

        guard let resultado = try? repositorio.registrar(candidato) else { return }
        if let descartada = resultado.rutaAnteriorDescartada {
            borrarArchivoSiEstaEnCarpetaPropia(descartada)
        }
        aplicarRetencionYRecargar()
        if let bus {
            let evento = ElementoDePortapapelesAgregado(elemento: resultado.guardado)
            Task { await bus.publicar(evento) }
        }
    }

    private func borrarArchivoSiEstaEnCarpetaPropia(_ ruta: String) {
        guard let carpetaImagenes else { return }
        let url = URL(fileURLWithPath: ruta)
        guard url.deletingLastPathComponent().standardizedFileURL == carpetaImagenes.standardizedFileURL else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    static func esEnlace(_ texto: String) -> Bool {
        guard !texto.contains(where: \.isWhitespace),
            let url = URL(string: texto),
            let esquema = url.scheme?.lowercased(),
            esquema == "http" || esquema == "https",
            url.host?.isEmpty == false
        else { return false }
        return true
    }

    static func sha256(_ texto: String) -> String {
        sha256(Data(texto.utf8))
    }

    static func sha256(_ datos: Data) -> String {
        SHA256.hash(data: datos).map { String(format: "%02x", $0) }.joined()
    }
}
