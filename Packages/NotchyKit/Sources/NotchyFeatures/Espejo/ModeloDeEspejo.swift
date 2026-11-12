import Foundation
import NotchyCore
import OSLog
import Observation
import SwiftUI

/// Modelo observable del módulo Espejo: enciende la cámara solo cuando el módulo está abierto y permite tomar fotos (ESP-1, RNF-7).
@MainActor
@Observable
public final class ModeloDeEspejo {
    public private(set) var encendida = false
    public private(set) var permiso: EstadoDePermiso = .sinPedir
    public private(set) var nombreDispositivo = "MacBook Air Camera"
    public private(set) var mensajeDeError: String?
    public private(set) var ultimaFotoGuardada: URL?

    @ObservationIgnored private let puerto: any PuertoDeCamara
    @ObservationIgnored private let ajustes: Ajustes
    @ObservationIgnored private let bus: BusDeEventos?
    @ObservationIgnored private let alAbrirURL: (@MainActor (URL) -> Void)?
    @ObservationIgnored private var tareaEventosIsla: Task<Void, Never>?
    @ObservationIgnored private let log = Registro.de(.espejo)

    public init(
        puerto: any PuertoDeCamara,
        ajustes: Ajustes? = nil,
        bus: BusDeEventos? = nil,
        alAbrirURL: (@MainActor (URL) -> Void)? = nil
    ) {
        self.puerto = puerto
        self.ajustes = ajustes ?? Ajustes(almacen: AlmacenEnMemoriaInterno())
        self.bus = bus
        self.alAbrirURL = alAbrirURL
        self.permiso = puerto.estadoDePermiso()
        self.nombreDispositivo = puerto.nombreDispositivo
    }

    public var vistaPrevia: AnyView {
        puerto.vistaPrevia
    }

    public var carpetaFotos: String {
        get { ajustes.carpetaFotosEspejo }
        set { ajustes.carpetaFotosEspejo = newValue }
    }

    public var nombreCarpetaFotos: String {
        URL(fileURLWithPath: ajustes.carpetaFotosEspejo).lastPathComponent
    }

    public var salud: SaludDeModulo {
        if permiso != .concedido {
            return .faltaPermiso(PermisoDelSistema.camara.nombre)
        }
        if let mensajeDeError {
            return .error(mensajeDeError)
        }
        return .listo
    }

    public func iniciar() {
        detenerVigilancia()
        permiso = puerto.estadoDePermiso()
        guard let bus else { return }
        tareaEventosIsla = Task { [weak self] in
            let flujo = await bus.suscribir(a: IslaCambioDeEstado.self)
            for await cambio in flujo {
                guard let self else { break }
                if cambio.moduloAbierto == "espejo" {
                    await self.abrirEspejo()
                } else if self.encendida {
                    await self.cerrarEspejo()
                }
            }
        }
    }

    public func detener() {
        detenerVigilancia()
        if encendida {
            let puertoCapturado = puerto
            encendida = false
            Task { await puertoCapturado.apagar() }
        }
    }

    public func abrirEspejo() async {
        permiso = puerto.estadoDePermiso()
        if permiso == .sinPedir {
            permiso = await puerto.pedirPermiso()
            if let bus {
                await bus.publicar(CambioDePermiso(permiso: .camara, estado: permiso))
            }
        }
        guard permiso == .concedido else {
            encendida = false
            return
        }
        guard !encendida else { return }
        do {
            try await puerto.encender()
            encendida = puerto.encendida
            nombreDispositivo = puerto.nombreDispositivo
            mensajeDeError = nil
        } catch {
            encendida = false
            mensajeDeError = error.localizedDescription
            log.error("No se pudo encender el espejo: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func cerrarEspejo() async {
        guard encendida || puerto.encendida else { return }
        await puerto.apagar()
        encendida = false
    }

    @discardableResult
    public func tomarFoto(ahora: Date = .now) async -> URL? {
        do {
            let datos = try await puerto.capturarFotoPNG()
            let carpeta = URL(fileURLWithPath: ajustes.carpetaFotosEspejo)
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            let formateador = DateFormatter()
            formateador.locale = Locale(identifier: "en_US_POSIX")
            formateador.dateFormat = "yyyy-MM-dd-HHmmss"
            let nombre = "Notchy-Espejo-\(formateador.string(from: ahora)).png"
            let destino = carpeta.appending(path: nombre)
            try datos.write(to: destino, options: .atomic)
            ultimaFotoGuardada = destino
            mensajeDeError = nil
            return destino
        } catch {
            mensajeDeError = error.localizedDescription
            log.error("No se pudo guardar la foto del espejo: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func abrirUltimaFoto() {
        guard let url = ultimaFotoGuardada else { return }
        alAbrirURL?(url)
    }

    public func abrirCarpetaFotos() {
        alAbrirURL?(URL(fileURLWithPath: ajustes.carpetaFotosEspejo))
    }

    public func abrirAjustesDePermiso() {
        if let url = PermisoDelSistema.camara.enlaceDeAjustesDelSistema {
            alAbrirURL?(url)
        }
    }

    private func detenerVigilancia() {
        tareaEventosIsla?.cancel()
        tareaEventosIsla = nil
    }
}

private final class AlmacenEnMemoriaInterno: AlmacenDeAjustes, @unchecked Sendable {
    private var datos: [String: Data] = [:]
    func leer(_ clave: String) -> Data? { datos[clave] }
    func guardar(_ dato: Data?, en clave: String) { datos[clave] = dato }
}
