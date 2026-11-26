import Foundation
import SwiftUI

/// Archivo en `~/Downloads` cuyo origen en cuarentena es `sharingd` (AIR-1, S11).
public struct ArchivoRecibidoAirDrop: Identifiable, Sendable, Equatable {
    public let id: String
    public let nombre: String
    public let ruta: String
    public let fechaRecibido: Date
    public let bytes: Int64

    public init(
        id: String? = nil,
        nombre: String,
        ruta: String,
        fechaRecibido: Date,
        bytes: Int64
    ) {
        self.id = id ?? ruta
        self.nombre = nombre
        self.ruta = ruta
        self.fechaRecibido = fechaRecibido
        self.bytes = bytes
    }

    public var url: URL {
        URL(fileURLWithPath: ruta)
    }
}

/// Puerto de vigilancia de archivos recibidos y envío por AirDrop (AIR-1, AIR-2).
@MainActor
public protocol PuertoDeAirDrop: AnyObject {
    var rutaDescargas: String { get }
    func listarRecibidos() throws -> [ArchivoRecibidoAirDrop]
    func vigilarRecibidos(alCambiar: @escaping @MainActor () -> Void)
    func detenerVigilancia()
    /// Abre el selector de AirDrop. `alTerminar` avisa si el envío se completó (`true`) o falló.
    func enviar(archivos: [URL], alTerminar: @escaping @MainActor (Bool) -> Void) throws
}

/// Evento publicado cuando llega un archivo nuevo por AirDrop (AIR-1).
public struct ArchivoAirDropDetectado: Evento, Equatable {
    public let archivo: ArchivoRecibidoAirDrop

    public init(archivo: ArchivoRecibidoAirDrop) {
        self.archivo = archivo
    }
}

/// Puerto de cámara para el módulo de Espejo (ESP-1).
@MainActor
public protocol PuertoDeCamara: AnyObject {
    var encendida: Bool { get }
    var nombreDispositivo: String { get }
    var vistaPrevia: AnyView { get }
    func estadoDePermiso() -> EstadoDePermiso
    func pedirPermiso() async -> EstadoDePermiso
    func encender() async throws
    func apagar() async
    /// Captura un cuadro espejado en PNG.
    func capturarFotoPNG() async throws -> Data
}
