import Foundation
import GRDB
import NotchyCore

/// Guarda y administra los archivos soltados en la bandeja (BND-1 a BND-3).
public struct RepositorioDeBandeja: Sendable {
    private let base: BaseDeDatos

    public init(_ base: BaseDeDatos) {
        self.base = base
    }

    public func agregar(_ elemento: ElementoDeBandeja) throws {
        try base.escritor.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tray_item (id, creado, nombre, ruta_original, ruta_copia, bytes)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        creado = excluded.creado,
                        nombre = excluded.nombre,
                        ruta_original = excluded.ruta_original,
                        ruta_copia = excluded.ruta_copia,
                        bytes = excluded.bytes
                    """,
                arguments: [
                    elemento.id,
                    elemento.creado.timeIntervalSince1970,
                    elemento.nombre,
                    elemento.rutaOriginal,
                    elemento.rutaCopia,
                    elemento.bytes,
                ])
        }
    }

    public func listar() throws -> [ElementoDeBandeja] {
        try base.escritor.read { db in
            try FilaDeBandeja.fetchAll(db, sql: "SELECT * FROM tray_item ORDER BY creado DESC")
                .map { $0.aDominio() }
        }
    }

    /// Quita un elemento de la bandeja y devuelve la ruta de su copia interna para borrarla sin tocar el original (BND-3).
    @discardableResult
    public func quitar(_ id: String) throws -> String? {
        try base.escritor.write { db in
            let rutaCopia = try String.fetchOne(
                db, sql: "SELECT ruta_copia FROM tray_item WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM tray_item WHERE id = ?", arguments: [id])
            return rutaCopia
        }
    }

    /// Vacía la bandeja y devuelve todas las rutas de copias internas para borrarlas sin tocar los originales (BND-3).
    @discardableResult
    public func vaciar() throws -> [String] {
        try base.escritor.write { db in
            let copias = try String.fetchAll(db, sql: "SELECT ruta_copia FROM tray_item")
            try db.execute(sql: "DELETE FROM tray_item")
            return copias
        }
    }
}

private struct FilaDeBandeja: FetchableRecord {
    let id: String
    let creado: Double
    let nombre: String
    let rutaOriginal: String
    let rutaCopia: String
    let bytes: Int

    init(row: Row) {
        id = row["id"]
        creado = row["creado"]
        nombre = row["nombre"]
        rutaOriginal = row["ruta_original"]
        rutaCopia = row["ruta_copia"]
        bytes = row["bytes"]
    }

    func aDominio() -> ElementoDeBandeja {
        ElementoDeBandeja(
            id: id,
            creado: Date(timeIntervalSince1970: creado),
            nombre: nombre,
            rutaOriginal: rutaOriginal,
            rutaCopia: rutaCopia,
            bytes: bytes
        )
    }
}
