import Foundation
import GRDB
import NotchyCore

/// Guarda y consulta las conversaciones y mensajes del agente en SQLite (AGT-8).
public struct RepositorioDeAgente: Sendable {
    private let base: BaseDeDatos

    public init(_ base: BaseDeDatos) {
        self.base = base
    }

    public func guardarConversacion(_ conversacion: ConversacionDeAgente) throws {
        try base.escritor.write { db in
            try db.execute(
                sql: """
                    INSERT INTO agent_conversation (id, sesion_opencode, titulo, modelo, creado, actualizado)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        sesion_opencode = excluded.sesion_opencode,
                        titulo = excluded.titulo,
                        modelo = excluded.modelo,
                        actualizado = excluded.actualizado
                    """,
                arguments: [
                    conversacion.id,
                    conversacion.sesionOpenCodeID,
                    conversacion.titulo,
                    conversacion.modelo,
                    conversacion.creado.timeIntervalSince1970,
                    conversacion.actualizado.timeIntervalSince1970,
                ]
            )
        }
    }

    public func guardarConversacionYMensajes(
        _ conversacion: ConversacionDeAgente,
        mensajes: [MensajeDeAgente]
    ) throws {
        try base.escritor.write { db in
            try db.execute(
                sql: """
                    INSERT INTO agent_conversation (id, sesion_opencode, titulo, modelo, creado, actualizado)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        sesion_opencode = excluded.sesion_opencode,
                        titulo = excluded.titulo,
                        modelo = excluded.modelo,
                        actualizado = excluded.actualizado
                    """,
                arguments: [
                    conversacion.id,
                    conversacion.sesionOpenCodeID,
                    conversacion.titulo,
                    conversacion.modelo,
                    conversacion.creado.timeIntervalSince1970,
                    conversacion.actualizado.timeIntervalSince1970,
                ]
            )
            try db.execute(
                sql: "DELETE FROM agent_message WHERE conversacion_id = ?",
                arguments: [conversacion.id]
            )
            for (indice, mensaje) in mensajes.enumerated() {
                let marcaTiempo = mensaje.fecha.timeIntervalSince1970 + Double(indice) * 0.0001
                try db.execute(
                    sql: """
                        INSERT INTO agent_message (id, conversacion_id, rol, texto, fecha)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        mensaje.id,
                        conversacion.id,
                        mensaje.rol.rawValue,
                        mensaje.texto,
                        marcaTiempo,
                    ]
                )
            }
        }
    }

    public func listarConversaciones() throws -> [ConversacionDeAgente] {
        try base.escritor.read { db in
            try FilaConversacionAgente.fetchAll(
                db,
                sql: "SELECT * FROM agent_conversation ORDER BY actualizado DESC, creado DESC"
            ).map { $0.aDominio() }
        }
    }

    public func obtenerConversacion(id: String) throws -> ConversacionDeAgente? {
        try base.escritor.read { db in
            try FilaConversacionAgente.fetchOne(
                db,
                sql: "SELECT * FROM agent_conversation WHERE id = ?",
                arguments: [id]
            )?.aDominio()
        }
    }

    public func listarMensajes(conversacionID: String) throws -> [MensajeDeAgente] {
        try base.escritor.read { db in
            try FilaMensajeAgente.fetchAll(
                db,
                sql: "SELECT * FROM agent_message WHERE conversacion_id = ? ORDER BY fecha ASC, rowid ASC",
                arguments: [conversacionID]
            ).map { $0.aDominio() }
        }
    }

    /// Borra una conversación y sus mensajes (en cascada) y devuelve su `sesionOpenCodeID` si tenía una.
    @discardableResult
    public func borrarConversacion(id: String) throws -> String? {
        try base.escritor.write { db in
            let sesion = try String.fetchOne(
                db,
                sql: "SELECT sesion_opencode FROM agent_conversation WHERE id = ?",
                arguments: [id]
            )
            try db.execute(
                sql: "DELETE FROM agent_conversation WHERE id = ?",
                arguments: [id]
            )
            return sesion
        }
    }

    /// Borra todas las conversaciones y mensajes y devuelve todos los `sesionOpenCodeID` registrados.
    @discardableResult
    public func borrarTodo() throws -> [String] {
        try base.escritor.write { db in
            let sesiones = try String.fetchAll(
                db,
                sql:
                    "SELECT sesion_opencode FROM agent_conversation WHERE sesion_opencode IS NOT NULL AND sesion_opencode != ''"
            )
            try db.execute(sql: "DELETE FROM agent_message")
            try db.execute(sql: "DELETE FROM agent_conversation")
            return sesiones
        }
    }
}

private struct FilaConversacionAgente: FetchableRecord {
    let id: String
    let sesionOpenCode: String?
    let titulo: String
    let modelo: String
    let creado: Double
    let actualizado: Double

    init(row: Row) {
        id = row["id"]
        sesionOpenCode = row["sesion_opencode"]
        titulo = row["titulo"]
        modelo = row["modelo"]
        creado = row["creado"]
        actualizado = row["actualizado"]
    }

    func aDominio() -> ConversacionDeAgente {
        ConversacionDeAgente(
            id: id,
            sesionOpenCodeID: sesionOpenCode,
            titulo: titulo,
            modelo: modelo,
            creado: Date(timeIntervalSince1970: creado),
            actualizado: Date(timeIntervalSince1970: actualizado)
        )
    }
}

private struct FilaMensajeAgente: FetchableRecord {
    let id: String
    let conversacionID: String
    let rol: String
    let texto: String
    let fecha: Double

    init(row: Row) {
        id = row["id"]
        conversacionID = row["conversacion_id"]
        rol = row["rol"]
        texto = row["texto"]
        fecha = row["fecha"]
    }

    func aDominio() -> MensajeDeAgente {
        MensajeDeAgente(
            id: id,
            rol: MensajeDeAgente.Rol(rawValue: rol) ?? .asistente,
            texto: texto,
            fecha: Date(timeIntervalSince1970: fecha)
        )
    }
}
