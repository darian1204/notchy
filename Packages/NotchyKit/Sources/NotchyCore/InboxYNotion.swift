import Foundation

/// Guarda y lee secretos (tokens) fuera de los ajustes normales. En la app es el llavero de macOS.
public protocol PuertoDeSecretos: Sendable {
    func leer(_ clave: String) -> String?
    /// `nil` o vacío borra el secreto.
    func guardar(_ valor: String?, en clave: String) throws
    /// Si hay un secreto guardado, sin leerlo.
    func existe(_ clave: String) -> Bool
}

extension PuertoDeSecretos {
    public func existe(_ clave: String) -> Bool { !(leer(clave) ?? "").isEmpty }
}

public enum ClavesDeSecretos {
    public static let tokenNotion = "notion.token"
}

/// A dónde van las notas rápidas del Inicio, los resúmenes de reuniones y la herramienta del agente.
public enum DestinoDeInbox: String, Codable, Sendable, CaseIterable, Identifiable {
    case obsidian
    case notion

    public var id: String { rawValue }

    public var nombre: String {
        switch self {
        case .obsidian: "Obsidian"
        case .notion: "Notion"
        }
    }
}

/// Reglas de la API de Notion que no dependen de la red.
public enum Notion {
    public static let version = "2022-06-28"
    public static let urlBase = URL(string: "https://api.notion.com/v1")!
    /// Límite de caracteres de un texto enriquecido en un bloque.
    public static let maximoPorBloque = 2000
    /// Límite de bloques por petición.
    public static let maximoDeBloques = 100

    /// El ID de una página a partir de su enlace o de su ID, con o sin guiones. Devuelve el ID con guiones.
    public static func idDePagina(_ texto: String) -> String? {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return nil }
        // Enlace de vista previa (`…/<base>?p=<página>`): la página es la del parámetro `p`.
        if let componentes = URLComponents(string: limpio),
            let p = componentes.queryItems?.first(where: { $0.name == "p" })?.value,
            p != limpio, let id = idDePagina(p)
        {
            return id
        }
        // En un enlace el ID va al final del último segmento, antes de `?` o `#`.
        let sinConsulta = limpio.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? limpio
        let ultimo = sinConsulta.split(separator: "/").last.map(String.init) ?? sinConsulta
        let hex = ultimo.filter(\.isHexDigit)
        let candidato: String
        if ultimo.replacingOccurrences(of: "-", with: "").count == 32,
            ultimo.replacingOccurrences(of: "-", with: "").allSatisfy(\.isHexDigit)
        {
            candidato = ultimo.replacingOccurrences(of: "-", with: "")
        } else if hex.count >= 32 {
            candidato = String(ultimo.suffix(32))
        } else {
            return nil
        }
        guard candidato.count == 32, candidato.allSatisfy(\.isHexDigit) else { return nil }
        let c = Array(candidato.lowercased())
        return [c[0..<8], c[8..<12], c[12..<16], c[16..<20], c[20..<32]].map { String($0) }.joined(separator: "-")
    }

    /// Una nota en párrafos de Notion: una por línea no vacía, partidas en trozos de hasta 2000
    /// unidades UTF-16 (como cuenta Notion), sin cortar un carácter a la mitad.
    public static func parrafos(de texto: String) -> [String] {
        texto.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .flatMap(trozos)
    }

    static func trozos(_ linea: String) -> [String] {
        var resultado: [String] = []
        var actual = ""
        var largo = 0
        for caracter in linea {
            let unidades = caracter.utf16.count
            if largo + unidades > maximoPorBloque, !actual.isEmpty {
                resultado.append(actual)
                actual = ""
                largo = 0
            }
            actual.append(caracter)
            largo += unidades
        }
        if !actual.isEmpty { resultado.append(actual) }
        return resultado
    }

    /// Enlace para abrir la página en el navegador o en la app de Notion.
    public static func urlDePagina(_ id: String) -> URL? {
        URL(string: "https://www.notion.so/\(id.replacingOccurrences(of: "-", with: ""))")
    }
}
