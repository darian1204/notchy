import Foundation
import NotchyCore

/// Habla con la API de Notion: agrega párrafos al final de una página y comprueba el acceso.
/// Solo se usa si el usuario elige Notion como destino del inbox.
public struct ClienteDeNotion: Sendable {
    public typealias Transporte = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let transporte: Transporte

    public init(transporte: @escaping Transporte = { try await URLSession.shared.data(for: $0) }) {
        self.transporte = transporte
    }

    /// Agrega `texto` al final de la página, un párrafo por línea.
    public func agregar(_ texto: String, aPagina pagina: String, token: String) async throws {
        let parrafos = Notion.parrafos(de: texto)
        guard !parrafos.isEmpty else { return }
        var inicio = 0
        while inicio < parrafos.count {
            let lote = Array(parrafos[inicio..<min(inicio + Notion.maximoDeBloques, parrafos.count)])
            do {
                try await enviar(Self.solicitudDeAgregar(lote, aPagina: pagina, token: token))
            } catch let error as NotchyError where inicio > 0 {
                // Lo anterior ya quedó en la página: avisarlo para no duplicarlo al reintentar.
                throw NotchyError.datos(
                    "Quedó a medias (\(inicio) de \(parrafos.count) párrafos en Notion). "
                        + (error.errorDescription ?? ""))
            }
            inicio += Notion.maximoDeBloques
        }
    }

    /// Comprueba que el token es válido y que la integración puede ver la página.
    /// No comprueba el permiso de insertar contenido: eso solo se sabe al escribir.
    public func comprobar(pagina: String, token: String) async throws {
        var componentes = URLComponents(
            url: Notion.urlBase.appending(path: "blocks").appending(path: pagina).appending(path: "children"),
            resolvingAgainstBaseURL: false)
        componentes?.queryItems = [URLQueryItem(name: "page_size", value: "1")]
        guard let url = componentes?.url else { throw NotchyError.datos("ID de página inválido") }
        var solicitud = Self.solicitudBase(url, token: token)
        solicitud.httpMethod = "GET"
        solicitud.setValue(nil, forHTTPHeaderField: "Content-Type")
        try await enviar(solicitud)
    }

    private func enviar(_ solicitud: URLRequest) async throws {
        let (datos, respuesta) = try await transporte(solicitud)
        guard let http = respuesta as? HTTPURLResponse else {
            throw NotchyError.datos("Notion no respondió")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NotchyError.datos(Self.mensaje(de: http.statusCode, datos: datos))
        }
    }

    static func solicitudBase(_ url: URL, token: String) -> URLRequest {
        var solicitud = URLRequest(url: url, timeoutInterval: 15)
        solicitud.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        solicitud.setValue(Notion.version, forHTTPHeaderField: "Notion-Version")
        solicitud.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return solicitud
    }

    static func solicitudDeAgregar(_ parrafos: [String], aPagina pagina: String, token: String) throws -> URLRequest {
        let url = Notion.urlBase.appending(path: "blocks").appending(path: pagina).appending(path: "children")
        var solicitud = solicitudBase(url, token: token)
        solicitud.httpMethod = "PATCH"
        solicitud.httpBody = try JSONEncoder().encode(CuerpoDeHijos(parrafos))
        return solicitud
    }

    static func mensaje(de codigo: Int, datos: Data) -> String {
        switch codigo {
        case 401: return "Notion rechazó el token. Revísalo en Ajustes."
        case 403: return "La integración de Notion no tiene permiso para insertar contenido en la página."
        case 404: return "La página no existe o no está compartida con tu integración de Notion."
        case 429: return "Notion pide esperar un momento. Intenta de nuevo."
        default:
            let detalle = (try? JSONDecoder().decode(ErrorDeNotion.self, from: datos))?.message
            return "Notion respondió \(codigo)" + (detalle.map { ": \($0)" } ?? "")
        }
    }
}

private struct ErrorDeNotion: Decodable {
    let message: String
}

/// `{"children": [{"object": "block", "type": "paragraph", "paragraph": {"rich_text": [...]}}]}`
struct CuerpoDeHijos: Encodable {
    struct Bloque: Encodable {
        let object = "block"
        let type = "paragraph"
        let paragraph: Parrafo
    }
    struct Parrafo: Encodable {
        let textoRico: [TextoRico]

        enum CodingKeys: String, CodingKey {
            case textoRico = "rich_text"
        }
    }
    struct TextoRico: Encodable {
        let type = "text"
        let text: Contenido
    }
    struct Contenido: Encodable {
        let content: String
    }

    let children: [Bloque]

    init(_ parrafos: [String]) {
        children = parrafos.map {
            Bloque(paragraph: Parrafo(textoRico: [TextoRico(text: Contenido(content: $0))]))
        }
    }
}
