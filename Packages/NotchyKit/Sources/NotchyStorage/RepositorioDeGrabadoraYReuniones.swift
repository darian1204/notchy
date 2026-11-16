import Foundation
import GRDB
import NotchyCore

/// Almacén persistente para notas de voz, reuniones, segmentos de transcripción (con búsqueda FTS5 sin acentos),
/// recuperación tras caída y glosario de correcciones (GRB-1 a GRB-5, GRB-7, D-25, RNF-4).
public struct RepositorioDeGrabadoraYReuniones: Sendable {
    private let base: BaseDeDatos

    public init(_ base: BaseDeDatos) {
        self.base = base
    }

    // MARK: - Notas de voz (GRB-1)

    public func guardarNotaDeVoz(_ nota: NotaDeVoz) throws {
        try base.escritor.write { db in
            try db.execute(
                sql: """
                    INSERT INTO voice_note (id, creado, titulo, duracion, ruta, transcripcion, idioma)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        titulo = excluded.titulo,
                        duracion = excluded.duracion,
                        ruta = excluded.ruta,
                        transcripcion = excluded.transcripcion,
                        idioma = excluded.idioma
                    """,
                arguments: [
                    nota.id,
                    nota.creado.timeIntervalSince1970,
                    nota.titulo,
                    nota.duracionSegundos,
                    nota.rutaArchivo,
                    nota.transcripcion,
                    nota.idioma.rawValue,
                ]
            )
        }
    }

    public func listarNotasDeVoz(limite: Int = 50) throws -> [NotaDeVoz] {
        try base.escritor.read { db in
            try FilaNotaDeVoz.fetchAll(
                db,
                sql: "SELECT * FROM voice_note ORDER BY creado DESC LIMIT ?",
                arguments: [limite]
            ).map { $0.aDominio() }
        }
    }

    @discardableResult
    public func borrarNotaDeVoz(id: String) throws -> NotaDeVoz? {
        try base.escritor.write { db in
            let existente = try FilaNotaDeVoz.fetchOne(
                db,
                sql: "SELECT * FROM voice_note WHERE id = ? LIMIT 1",
                arguments: [id]
            )?.aDominio()
            try db.execute(sql: "DELETE FROM voice_note WHERE id = ?", arguments: [id])
            return existente
        }
    }

    // MARK: - Reuniones y segmentos incrementales (GRB-2 a GRB-4, RNF-4)

    public func guardarReunion(_ reunion: ReunionGrabada) throws {
        let jsonMic = Self.codificarListaJSON(reunion.rutasAudioMicrofono)
        let jsonSis = Self.codificarListaJSON(reunion.rutasAudioSistema)
        try base.escritor.write { db in
            try db.execute(
                sql: """
                    INSERT INTO meeting
                    (id, titulo, inicio, fin, estado, idioma, evento_calendario, rutas_audio_mic, rutas_audio_sistema, desfase_ms)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        titulo = excluded.titulo,
                        inicio = excluded.inicio,
                        fin = excluded.fin,
                        estado = excluded.estado,
                        idioma = excluded.idioma,
                        evento_calendario = excluded.evento_calendario,
                        rutas_audio_mic = excluded.rutas_audio_mic,
                        rutas_audio_sistema = excluded.rutas_audio_sistema,
                        desfase_ms = excluded.desfase_ms
                    """,
                arguments: [
                    reunion.id,
                    reunion.titulo,
                    reunion.inicio.timeIntervalSince1970,
                    reunion.fin?.timeIntervalSince1970,
                    reunion.estado.rawValue,
                    reunion.idioma.rawValue,
                    reunion.eventoCalendarioID,
                    jsonMic,
                    jsonSis,
                    reunion.desfaseInicialMs,
                ]
            )
        }
    }

    public func obtenerReunion(id: String) throws -> ReunionGrabada? {
        try base.escritor.read { db in
            try FilaReunion.fetchOne(
                db,
                sql: "SELECT * FROM meeting WHERE id = ? LIMIT 1",
                arguments: [id]
            )?.aDominio()
        }
    }

    public func listarReuniones(limite: Int = 50) throws -> [ReunionGrabada] {
        try base.escritor.read { db in
            try FilaReunion.fetchAll(
                db,
                sql: "SELECT * FROM meeting ORDER BY inicio DESC LIMIT ?",
                arguments: [limite]
            ).map { $0.aDominio() }
        }
    }

    public func guardarSegmento(_ segmento: SegmentoDeTranscripcion) throws {
        try base.escritor.write { db in
            try Self.insertarSegmento(segmento, en: db)
        }
    }

    /// Reemplaza los segmentos de una reunión al retranscribir sus archivos de audio (GRB-4).
    public func reemplazarSegmentos(
        reunionID: String,
        nuevos: [SegmentoDeTranscripcion]
    ) throws {
        try base.escritor.write { db in
            try db.execute(sql: "DELETE FROM transcript_fts WHERE reunion_id = ?", arguments: [reunionID])
            try db.execute(
                sql: "DELETE FROM transcript_segment WHERE reunion_id = ? AND fuente != ?",
                arguments: [reunionID, FuenteDeAudio.marca.rawValue]
            )
            for seg in nuevos {
                try Self.insertarSegmento(seg, en: db)
            }
        }
    }

    public func listarSegmentos(reunionID: String) throws -> [SegmentoDeTranscripcion] {
        try base.escritor.read { db in
            try FilaSegmento.fetchAll(
                db,
                sql: "SELECT * FROM transcript_segment WHERE reunion_id = ? ORDER BY inicio ASC, rowid ASC",
                arguments: [reunionID]
            ).map { $0.aDominio() }
        }
    }

    /// Busca segmentos de transcripción sin acentos usando `transcript_fts`.
    public func buscarSegmentos(
        consulta: String,
        reunionID: String? = nil,
        limite: Int = 20
    ) throws -> [SegmentoDeTranscripcion] {
        guard let fts = Self.consultaFTS(para: consulta) else { return [] }
        return try base.escritor.read { db in
            var sql = """
                SELECT s.* FROM transcript_segment s
                JOIN transcript_fts f ON f.id = s.id
                WHERE transcript_fts MATCH ?
                """
            var argumentos: [any DatabaseValueConvertible] = [fts]
            if let reunionID {
                sql += " AND s.reunion_id = ?"
                argumentos.append(reunionID)
            }
            sql += " ORDER BY s.inicio ASC LIMIT ?"
            argumentos.append(limite)
            return try FilaSegmento.fetchAll(db, sql: sql, arguments: StatementArguments(argumentos))
                .map { $0.aDominio() }
        }
    }

    /// Si la app se cerró a media reunión, marca las reuniones abiertas como `.recuperada`
    /// conservando todos sus segmentos y trozos de audio guardados hasta el último instante (GRB-4, RNF-4).
    @discardableResult
    public func recuperarReunionesIncompletas(en fechaRecuperacion: Date = .now) throws -> [ReunionGrabada] {
        try base.escritor.write { db in
            let abiertas = try FilaReunion.fetchAll(
                db,
                sql: "SELECT * FROM meeting WHERE estado IN (?, ?) ORDER BY inicio DESC",
                arguments: [EstadoDeReunion.enCurso.rawValue, EstadoDeReunion.pausada.rawValue]
            ).map { $0.aDominio() }

            var recuperadas: [ReunionGrabada] = []
            for var reunion in abiertas {
                let ultimoFinSegundos =
                    try Double.fetchOne(
                        db,
                        sql: "SELECT MAX(fin) FROM transcript_segment WHERE reunion_id = ?",
                        arguments: [reunion.id]
                    ) ?? 0
                let finEstimado = reunion.inicio.addingTimeInterval(max(1, ultimoFinSegundos))
                reunion.fin = min(fechaRecuperacion, max(reunion.inicio, finEstimado))
                reunion.estado = .recuperada
                try db.execute(
                    sql: "UPDATE meeting SET fin = ?, estado = ? WHERE id = ?",
                    arguments: [
                        reunion.fin?.timeIntervalSince1970,
                        reunion.estado.rawValue,
                        reunion.id,
                    ]
                )
                recuperadas.append(reunion)
            }
            return recuperadas
        }
    }

    /// Aplica la retención de audio de reuniones (D-25: 30 días por defecto).
    /// Conserva la reunión y su transcripción en la base, vacía las listas de rutas de audio
    /// y devuelve las rutas de los archivos que el llamador debe borrar de disco.
    public func aplicarRetencionDeAudio(dias: Int, ahora: Date = .now) throws -> [String] {
        let corte = ahora.addingTimeInterval(-Double(max(1, dias)) * 86_400).timeIntervalSince1970
        return try base.escritor.write { db in
            let viejas = try FilaReunion.fetchAll(
                db,
                sql: """
                    SELECT * FROM meeting
                    WHERE inicio < ? AND estado IN (?, ?)
                    AND (rutas_audio_mic != '[]' OR rutas_audio_sistema != '[]')
                    """,
                arguments: [
                    corte,
                    EstadoDeReunion.finalizada.rawValue,
                    EstadoDeReunion.recuperada.rawValue,
                ]
            ).map { $0.aDominio() }

            var rutasABorrar: [String] = []
            for reunion in viejas {
                rutasABorrar.append(contentsOf: reunion.rutasAudioMicrofono)
                rutasABorrar.append(contentsOf: reunion.rutasAudioSistema)
                try db.execute(
                    sql: "UPDATE meeting SET rutas_audio_mic = '[]', rutas_audio_sistema = '[]' WHERE id = ?",
                    arguments: [reunion.id]
                )
            }
            return rutasABorrar
        }
    }

    @discardableResult
    public func borrarReunion(id: String) throws -> ReunionGrabada? {
        try base.escritor.write { db in
            let existente = try FilaReunion.fetchOne(
                db,
                sql: "SELECT * FROM meeting WHERE id = ? LIMIT 1",
                arguments: [id]
            )?.aDominio()
            try db.execute(sql: "DELETE FROM transcript_fts WHERE reunion_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM transcript_segment WHERE reunion_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM meeting WHERE id = ?", arguments: [id])
            return existente
        }
    }

    // MARK: - Glosario de correcciones (GRB-5, D-09)

    public func listarGlosario() throws -> [EntradaDeGlosario] {
        try base.escritor.read { db in
            try FilaGlosario.fetchAll(
                db,
                sql: "SELECT * FROM glossary ORDER BY mal_reconocido COLLATE NOCASE ASC"
            ).map { $0.aDominio() }
        }
    }

    public func guardarEntradaGlosario(_ entrada: EntradaDeGlosario) throws {
        try base.escritor.write { db in
            try db.execute(
                sql: """
                    INSERT INTO glossary (id, mal_reconocido, correcto, activo)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        mal_reconocido = excluded.mal_reconocido,
                        correcto = excluded.correcto,
                        activo = excluded.activo
                    """,
                arguments: [entrada.id, entrada.malReconocido, entrada.correcto, entrada.activo]
            )
        }
    }

    public func borrarEntradaGlosario(id: String) throws {
        try base.escritor.write { db in
            try db.execute(sql: "DELETE FROM glossary WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Internos

    private static func insertarSegmento(_ segmento: SegmentoDeTranscripcion, en db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO transcript_segment
                (id, reunion_id, fuente, inicio, fin, texto, confianza, es_final)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    fuente = excluded.fuente,
                    inicio = excluded.inicio,
                    fin = excluded.fin,
                    texto = excluded.texto,
                    confianza = excluded.confianza,
                    es_final = excluded.es_final
                """,
            arguments: [
                segmento.id,
                segmento.reunionID,
                segmento.fuente.rawValue,
                segmento.inicioSegundos,
                segmento.finSegundos,
                segmento.texto,
                segmento.confianza,
                segmento.esFinal,
            ]
        )
        try db.execute(sql: "DELETE FROM transcript_fts WHERE id = ?", arguments: [segmento.id])
        if segmento.esFinal {
            try db.execute(
                sql: "INSERT INTO transcript_fts (id, reunion_id, texto) VALUES (?, ?, ?)",
                arguments: [segmento.id, segmento.reunionID, segmento.texto]
            )
        }
    }

    private static func consultaFTS(para texto: String) -> String? {
        let tokens =
            texto
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " AND ")
    }

    private static func codificarListaJSON(_ rutas: [String]) -> String {
        guard let datos = try? JSONEncoder().encode(rutas),
            let texto = String(data: datos, encoding: .utf8)
        else { return "[]" }
        return texto
    }

    fileprivate static func decodificarListaJSON(_ texto: String) -> [String] {
        guard let datos = texto.data(using: .utf8),
            let rutas = try? JSONDecoder().decode([String].self, from: datos)
        else { return [] }
        return rutas
    }
}

private struct FilaNotaDeVoz: FetchableRecord {
    let id: String
    let creado: Double
    let titulo: String
    let duracion: Double
    let ruta: String
    let transcripcion: String?
    let idioma: String

    init(row: Row) {
        id = row["id"]
        creado = row["creado"]
        titulo = row["titulo"]
        duracion = row["duracion"]
        ruta = row["ruta"]
        transcripcion = row["transcripcion"]
        idioma = row["idioma"]
    }

    func aDominio() -> NotaDeVoz {
        NotaDeVoz(
            id: id,
            creado: Date(timeIntervalSince1970: creado),
            titulo: titulo,
            duracionSegundos: duracion,
            rutaArchivo: ruta,
            transcripcion: transcripcion,
            idioma: IdiomaDeTranscripcion(rawValue: idioma) ?? .espanolMexico
        )
    }
}

private struct FilaReunion: FetchableRecord {
    let id: String
    let titulo: String
    let inicio: Double
    let fin: Double?
    let estado: String
    let idioma: String
    let eventoCalendario: String?
    let rutasMic: String
    let rutasSistema: String
    let desfaseMs: Double?

    init(row: Row) {
        id = row["id"]
        titulo = row["titulo"]
        inicio = row["inicio"]
        fin = row["fin"]
        estado = row["estado"]
        idioma = row["idioma"]
        eventoCalendario = row["evento_calendario"]
        rutasMic = row["rutas_audio_mic"]
        rutasSistema = row["rutas_audio_sistema"]
        desfaseMs = row["desfase_ms"]
    }

    func aDominio() -> ReunionGrabada {
        ReunionGrabada(
            id: id,
            titulo: titulo,
            inicio: Date(timeIntervalSince1970: inicio),
            fin: fin.map(Date.init(timeIntervalSince1970:)),
            estado: EstadoDeReunion(rawValue: estado) ?? .finalizada,
            idioma: IdiomaDeTranscripcion(rawValue: idioma) ?? .espanolMexico,
            eventoCalendarioID: eventoCalendario,
            rutasAudioMicrofono: RepositorioDeGrabadoraYReuniones.decodificarListaJSON(rutasMic),
            rutasAudioSistema: RepositorioDeGrabadoraYReuniones.decodificarListaJSON(rutasSistema),
            desfaseInicialMs: desfaseMs
        )
    }
}

private struct FilaSegmento: FetchableRecord {
    let id: String
    let reunionID: String
    let fuente: String
    let inicio: Double
    let fin: Double
    let texto: String
    let confianza: Double?
    let esFinal: Bool

    init(row: Row) {
        id = row["id"]
        reunionID = row["reunion_id"]
        fuente = row["fuente"]
        inicio = row["inicio"]
        fin = row["fin"]
        texto = row["texto"]
        confianza = row["confianza"]
        esFinal = row["es_final"]
    }

    func aDominio() -> SegmentoDeTranscripcion {
        SegmentoDeTranscripcion(
            id: id,
            reunionID: reunionID,
            fuente: FuenteDeAudio(rawValue: fuente) ?? .microfono,
            inicioSegundos: inicio,
            finSegundos: fin,
            texto: texto,
            confianza: confianza,
            esFinal: esFinal
        )
    }
}

private struct FilaGlosario: FetchableRecord {
    let id: String
    let malReconocido: String
    let correcto: String
    let activo: Bool

    init(row: Row) {
        id = row["id"]
        malReconocido = row["mal_reconocido"]
        correcto = row["correcto"]
        activo = row["activo"]
    }

    func aDominio() -> EntradaDeGlosario {
        EntradaDeGlosario(
            id: id,
            malReconocido: malReconocido,
            correcto: correcto,
            activo: activo
        )
    }
}
