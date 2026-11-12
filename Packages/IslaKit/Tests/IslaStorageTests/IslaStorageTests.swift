import GRDB
import Testing

@testable import IslaStorage

@Suite struct IslaStorageTests {
    @Test func grdbAbreUnaBaseEnMemoria() throws {
        let base = try DatabaseQueue()
        let version = try base.read { try String.fetchOne($0, sql: "SELECT sqlite_version()") }
        #expect(version?.isEmpty == false)
    }

    /// La búsqueda del portapapeles y de las reuniones depende de esto.
    @Test func laBusquedaIgnoraAcentos() throws {
        let base = try DatabaseQueue()
        try base.write { db in
            try db.execute(
                sql: "CREATE VIRTUAL TABLE notas USING fts5(texto, tokenize='unicode61 remove_diacritics 2')")
            try db.execute(sql: "INSERT INTO notas(texto) VALUES ('Reunión de planeación')")
        }
        let encontradas = try base.read {
            try Int.fetchOne($0, sql: "SELECT count(*) FROM notas WHERE notas MATCH 'reunion'")
        }
        #expect(encontradas == 1)
    }
}
