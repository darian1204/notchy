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
        var salud = try escritor.read { db in
            let opciones = try String.fetchAll(db, sql: "PRAGMA compile_options")
            let revision = try String.fetchAll(db, sql: "PRAGMA quick_check")
            return SaludDeLaBase(
                migraciones: try Migraciones.aplicadas(db),
                integra: revision == ["ok"],
                busquedaDeTexto: opciones.contains("ENABLE_FTS5"),
                versionDeSQLite: try String.fetchOne(db, sql: "SELECT sqlite_version()") ?? "",
                problemaDeIntegridad: revision.first(where: { $0 != "ok" }))
        }
        // Una lectura puede chocar con una escritura del portapapeles en curso (falso positivo).
        // Antes de alarmar se confirma con integrity_check desde el escritor, que ve la base completa.
        if !salud.integra {
            let confirmacion = try escritor.writeWithoutTransaction { db in
                try String.fetchAll(db, sql: "PRAGMA integrity_check")
            }
            salud.integra = confirmacion == ["ok"]
            salud.problemaDeIntegridad = salud.integra ? nil : confirmacion.first(where: { $0 != "ok" })
        }
        return salud
    }
}

public struct SaludDeLaBase: Sendable, Equatable {
    public let migraciones: [String]
    public internal(set) var integra: Bool
    /// La búsqueda del portapapeles y de las reuniones necesita FTS5.
    public let busquedaDeTexto: Bool
    public let versionDeSQLite: String
    /// Primer mensaje de SQLite cuando la revisión de integridad no da "ok".
    public internal(set) var problemaDeIntegridad: String?

    public init(
        migraciones: [String],
        integra: Bool,
        busquedaDeTexto: Bool,
        versionDeSQLite: String,
        problemaDeIntegridad: String? = nil
    ) {
        self.migraciones = migraciones
        self.integra = integra
        self.busquedaDeTexto = busquedaDeTexto
        self.versionDeSQLite = versionDeSQLite
        self.problemaDeIntegridad = problemaDeIntegridad
    }

    public var estaBien: Bool { integra && busquedaDeTexto && !migraciones.isEmpty }
}
