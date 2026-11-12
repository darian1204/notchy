import Foundation
import GRDB
import NotchyCore

/// La base SQLite de Notchy. Al abrirla quedan aplicadas todas las migraciones.
public final class BaseDeDatos: Sendable {
    public let escritor: any DatabaseWriter
    /// `nil` cuando vive en memoria.
    public let ruta: URL?

    /// Abre (o crea) la base en disco, en modo WAL.
    public static func abrir(en ruta: URL) throws -> BaseDeDatos {
        try BaseDeDatos(escritor: DatabasePool(path: ruta.path), ruta: ruta)
    }

    /// Base en memoria, para pruebas.
    public static func enMemoria() throws -> BaseDeDatos {
        try BaseDeDatos(escritor: DatabaseQueue(), ruta: nil)
    }

    init(escritor: any DatabaseWriter, ruta: URL?) throws {
        self.escritor = escritor
        self.ruta = ruta
        try Migraciones.aplicar(a: escritor)
    }

    /// Estado de la base para el panel de diagnóstico (SIS-2).
    public func salud() throws -> SaludDeLaBase {
        try escritor.read { db in
            let opciones = try String.fetchAll(db, sql: "PRAGMA compile_options")
            return SaludDeLaBase(
                migraciones: try Migraciones.aplicadas(db),
                integra: try String.fetchOne(db, sql: "PRAGMA quick_check") == "ok",
                busquedaDeTexto: opciones.contains("ENABLE_FTS5"),
                versionDeSQLite: try String.fetchOne(db, sql: "SELECT sqlite_version()") ?? "")
        }
    }
}

public struct SaludDeLaBase: Sendable, Equatable {
    public let migraciones: [String]
    public let integra: Bool
    /// La búsqueda del portapapeles y de las reuniones necesita FTS5.
    public let busquedaDeTexto: Bool
    public let versionDeSQLite: String

    public var estaBien: Bool { integra && busquedaDeTexto && !migraciones.isEmpty }
}
