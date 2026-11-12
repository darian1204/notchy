import GRDB

/// Datos sueltos de la propia base (cuándo se creó, marcas de mantenimiento). No guarda preferencias.
public struct RepositorioDeMeta: Sendable {
    private let base: BaseDeDatos

    public init(_ base: BaseDeDatos) {
        self.base = base
    }

    public func leer(_ clave: String) throws -> String? {
        try base.escritor.read { db in
            try String.fetchOne(db, sql: "SELECT valor FROM meta WHERE clave = ?", arguments: [clave])
        }
    }

    public func guardar(_ valor: String, en clave: String) throws {
        try base.escritor.write { db in
            try db.execute(
                sql:
                    "INSERT INTO meta (clave, valor) VALUES (?, ?) ON CONFLICT(clave) DO UPDATE SET valor = excluded.valor",
                arguments: [clave, valor])
        }
    }
}
