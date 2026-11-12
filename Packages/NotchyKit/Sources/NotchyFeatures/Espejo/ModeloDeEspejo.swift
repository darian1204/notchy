import Foundation
import NotchyCore
import OSLog
import Observation
import SwiftUI

/// Modelo observable del módulo Espejo: enciende la cámara al abrirse y la apaga de inmediato al cerrarse (ESP-1).
@MainActor
@Observable
public final class ModeloDeEspejo {
    public private(set) var permiso: EstadoDePermiso
    public private(set) var encendida = false
    public private(set) var nombreDispositivo: String
    public private(set) var mensajeDeError: String?

    @ObservationIgnored private let puerto: any PuertoDeCamara
    @ObservationIgnored private let bus: BusDeEventos?
    @ObservationIgnored private let alAbrirURL: (@MainActor (URL) -> Void)?
    @ObservationIgnored private var tareaEventosIsla: Task<Void, Never>?
    @ObservationIgnored private let log = Registro.de(.espejo)

    public init(
        puerto: any PuertoDeCamara,
        bus: BusDeEventos? = nil,
        alAbrirURL: (@MainActor (URL) -> Void)? = nil
    ) {
        self.puerto = puerto
        self.bus = bus
        self.alAbrirURL = alAbrirURL
        self.permiso = puerto.estadoDePermiso()
        self.nombreDispositivo = puerto.nombreDispositivo
    }

    public var vistaPrevia: AnyView {
        puerto.vistaPrevia
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
