import Foundation
import NotchyCore
import SwiftUI

/// Falso de `PuertoDeCamara` para probar el ciclo de vida del Espejo sin hardware.
@MainActor
public final class CamaraFalsa: PuertoDeCamara {
    public var permiso: EstadoDePermiso
    public var fallaAlEncender: String?
    public private(set) var encendida = false
    public var nombreDispositivo = "Cámara de prueba"
    public private(set) var encendidos = 0
    public private(set) var apagados = 0
    public private(set) var peticionesDePermiso = 0
    public var datosFotoFalsa = Data([0x89, 0x50, 0x4E, 0x47])

    public init(permiso: EstadoDePermiso = .concedido, fallaAlEncender: String? = nil) {
        self.permiso = permiso
        self.fallaAlEncender = fallaAlEncender
    }

    public var vistaPrevia: AnyView {
        AnyView(Color.clear)
    }

    public func estadoDePermiso() -> EstadoDePermiso {
        permiso
    }

    public func pedirPermiso() async -> EstadoDePermiso {
        peticionesDePermiso += 1
        return permiso
    }

    public func encender() async throws {
        if let fallaAlEncender {
            throw NotchyError.noDisponible(fallaAlEncender)
        }
        encendida = true
        encendidos += 1
    }

    public func apagar() async {
        if encendida {
            encendida = false
            apagados += 1
        }
    }

    public func capturarFotoPNG() async throws -> Data {
        guard encendida else {
            throw NotchyError.noDisponible("Cámara apagada")
        }
        return datosFotoFalsa
    }
}

/// Falso de `PuertoDeAirDrop` para probar recepción y envío sin Finder ni NSSharingService.
@MainActor
public final class AirDropFalso: PuertoDeAirDrop {
    public var rutaDescargas = "/Users/prueba/Downloads"
    public var archivosRecibidos: [ArchivoRecibidoAirDrop]
    public var errorAlListar: String?
    public private(set) var vigilando = false
    public private(set) var lotesEnviados: [[URL]] = []
    private var oyente: (@MainActor () -> Void)?

    public init(archivos: [ArchivoRecibidoAirDrop] = []) {
        self.archivosRecibidos = archivos
    }

    public func listarRecibidos() throws -> [ArchivoRecibidoAirDrop] {
        if let errorAlListar {
            throw NotchyError.noDisponible(errorAlListar)
        }
        return archivosRecibidos
    }

    public func vigilarRecibidos(alCambiar: @escaping @MainActor () -> Void) {
        vigilando = true
        oyente = alCambiar
    }

    public func detenerVigilancia() {
        vigilando = false
        oyente = nil
    }

    public func enviar(archivos: [URL], alTerminar: @escaping @MainActor (Bool) -> Void) throws {
        lotesEnviados.append(archivos)
        alTerminar(true)
    }

    public func simularLlegada(_ archivo: ArchivoRecibidoAirDrop) {
        archivosRecibidos.insert(archivo, at: 0)
        oyente?()
    }
}
