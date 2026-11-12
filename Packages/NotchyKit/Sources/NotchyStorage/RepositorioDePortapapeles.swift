import Foundation
import GRDB
import NotchyCore

/// Guarda, busca (sin acentos con FTS5), fija y limpia el historial del portapapeles (CLP-1 a CLP-7).
public struct RepositorioDePortapapeles: Sendable {
    private let base: BaseDeDatos

    public init(_ base: BaseDeDatos) {
        self.base = base
    }

    /// Inserta el elemento o, si ya existe uno con la misma huella, actualiza su fecha y lo sube al principio
    /// conservando su estado de fijado. Devuelve el elemento resultante y, si se reemplazó un archivo anterior,
    /// la ruta del archivo descartado para que el llamador pueda borrarlo si es distinto.
    @discardableResult
    public func registrar(_ elemento: ElementoDePortapapeles) throws -> (
        guardado: ElementoDePortapapeles, rutaAnteriorDescartada: String?
    ) {
        try base.escritor.write { db in
            if let existente = try FilaDePortapapeles.fetchOne(
                db, sql: "SELECT * FROM clipboard_item WHERE huella = ? LIMIT 1", arguments: [elemento.huella]
            )?.aDominio() {
                let actualizado = ElementoDePortapapeles(
                    id: existente.id,
                    creado: elemento.creado,
                    tipo: elemento.tipo,
                    texto: elemento.texto,
                    rutaArchivo: elemento.rutaArchivo ?? existente.rutaArchivo,
                    huella: elemento.huella,
                    appOrigen: elemento.appOrigen ?? existente.appOrigen,
                    bundleOrigen: elemento.bundleOrigen ?? existente.bundleOrigen,
                    fijado: existente.fijado,
                    bytes: elemento.bytes
                )
                try db.execute(
                    sql: """
                        UPDATE clipboard_item
                        SET creado = ?, tipo = ?, texto = ?, ruta_archivo = ?, app_origen = ?, bundle_origen = ?, bytes = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        actualizado.creado.timeIntervalSince1970,
                        actualizado.tipo.rawValue,
                        actualizado.texto,
                        actualizado.rutaArchivo,
                        actualizado.appOrigen,
                        actualizado.bundleOrigen,
                        actualizado.bytes,
                        actualizado.id,
                    ])
                try db.execute(sql: "DELETE FROM clipboard_fts WHERE id = ?", arguments: [actualizado.id])
                try db.execute(
                    sql: "INSERT INTO clipboard_fts (id, texto, app_origen) VALUES (?, ?, ?)",
                    arguments: [actualizado.id, actualizado.texto, actualizado.appOrigen ?? ""])
                let descartada =
                    (existente.rutaArchivo != actualizado.rutaArchivo) ? existente.rutaArchivo : nil
                return (actualizado, descartada)
            }

            try db.execute(
                sql: """
                    INSERT INTO clipboard_item
                    (id, creado, tipo, texto, ruta_archivo, huella, app_origen, bundle_origen, fijado, bytes)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    elemento.id,
                    elemento.creado.timeIntervalSince1970,
                    elemento.tipo.rawValue,
                    elemento.texto,
                    elemento.rutaArchivo,
                    elemento.huella,
                    elemento.appOrigen,
                    elemento.bundleOrigen,
                    elemento.fijado,
                    elemento.bytes,
                ])
            try db.execute(
                sql: "INSERT INTO clipboard_fts (id, texto, app_origen) VALUES (?, ?, ?)",
                arguments: [elemento.id, elemento.texto, elemento.appOrigen ?? ""])
            return (elemento, nil)
        }
    }

    /// Lista o busca elementos sin acentos. Los fijados van primero, luego por fecha más reciente (CLP-3, CLP-6).
    public func listar(
        busqueda: String = "",
        tipo: TipoDePortapapeles? = nil,
        limite: Int = 100
    ) throws -> [ElementoDePortapapeles] {
        let consulta = Self.consultaFTS(para: busqueda)
        return try base.escritor.read { db in
            var sql = "SELECT c.* FROM clipboard_item c"
            var condiciones: [String] = []
            var argumentos: [any DatabaseValueConvertible] = []

            if let consulta {
                sql += " JOIN clipboard_fts f ON f.id = c.id"
                condiciones.append("clipboard_fts MATCH ?")
                argumentos.append(consulta)
            }
            if let tipo {
                condiciones.append("c.tipo = ?")
                argumentos.append(tipo.rawValue)
            }
            if !condiciones.isEmpty {
                sql += " WHERE " + condiciones.joined(separator: " AND ")
            }
            sql += " ORDER BY c.fijado DESC, c.creado DESC LIMIT ?"
            argumentos.append(limite)

            return try FilaDePortapapeles.fetchAll(db, sql: sql, arguments: StatementArguments(argumentos))
                .map { $0.aDominio() }
        }
    }

    public func total() throws -> Int {
        try base.escritor.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clipboard_item") ?? 0
        }
    }

    public func alternarFijado(_ id: String) throws -> Bool {
        try base.escritor.write { db in
            guard
                let actual = try Bool.fetchOne(
                    db, sql: "SELECT fijado FROM clipboard_item WHERE id = ?", arguments: [id])
            else { return false }
            let nuevo = !actual
            try db.execute(sql: "UPDATE clipboard_item SET fijado = ? WHERE id = ?", arguments: [nuevo, id])
            return nuevo
        }
    }

    /// Borra un elemento y devuelve su ruta de archivo (si tenía) para limpiar el disco (CLP-7).
    @discardableResult
    public func borrar(_ id: String) throws -> String? {
        try base.escritor.write { db in
            let ruta = try String.fetchOne(
                db, sql: "SELECT ruta_archivo FROM clipboard_item WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM clipboard_item WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM clipboard_fts WHERE id = ?", arguments: [id])
            return ruta
        }
    }

    /// Vacía todo el historial y devuelve las rutas de archivo para borrar en disco (CLP-5).
    @discardableResult
    public func borrarTodo() throws -> [String] {
        try base.escritor.write { db in
            let rutas = try String.fetchAll(
                db, sql: "SELECT ruta_archivo FROM clipboard_item WHERE ruta_archivo IS NOT NULL")
            try db.execute(sql: "DELETE FROM clipboard_item")
            try db.execute(sql: "DELETE FROM clipboard_fts")
            return rutas
        }
    }

    /// Aplica las reglas de retención por antigüedad y por cantidad máxima, sin borrar nunca los fijados (CLP-5, CLP-6).
    /// Devuelve las rutas de los archivos eliminados para limpiarlos del disco.
    @discardableResult
    public func aplicarRetencion(
        diasMaximos: Int,
        elementosMaximos: Int,
        ahora: Date = .now
    ) throws -> [String] {
        try base.escritor.write { db in
            let corte = ahora.addingTimeInterval(-Double(max(1, diasMaximos)) * 86_400).timeIntervalSince1970
            let vencidos = try FilaIdRuta.fetchAll(
                db,
                sql: "SELECT id, ruta_archivo FROM clipboard_item WHERE fijado = 0 AND creado < ?",
                arguments: [corte]
            )
            var idsABorrar = Set(vencidos.map(\.id))
            var rutas = vencidos.compactMap(\.rutaArchivo)

            let limite = max(1, elementosMaximos)
            let sobrantes = try FilaIdRuta.fetchAll(
                db,
                sql: """
                    SELECT id, ruta_archivo FROM clipboard_item
                    WHERE fijado = 0
                    ORDER BY creado DESC
                    LIMIT -1 OFFSET ?
                    """,
                arguments: [limite]
            )
            for fila in sobrantes where idsABorrar.insert(fila.id).inserted {
                if let ruta = fila.rutaArchivo {
                    rutas.append(ruta)
                }
            }

            for id in idsABorrar {
                try db.execute(sql: "DELETE FROM clipboard_item WHERE id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM clipboard_fts WHERE id = ?", arguments: [id])
            }
            return rutas
        }
    }

    static func consultaFTS(para texto: String) -> String? {
        let tokens =
            texto
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " AND ")
    }
}

private struct FilaIdRuta: FetchableRecord {
    let id: String
    let rutaArchivo: String?

    init(row: Row) {
        id = row["id"]
        rutaArchivo = row["ruta_archivo"]
    }
}

private struct FilaDePortapapeles: FetchableRecord {
    let id: String
    let creado: Double
    let tipo: String
    let texto: String
    let rutaArchivo: String?
    let huella: String
    let appOrigen: String?
    let bundleOrigen: String?
    let fijado: Bool
    let bytes: Int

    init(row: Row) {
        id = row["id"]
        creado = row["creado"]
        tipo = row["tipo"]
        texto = row["texto"]
        rutaArchivo = row["ruta_archivo"]
        huella = row["huella"]
        appOrigen = row["app_origen"]
        bundleOrigen = row["bundle_origen"]
        fijado = row["fijado"]
        bytes = row["bytes"]
    }

    func aDominio() -> ElementoDePortapapeles {
        ElementoDePortapapeles(
            id: id,
            creado: Date(timeIntervalSince1970: creado),
            tipo: TipoDePortapapeles(rawValue: tipo) ?? .texto,
            texto: texto,
            rutaArchivo: rutaArchivo,
            huella: huella,
            appOrigen: appOrigen,
            bundleOrigen: bundleOrigen,
            fijado: fijado,
            bytes: bytes
        )
    }
}
