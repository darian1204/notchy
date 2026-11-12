import Foundation
import GRDB
import NotchyCore

/// Migraciones de la base. Solo avanzan: una migración publicada no se edita, se agrega otra.
/// Cada una tiene su prueba en `MigracionesTests`.
enum Migraciones {
    static var migrador: DatabaseMigrator {
        var migrador = DatabaseMigrator()
        migrador.registerMigration("v1-meta") { db in
            try db.create(table: "meta") { tabla in
                tabla.primaryKey("clave", .text)
                tabla.column("valor", .text).notNull()
            }
            try db.execute(
                sql: "INSERT INTO meta (clave, valor) VALUES ('creada_en', ?)",
                arguments: [Date().ISO8601Format()])
        }
        return migrador
    }

    /// Aplica lo que falte. Si la base trae una migración desconocida (la abrió una versión más nueva
    /// de la app) no la toca y falla, para no dañar datos.
    static func aplicar(a escritor: any DatabaseWriter, con migrador: DatabaseMigrator = migrador) throws {
        let conocidas = Set(migrador.migrations)
        let aplicadas = try escritor.read(aplicadas)
        if let desconocida = aplicadas.first(where: { !conocidas.contains($0) }) {
            throw NotchyError.baseMasNueva(migracion: desconocida)
        }
        try migrador.migrate(escritor)
    }

    static func aplicadas(_ db: Database) throws -> [String] {
        guard try db.tableExists("grdb_migrations") else { return [] }
        return try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
    }
}
