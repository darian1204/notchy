import Foundation

/// Modelo de lenguaje que resume texto. La implementación real corre en la Mac (Apple Intelligence).
public protocol PuertoDeResumenDeTexto: Sendable {
    /// `false` si el modelo no está listo (Apple Intelligence apagado, descargando o Mac no compatible).
    func disponible() async -> Bool
    func resumir(_ texto: String, instrucciones: String) async throws -> String
}

/// Reglas puras para resumir reuniones largas y redactar la nota que va al inbox de Obsidian.
public enum RedaccionDeResumen {
    /// Tamaño por trozo pensado para la ventana de contexto del modelo local (~4 k tokens).
    public static let maximoPorTrozo = 5000

    public static let instruccionesDeTrozo = """
        Resume en español un fragmento de la transcripción de una clase o reunión. \
        Devuelve de 3 a 7 viñetas cortas que empiecen con "- ": ideas principales, acuerdos, \
        tareas y fechas mencionadas. No inventes nada que no esté en el texto. Sin introducción.
        """

    public static let instruccionesDeUnion = """
        Te paso resúmenes parciales de una misma clase o reunión, en orden. Únelos en un solo \
        resumen en español de 4 a 8 viñetas que empiecen con "- ", sin repetir ideas. \
        Si hay tareas o fechas, ponlas al final. No inventes nada. Sin introducción.
        """

    /// Parte el texto por líneas en trozos de hasta `maximo` caracteres; una línea larga se corta sola.
    public static func trozos(de texto: String, maximo: Int = maximoPorTrozo) -> [String] {
        let limite = max(1, maximo)
        var resultado: [String] = []
        var actual = ""
        for linea in texto.split(separator: "\n", omittingEmptySubsequences: true) {
            var resto = Substring(linea)
            while resto.count > limite {
                if !actual.isEmpty {
                    resultado.append(actual)
                    actual = ""
                }
                let corte = resto.index(resto.startIndex, offsetBy: limite)
                resultado.append(String(resto[..<corte]))
                resto = resto[corte...]
            }
            if resto.isEmpty { continue }
            if actual.count + resto.count + 1 > limite, !actual.isEmpty {
                resultado.append(actual)
                actual = ""
            }
            actual += actual.isEmpty ? String(resto) : "\n" + resto
        }
        if !actual.isEmpty { resultado.append(actual) }
        return resultado
    }

    /// Resume por partes y une los resúmenes hasta que quepan en un solo trozo (máximo 3 rondas).
    public static func resumirPorPartes(
        _ texto: String,
        con modelo: any PuertoDeResumenDeTexto,
        maximo: Int = maximoPorTrozo
    ) async throws -> String {
        var partes = trozos(de: texto, maximo: maximo)
        guard !partes.isEmpty else { return "" }
        var resumenes: [String] = []
        for parte in partes {
            resumenes.append(try await modelo.resumir(parte, instrucciones: instruccionesDeTrozo))
        }
        var ronda = 0
        while resumenes.count > 1, ronda < 3 {
            ronda += 1
            partes = trozos(de: resumenes.joined(separator: "\n"), maximo: maximo)
            resumenes = []
            for parte in partes {
                resumenes.append(try await modelo.resumir(parte, instrucciones: instruccionesDeUnion))
            }
        }
        return resumenes.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bloque que se agrega tal cual al final de `00-inbox/inbox.md`.
    public static func notaDeInbox(titulo: String, inicio: Date, duracionMinutos: Int, resumen: String) -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "es_MX")
        formato.dateFormat = "yyyy-MM-dd HH:mm"
        let encabezado =
            "Resumen de reunión: \(titulo) (\(formato.string(from: inicio)), \(max(1, duracionMinutos)) min)"
        return encabezado + "\n" + resumen.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
