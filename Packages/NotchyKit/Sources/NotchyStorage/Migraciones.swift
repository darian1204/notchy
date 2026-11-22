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
        migrador.registerMigration("v2-portapapeles-y-bandeja") { db in
            try db.create(table: "clipboard_item") { tabla in
                tabla.primaryKey("id", .text)
                tabla.column("creado", .double).notNull().indexed()
                tabla.column("tipo", .text).notNull().indexed()
                tabla.column("texto", .text).notNull()
                tabla.column("ruta_archivo", .text)
                tabla.column("huella", .text).notNull().indexed()
                tabla.column("app_origen", .text)
                tabla.column("bundle_origen", .text)
                tabla.column("fijado", .boolean).notNull().defaults(to: false)
                tabla.column("bytes", .integer).notNull().defaults(to: 0)
            }
            try db.execute(
                sql: """
                    CREATE VIRTUAL TABLE clipboard_fts USING fts5(
                        id UNINDEXED,
                        texto,
                        app_origen,
                        tokenize='unicode61 remove_diacritics 2'
                    )
                    """)
            try db.create(table: "tray_item") { tabla in
                tabla.primaryKey("id", .text)
                tabla.column("creado", .double).notNull().indexed()
                tabla.column("nombre", .text).notNull()
                tabla.column("ruta_original", .text).notNull()
                tabla.column("ruta_copia", .text).notNull()
                tabla.column("bytes", .integer).notNull().defaults(to: 0)
            }
        }
        migrador.registerMigration("v3-grabadora-y-reuniones") { db in
            try db.create(table: "voice_note") { tabla in
                tabla.primaryKey("id", .text)
                tabla.column("creado", .double).notNull().indexed()
                tabla.column("titulo", .text).notNull()
                tabla.column("duracion", .double).notNull().defaults(to: 0)
                tabla.column("ruta", .text).notNull()
                tabla.column("transcripcion", .text)
                tabla.column("idioma", .text).notNull().defaults(to: "es-MX")
            }
            try db.create(table: "meeting") { tabla in
                tabla.primaryKey("id", .text)
                tabla.column("titulo", .text).notNull()
                tabla.column("inicio", .double).notNull().indexed()
                tabla.column("fin", .double)
                tabla.column("estado", .text).notNull().indexed()
                tabla.column("idioma", .text).notNull().defaults(to: "es-MX")
                tabla.column("evento_calendario", .text)
                tabla.column("rutas_audio_mic", .text).notNull().defaults(to: "[]")
                tabla.column("rutas_audio_sistema", .text).notNull().defaults(to: "[]")
                tabla.column("desfase_ms", .double)
            }
            try db.create(table: "transcript_segment") { tabla in
                tabla.primaryKey("id", .text)
                tabla.column("reunion_id", .text).notNull().indexed()
                    .references("meeting", onDelete: .cascade)
                tabla.column("fuente", .text).notNull()
                tabla.column("inicio", .double).notNull()
                tabla.column("fin", .double).notNull()
                tabla.column("texto", .text).notNull()
                tabla.column("confianza", .double)
                tabla.column("es_final", .boolean).notNull().defaults(to: true)
            }
            try db.execute(
                sql: """
                    CREATE VIRTUAL TABLE transcript_fts USING fts5(
                        id UNINDEXED,
                        reunion_id UNINDEXED,
                        texto,
                        tokenize='unicode61 remove_diacritics 2'
                    )
                    """)
            try db.create(table: "glossary") { tabla in
                tabla.primaryKey("id", .text)
                tabla.column("mal_reconocido", .text).notNull().unique()
                tabla.column("correcto", .text).notNull()
                tabla.column("activo", .boolean).notNull().defaults(to: true)
            }
            for entrada in EntradaDeGlosario.porDefecto {
                try db.execute(
                    sql: """
                        INSERT INTO glossary (id, mal_reconocido, correcto, activo)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [entrada.id, entrada.malReconocido, entrada.correcto, entrada.activo]
                )
            }
        }
        migrador.registerMigration("v4-notas-de-reunion") { db in
            try db.create(table: "meeting_note") { tabla in
                tabla.primaryKey("meeting_id", .text)
                    .references("meeting", onDelete: .cascade)
                tabla.column("markdown", .text).notNull()
                tabla.column("generada_en", .double).notNull()
                tabla.column("editada_en", .double)
            }
        }
        migrador.registerMigration("v5-agente-historial") { db in
            try db.create(table: "agent_conversation") { tabla in
                tabla.primaryKey("id", .text)
                tabla.column("sesion_opencode", .text).indexed()
                tabla.column("titulo", .text).notNull()
                tabla.column("modelo", .text).notNull()
                tabla.column("creado", .double).notNull().indexed()
                tabla.column("actualizado", .double).notNull().indexed()
            }
            try db.create(table: "agent_message") { tabla in
                tabla.primaryKey("id", .text)
                tabla.column("conversacion_id", .text).notNull().indexed()
                    .references("agent_conversation", onDelete: .cascade)
                tabla.column("rol", .text).notNull()
                tabla.column("texto", .text).notNull()
                tabla.column("fecha", .double).notNull().indexed()
            }
        }
        migrador.registerMigration("v6-diarizacion-de-reuniones") { db in
            try db.alter(table: "transcript_segment") { tabla in
                tabla.add(column: "hablante", .text)
            }
            try db.create(table: "meeting_speaker") { tabla in
                tabla.column("reunion_id", .text).notNull().indexed()
                    .references("meeting", onDelete: .cascade)
                tabla.column("hablante_id", .text).notNull()
                tabla.column("nombre", .text).notNull()
                tabla.primaryKey(["reunion_id", "hablante_id"])
            }
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
