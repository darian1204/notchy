import AppKit
import Foundation
import NotchyCore
import OSLog
import SQLite3

/// Lee la base de Notification Center (`group.com.apple.usernoted/db2/db`).
/// Requiere Acceso total al disco; se trabaja sobre una copia para no bloquear a `usernoted`.
public final class AdaptadorDeNotificacionesDelSistema: PuertoDeNotificacionesDelSistema {
    private let log = Logger(subsystem: "dev.darian.notchy", category: "notificaciones")

    public init() {}

    private var carpetaDeLaBase: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Group Containers/group.com.apple.usernoted/db2", directoryHint: .isDirectory)
    }

    public func tieneAcceso() -> Bool {
        FileManager.default.isReadableFile(atPath: carpetaDeLaBase.appending(path: "db").path)
    }

    public func recientes(limite: Int) async throws -> [NotificacionReciente] {
        let copia = try copiarBase()
        defer { try? FileManager.default.removeItem(at: copia.deletingLastPathComponent()) }
        let filas = try leerFilas(de: copia, limite: limite)
        return await MainActor.run { filas.map { $0.convertir() } }
    }

    // MARK: Copia

    private func copiarBase() throws -> URL {
        let fm = FileManager.default
        let destino = fm.temporaryDirectory.appending(
            path: "notchy-nc-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: destino, withIntermediateDirectories: true)
        for nombre in ["db", "db-wal", "db-shm"] {
            let origen = carpetaDeLaBase.appending(path: nombre)
            guard fm.fileExists(atPath: origen.path) else { continue }
            try fm.copyItem(at: origen, to: destino.appending(path: nombre))
        }
        return destino.appending(path: "db")
    }

    // MARK: Lectura

    struct Fila: Sendable {
        let id: Int64
        let bundleId: String
        let titulo: String
        let subtitulo: String?
        let cuerpo: String
        let fecha: Date

        @MainActor
        func convertir() -> NotificacionReciente {
            NotificacionReciente(
                id: "nc-\(id)",
                bundleId: bundleId,
                nombreApp: AdaptadorDeNotificacionesDelSistema.nombreVisible(de: bundleId),
                titulo: titulo,
                subtitulo: subtitulo,
                cuerpo: cuerpo,
                fecha: fecha
            )
        }
    }

    private func leerFilas(de ruta: URL, limite: Int) throws -> [Fila] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(ruta.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw ErrorDeNotificaciones.noSePudoAbrir
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date
            FROM record r JOIN app a ON a.app_id = r.app_id
            ORDER BY r.delivered_date DESC
            LIMIT ?
            """
        var sentencia: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &sentencia, nil) == SQLITE_OK else {
            let mensaje = String(cString: sqlite3_errmsg(db))
            log.error("Consulta de notificaciones inválida: \(mensaje, privacy: .public)")
            throw ErrorDeNotificaciones.esquemaDesconocido
        }
        defer { sqlite3_finalize(sentencia) }
        sqlite3_bind_int(sentencia, 1, Int32(limite))

        var filas: [Fila] = []
        while sqlite3_step(sentencia) == SQLITE_ROW {
            let id = sqlite3_column_int64(sentencia, 0)
            let bundleId = sqlite3_column_text(sentencia, 1).map { String(cString: $0) } ?? ""
            let fechaEntrega = sqlite3_column_double(sentencia, 3)
            guard let bytes = sqlite3_column_blob(sentencia, 2) else { continue }
            let datos = Data(bytes: bytes, count: Int(sqlite3_column_bytes(sentencia, 2)))
            guard let contenido = Self.decodificar(datos) else { continue }
            let fecha = fechaEntrega > 0 ? Date(timeIntervalSinceReferenceDate: fechaEntrega) : contenido.fecha ?? .now
            filas.append(
                Fila(
                    id: id,
                    bundleId: bundleId,
                    titulo: contenido.titulo,
                    subtitulo: contenido.subtitulo,
                    cuerpo: contenido.cuerpo,
                    fecha: fecha
                ))
        }
        return filas
    }

    /// El blob `data` es un plist binario: `{ app, req: { titl, subt, body, date } }`.
    static func decodificar(_ datos: Data) -> (titulo: String, subtitulo: String?, cuerpo: String, fecha: Date?)? {
        guard
            let raiz = try? PropertyListSerialization.propertyList(from: datos, format: nil) as? [String: Any],
            let req = raiz["req"] as? [String: Any]
        else {
            return nil
        }
        let titulo = (req["titl"] as? String) ?? ""
        let subtitulo = (req["subt"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let cuerpo = (req["body"] as? String) ?? ""
        guard !titulo.isEmpty || !cuerpo.isEmpty else { return nil }
        let fecha = (req["date"] as? Double).map { Date(timeIntervalSinceReferenceDate: $0) } ?? (req["date"] as? Date)
        return (titulo.isEmpty ? cuerpo : titulo, subtitulo, titulo.isEmpty ? "" : cuerpo, fecha)
    }

    @MainActor
    static func nombreVisible(de bundleId: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return bundleId.split(separator: ".").last.map(String.init)?.capitalized ?? bundleId
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

enum ErrorDeNotificaciones: Error {
    case noSePudoAbrir
    case esquemaDesconocido
}
