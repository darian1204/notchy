import Foundation
import GRDB
import NotchyCore
import Testing

@testable import NotchyStorage

@Suite struct MigracionesTests {
    static let migracionesEsperadas = [
        "v1-meta",
        "v2-portapapeles-y-bandeja",
        "v3-grabadora-y-reuniones",
        "v4-notas-de-reunion",
    ]

    @Test func v1CreaMetaConLaFechaDeCreacion() throws {
        let base = try BaseDeDatos.enMemoria()
        let creada = try #require(try RepositorioDeMeta(base).leer("creada_en"))
        #expect(try Date(creada, strategy: .iso8601) <= Date())
        #expect(try base.salud().migraciones == Self.migracionesEsperadas)
    }

    @Test func reabrirNoRepiteMigracionesNiPierdeDatos() throws {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "notchy-pruebas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ruta = carpeta.appending(path: "notchy.sqlite")

        var creada: String?
        do {
            let base = try BaseDeDatos.abrir(en: ruta)
            creada = try RepositorioDeMeta(base).leer("creada_en")
            try RepositorioDeMeta(base).guardar("1", en: "marca")
            try base.escritor.close()
        }
        let base = try BaseDeDatos.abrir(en: ruta)
        #expect(try RepositorioDeMeta(base).leer("creada_en") == creada)
        #expect(try RepositorioDeMeta(base).leer("marca") == "1")
        #expect(try base.salud().migraciones == Self.migracionesEsperadas)
    }

    @Test func v3SemillaElGlosarioPorDefecto() throws {
        let repo = RepositorioDeGrabadoraYReuniones(try BaseDeDatos.enMemoria())
        let glosario = try repo.listarGlosario()
        #expect(glosario.contains { $0.malReconocido == "supavase" && $0.correcto == "Supabase" })
    }

    @Test func noTocaUnaBaseDeUnaVersionMasNueva() throws {
        let cola = try DatabaseQueue()
        var futuro = Migraciones.migrador
        futuro.registerMigration("v99-del-futuro") { db in
            try db.execute(sql: "CREATE TABLE futuro (id INTEGER PRIMARY KEY)")
        }
        try futuro.migrate(cola)

        #expect(throws: NotchyError.baseMasNueva(migracion: "v99-del-futuro")) {
            try Migraciones.aplicar(a: cola)
        }
    }

    @Test func guardarEnMetaReemplazaElValor() throws {
        let meta = RepositorioDeMeta(try BaseDeDatos.enMemoria())
        try meta.guardar("a", en: "clave")
        try meta.guardar("b", en: "clave")
        #expect(try meta.leer("clave") == "b")
    }

    @Test func laSaludReportaUnaBaseSana() throws {
        let salud = try BaseDeDatos.enMemoria().salud()
        #expect(salud.integra)
        #expect(salud.busquedaDeTexto)
        #expect(salud.estaBien)
        #expect(!salud.versionDeSQLite.isEmpty)
    }
}
