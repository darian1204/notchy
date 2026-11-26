import Foundation
import NotchyCore
import NotchyTestSupport
import Testing

@testable import NotchyFeatures

/// Llavero falso en memoria.
private final class SecretosEnMemoria: PuertoDeSecretos, @unchecked Sendable {
    private var valores: [String: String] = [:]
    func leer(_ clave: String) -> String? { valores[clave] }
    func guardar(_ valor: String?, en clave: String) throws { valores[clave] = valor }
}

/// Guarda las peticiones y contesta con el código que se le diga.
private actor TransporteFalso {
    private(set) var peticiones: [URLRequest] = []
    private let codigo: Int

    init(codigo: Int = 200) { self.codigo = codigo }

    func responder(_ solicitud: URLRequest) -> (Data, URLResponse) {
        peticiones.append(solicitud)
        let respuesta = HTTPURLResponse(url: solicitud.url!, statusCode: codigo, httpVersion: nil, headerFields: nil)!
        return (Data("{}".utf8), respuesta)
    }
}

@MainActor
@Suite struct InboxNotionTests {
    private let pagina = "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d"

    @Test func laPeticionLlevaTokenVersionYParrafos() throws {
        let solicitud = try ClienteDeNotion.solicitudDeAgregar(
            ["hola", "adiós"], aPagina: "1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d", token: "secreto")
        #expect(solicitud.httpMethod == "PATCH")
        #expect(
            solicitud.url?.absoluteString
                == "https://api.notion.com/v1/blocks/1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d/children")
        #expect(solicitud.value(forHTTPHeaderField: "Authorization") == "Bearer secreto")
        #expect(solicitud.value(forHTTPHeaderField: "Notion-Version") == Notion.version)
        let cuerpo = try #require(solicitud.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: cuerpo) as? [String: Any])
        let hijos = try #require(json["children"] as? [[String: Any]])
        #expect(hijos.count == 2)
        #expect(hijos.first?["type"] as? String == "paragraph")
        let parrafo = try #require(hijos.first?["paragraph"] as? [String: Any])
        let texto = try #require((parrafo["rich_text"] as? [[String: Any]])?.first?["text"] as? [String: Any])
        #expect(texto["content"] as? String == "hola")
    }

    @Test func losErroresDeNotionSeExplican() {
        #expect(ClienteDeNotion.mensaje(de: 401, datos: Data()).contains("token"))
        #expect(ClienteDeNotion.mensaje(de: 404, datos: Data()).contains("compartida"))
        #expect(
            ClienteDeNotion.mensaje(de: 400, datos: Data(#"{"message":"mal"}"#.utf8)) == "Notion respondió 400: mal")
    }

    @Test func conNotionElegidoEnviaYNoTocaElArchivo() async throws {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.rutaVaultObsidian = carpeta.path
        ajustes.destinoDeInbox = .notion
        ajustes.paginaNotion = "https://www.notion.so/Inbox-\(pagina)"
        let secretos = SecretosEnMemoria()
        try secretos.guardar("secreto", en: ClavesDeSecretos.tokenNotion)
        let transporte = TransporteFalso()
        let gestor = GestorDeInboxObsidian(
            ajustes: ajustes, secretos: secretos,
            notion: ClienteDeNotion { await transporte.responder($0) })

        gestor.borrador = "comprar leche"
        #expect(gestor.guardarBorrador())
        #expect(gestor.borrador.isEmpty)
        for _ in 0..<100 where gestor.mensajeEstado != "Guardado en Notion" {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(gestor.mensajeEstado == "Guardado en Notion")
        #expect(gestor.lineasRecientes == ["comprar leche"])
        #expect(await transporte.peticiones.count == 1)
        #expect(!FileManager.default.fileExists(atPath: ajustes.urlNotaInboxObsidian.path))
    }

    @Test func siNotionFallaLaNotaVuelveAlCampo() async throws {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.destinoDeInbox = .notion
        ajustes.paginaNotion = pagina
        let secretos = SecretosEnMemoria()
        try secretos.guardar("malo", en: ClavesDeSecretos.tokenNotion)
        let transporte = TransporteFalso(codigo: 401)
        let gestor = GestorDeInboxObsidian(
            ajustes: ajustes, secretos: secretos,
            notion: ClienteDeNotion { await transporte.responder($0) })

        gestor.borrador = "idea"
        _ = gestor.guardarBorrador()
        for _ in 0..<100 where gestor.borrador.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(gestor.borrador == "idea")
        #expect(gestor.mensajeEstado?.contains("token") == true)
    }

    @Test func sinTokenNoEnviaYAvisa() async {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.destinoDeInbox = .notion
        ajustes.paginaNotion = pagina
        let gestor = GestorDeInboxObsidian(ajustes: ajustes, secretos: SecretosEnMemoria())
        await #expect(throws: NotchyError.datos("Falta el token de Notion en Ajustes")) {
            try await gestor.agregar("algo")
        }
    }

    @Test func elAgenteRecibeElErrorRealDeNotion() async throws {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.destinoDeInbox = .notion
        ajustes.paginaNotion = pagina
        let secretos = SecretosEnMemoria()
        try secretos.guardar("malo", en: ClavesDeSecretos.tokenNotion)
        let gestor = GestorDeInboxObsidian(
            ajustes: ajustes, secretos: secretos,
            notion: ClienteDeNotion { await TransporteFalso(codigo: 401).responder($0) })
        await #expect(throws: NotchyError.self) { try await gestor.agregar("resumen") }
    }

    @Test func variosEnviosSeguidosLleganTodos() async throws {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.destinoDeInbox = .notion
        ajustes.paginaNotion = pagina
        let secretos = SecretosEnMemoria()
        try secretos.guardar("secreto", en: ClavesDeSecretos.tokenNotion)
        let transporte = TransporteFalso()
        let gestor = GestorDeInboxObsidian(
            ajustes: ajustes, secretos: secretos,
            notion: ClienteDeNotion { await transporte.responder($0) })
        async let uno = gestor.agregar("uno")
        async let dos = gestor.agregar("dos")
        _ = try await (uno, dos)
        let cuerpos = await transporte.peticiones.compactMap {
            $0.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        }
        #expect(cuerpos.count == 2)
    }

    @Test func conObsidianEscribeEnElArchivo() async throws {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.rutaVaultObsidian = carpeta.path
        let gestor = GestorDeInboxObsidian(ajustes: ajustes)
        #expect(try await gestor.agregar("nota") == "Guardado en inbox.md")
        let texto = try String(contentsOf: ajustes.urlNotaInboxObsidian, encoding: .utf8)
        #expect(texto.hasSuffix("nota\n"))
    }
}
