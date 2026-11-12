import AppKit
import Darwin
import Foundation
import NotchyCore

/// Adaptador real de AirDrop: vigila `~/Downloads` buscando el atributo `com.apple.quarantine`
/// con `sharingd` y abre el selector de envío `NSSharingService(.sendViaAirDrop)` (AIR-1, AIR-2, S11).
@MainActor
public final class AdaptadorDeAirDrop: PuertoDeAirDrop {
    private let carpeta: URL
    private var fuente: DispatchSourceFileSystemObject?

    public init(
        carpetaDescargas: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Downloads")
    ) {
        self.carpeta = carpetaDescargas
    }

    public var rutaDescargas: String {
        carpeta.path
    }

    public func listarRecibidos() throws -> [ArchivoRecibidoAirDrop] {
        let fm = FileManager.default
        var esDirectorio: ObjCBool = false
        guard fm.fileExists(atPath: carpeta.path, isDirectory: &esDirectorio), esDirectorio.boolValue else {
            throw NotchyError.noDisponible("No se encontró la carpeta Descargas en \(carpeta.path)")
        }

        let claves: [URLResourceKey] = [
            .isHiddenKey,
            .addedToDirectoryDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]
        let urls = try fm.contentsOfDirectory(
            at: carpeta,
            includingPropertiesForKeys: claves,
            options: [.skipsHiddenFiles]
        )

        var recibidos: [ArchivoRecibidoAirDrop] = []
        for url in urls {
            guard Self.esOrigenAirDrop(ruta: url.path) else { continue }
            let valores = try? url.resourceValues(forKeys: Set(claves))
            let fecha = valores?.addedToDirectoryDate ?? valores?.contentModificationDate ?? .distantPast
            let tamano = Int64(valores?.fileSize ?? 0)
            recibidos.append(
                ArchivoRecibidoAirDrop(
                    nombre: url.lastPathComponent,
                    ruta: url.path,
                    fechaRecibido: fecha,
                    bytes: tamano
                ))
        }
        return recibidos.sorted { $0.fechaRecibido > $1.fechaRecibido }
    }

    public func vigilarRecibidos(alCambiar: @escaping @MainActor () -> Void) {
        detenerVigilancia()
        let descriptor = open(carpeta.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let nuevaFuente = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .extend],
            queue: .main
        )
        nuevaFuente.setEventHandler {
            MainActor.assumeIsolated {
                alCambiar()
            }
        }
        nuevaFuente.setCancelHandler {
            close(descriptor)
        }
        nuevaFuente.resume()
        fuente = nuevaFuente
    }

    public func detenerVigilancia() {
        fuente?.cancel()
        fuente = nil
    }

    public func enviar(archivos: [URL]) throws {
        guard !archivos.isEmpty else { return }
        guard let servicio = NSSharingService(named: .sendViaAirDrop),
            servicio.canPerform(withItems: archivos)
        else {
            throw NotchyError.noDisponible("El servicio de AirDrop no está disponible")
        }
        NSApp.activate()
        servicio.perform(withItems: archivos)
    }

    /// Comprueba si el atributo extendido `com.apple.quarantine` fue escrito por `sharingd` (S11).
    nonisolated public static func esOrigenAirDrop(ruta: String) -> Bool {
        guard let cuarentena = leerAtributoExtend(ruta: ruta, nombre: "com.apple.quarantine") else {
            return false
        }
        return cuarentena.localizedCaseInsensitiveContains("sharingd")
    }

    nonisolated public static func leerAtributoExtend(ruta: String, nombre: String) -> String? {
        let longitud = getxattr(ruta, nombre, nil, 0, 0, 0)
        guard longitud > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: longitud)
        guard getxattr(ruta, nombre, &buffer, longitud, 0, 0) == longitud else { return nil }
        return String(decoding: buffer, as: UTF8.self)
    }

    nonisolated public static func escribirAtributoExtend(ruta: String, nombre: String, valor: String) -> Bool {
        let bytes = Array(valor.utf8)
        return bytes.withUnsafeBytes { puntero in
            setxattr(ruta, nombre, puntero.baseAddress, bytes.count, 0, 0) == 0
        }
    }
}
