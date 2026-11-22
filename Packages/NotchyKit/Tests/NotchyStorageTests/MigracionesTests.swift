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
        "v5-agente-historial",
        "v6-diarizacion-de-reuniones",
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

    @Test func v5PersisteListaYBorraConversacionesYMensajesDelAgente() throws {
        let repo = RepositorioDeAgente(try BaseDeDatos.enMemoria())
        let c1 = ConversacionDeAgente(
            id: "conv-1",
            sesionOpenCodeID: "ses-101",
            titulo: "Resumen de reuniones de hoy",
            modelo: "opencode/glm-5.3-flash-free",
            creado: Date(timeIntervalSince1970: 1_700_000_000),
            actualizado: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let mensajesC1 = [
            MensajeDeAgente(
                id: "m-1",
                rol: .usuario,
                texto: "Resumen de reuniones de hoy",
                fecha: Date(timeIntervalSince1970: 1_700_000_010)
            ),
            MensajeDeAgente(
                id: "m-2",
                rol: .asistente,
                texto: "Tienes Daily a las 10:00.",
                fecha: Date(timeIntervalSince1970: 1_700_000_020)
            ),
        ]
        try repo.guardarConversacionYMensajes(c1, mensajes: mensajesC1)

        let c2 = ConversacionDeAgente(
            id: "conv-2",
            sesionOpenCodeID: "ses-202",
            titulo: "Crear recordatorio",
            modelo: "apple/local",
            creado: Date(timeIntervalSince1970: 1_700_000_200),
            actualizado: Date(timeIntervalSince1970: 1_700_000_300)
        )
        try repo.guardarConversacionYMensajes(
            c2,
            mensajes: [
                MensajeDeAgente(
                    id: "m-3",
                    rol: .usuario,
                    texto: "Crear recordatorio",
                    fecha: Date(timeIntervalSince1970: 1_700_000_210)
                )
            ]
        )

        let conversaciones = try repo.listarConversaciones()
        #expect(conversaciones.map(\.id) == ["conv-2", "conv-1"])
        let recuperados = try repo.listarMensajes(conversacionID: "conv-1")
        #expect(recuperados.map(\.id) == ["m-1", "m-2"])
        #expect(recuperados.last?.texto == "Tienes Daily a las 10:00.")

        let sesionBorrada = try repo.borrarConversacion(id: "conv-1")
        #expect(sesionBorrada == "ses-101")
        #expect(try repo.listarMensajes(conversacionID: "conv-1").isEmpty)

        let sesionesRestantes = try repo.borrarTodo()
        #expect(sesionesRestantes == ["ses-202"])
        #expect(try repo.listarConversaciones().isEmpty)
    }
}
