import Foundation
import NotchyCore
import OSLog
import Observation

/// Modelo observable del módulo AirDrop: vigila los recibidos en `~/Downloads` y envía archivos (AIR-1, AIR-2).
@MainActor
@Observable
public final class ModeloDeAirDrop {
    public private(set) var recibidos: [ArchivoRecibidoAirDrop] = []
    public private(set) var mensajeDeError: String?

    @ObservationIgnored private let puerto: any PuertoDeAirDrop
    @ObservationIgnored private let bus: BusDeEventos?
    @ObservationIgnored private let alAbrirArchivo: (@MainActor (URL) -> Void)?
    @ObservationIgnored private let alRevelarArchivo: (@MainActor (URL) -> Void)?
    @ObservationIgnored private var rutasConocidas: Set<String> = []
    @ObservationIgnored private var inicializado = false
    /// Archivos recibidos que aún no se avisaron: AirDrop escribe cada archivo por separado, así que se
    /// espera un momento para dar un solo aviso con todos.
    @ObservationIgnored private var recibidosSinAvisar: [String] = []
    @ObservationIgnored private var tareaDeAviso: Task<Void, Never>?
    static let esperaParaAgrupar: Duration = .milliseconds(900)
    @ObservationIgnored private let log = Registro.de(.airdrop)

    public init(
        puerto: any PuertoDeAirDrop,
        bus: BusDeEventos? = nil,
        alAbrirArchivo: (@MainActor (URL) -> Void)? = nil,
        alRevelarArchivo: (@MainActor (URL) -> Void)? = nil
    ) {
        self.puerto = puerto
        self.bus = bus
        self.alAbrirArchivo = alAbrirArchivo
        self.alRevelarArchivo = alRevelarArchivo
    }

    public var rutaDescargas: String {
        puerto.rutaDescargas
    }

    public var salud: SaludDeModulo {
        if let mensajeDeError {
            return .error(mensajeDeError)
        }
        return .listo
    }

    public func iniciar() {
        inicializado = false
        recargar()
        puerto.vigilarRecibidos { [weak self] in
            self?.recargar()
        }
    }

    public func detener() {
        tareaDeAviso?.cancel()
        tareaDeAviso = nil
        recibidosSinAvisar = []
        puerto.detenerVigilancia()
    }

    public func recargar() {
        do {
            let lista = try puerto.listarRecibidos()
            let nuevasRutas = Set(lista.map(\.ruta))
            if inicializado, let bus {
                let nuevos = lista.filter { !rutasConocidas.contains($0.ruta) }
                for archivo in nuevos {
                    Task { await bus.publicar(ArchivoAirDropDetectado(archivo: archivo)) }
                }
                if !nuevos.isEmpty {
                    recibidosSinAvisar += nuevos.map(\.nombre)
                    programarAvisoDeRecibidos(bus: bus)
                }
            }
            rutasConocidas = nuevasRutas
            inicializado = true
            recibidos = lista
            mensajeDeError = nil
        } catch {
            recibidos = []
            mensajeDeError = "No se pudo leer \(puerto.rutaDescargas)"
            log.error("Error al listar AirDrop en Descargas: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Un solo aviso en las orejas por tanda: se reinicia la espera con cada archivo que llega.
    private func programarAvisoDeRecibidos(bus: BusDeEventos) {
        tareaDeAviso?.cancel()
        tareaDeAviso = Task { [weak self] in
            try? await Task.sleep(for: Self.esperaParaAgrupar)
            guard !Task.isCancelled, let self, !self.recibidosSinAvisar.isEmpty else { return }
            let aviso = EstadoDeHUDSistema.archivos(self.recibidosSinAvisar, tipo: .airdropRecibido)
            self.recibidosSinAvisar = []
            await bus.publicar(ActividadBreveSolicitada(aviso))
        }
    }

    public func enviar(archivos: [URL]) {
        let urls = archivos.filter(\.isFileURL)
        guard !urls.isEmpty else { return }
        do {
            let nombres = urls.map(\.lastPathComponent)
            try puerto.enviar(archivos: urls) { [weak self] completado in
                guard completado, let bus = self?.bus else { return }
                let aviso = EstadoDeHUDSistema.archivos(nombres, tipo: .airdropEnviado)
                Task { await bus.publicar(ActividadBreveSolicitada(aviso)) }
            }
            mensajeDeError = nil
        } catch {
            mensajeDeError = error.localizedDescription
            log.error("No se pudo enviar por AirDrop: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Abre el archivo con su aplicación predeterminada (Preview para imágenes/PDFs, etc.).
    public func abrirRecibido(_ archivo: ArchivoRecibidoAirDrop) {
        if let alAbrirArchivo {
            alAbrirArchivo(archivo.url)
        } else {
            alRevelarArchivo?(archivo.url)
        }
    }

    public func revelarRecibido(_ archivo: ArchivoRecibidoAirDrop) {
        alRevelarArchivo?(archivo.url)
    }

    public func abrirCarpetaDescargas() {
        if let alAbrirArchivo {
            alAbrirArchivo(URL(fileURLWithPath: puerto.rutaDescargas))
        } else {
            alRevelarArchivo?(URL(fileURLWithPath: puerto.rutaDescargas))
        }
    }
}
