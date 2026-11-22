import Foundation

/// Modelo de lenguaje que resume texto. La implementación real corre en la Mac (Apple Intelligence).
public protocol PuertoDeResumenDeTexto: Sendable {
    /// `false` si el modelo no está listo (Apple Intelligence apagado, descargando o Mac no compatible).
    func disponible() async -> Bool
    func resumir(_ texto: String, instrucciones: String) async throws -> String
}

/// Reglas puras para resumir reuniones largas, estructurar notas y exportar a Markdown (NOT-1, NOT-2).
public enum RedaccionDeResumen {
    /// Tamaño por trozo pensado para la ventana de contexto del modelo local (~4 k tokens).
    public static let maximoPorTrozo = 5000

    public static let instruccionesDeTrozo = """
        Resume en español un fragmento de la transcripción de una clase o reunión. \
        Devuelve de 3 a 7 viñetas cortas que empiecen con "- ": ideas principales, decisiones, \
        tareas (con responsable si se menciona) y fechas. No inventes nada que no esté en el texto. Sin introducción.
        """

    public static let instruccionesDeUnion = """
        Te paso notas o transcripciones de una misma clase o reunión, en orden. Únelas en español \
        con exactamente estas tres secciones en Markdown y en este orden:

        ## Resumen
        - viñetas cortas con las ideas principales sin repetir

        ## Decisiones
        - viñetas cortas con los acuerdos o decisiones tomadas (o "- Ninguna" si no hubo)

        ## Tareas
        - viñetas con formato "- [ ] tarea — responsable" si se menciona responsable, o "- [ ] tarea" si no (o "- Ninguna" si no hubo)

        No inventes nada que no esté en el texto. Sin introducción ni texto fuera de las tres secciones.
        """

    private enum SeccionDeNota {
        case resumen
        case decisiones
        case tareas
    }

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

    /// Resume por partes y une el resultado en una nota estructurada con las 3 secciones (NOT-1).
    public static func resumirPorPartes(
        _ texto: String,
        con modelo: any PuertoDeResumenDeTexto,
        maximo: Int = maximoPorTrozo
    ) async throws -> String {
        var partes = trozos(de: texto, maximo: maximo)
        guard !partes.isEmpty else { return "" }
        if partes.count == 1 {
            let salida = try await modelo.resumir(partes[0], instrucciones: instruccionesDeUnion)
            return normalizarNotaEstructurada(salida)
        }
        var resumenes: [String] = []
        for parte in partes {
            resumenes.append(try await modelo.resumir(parte, instrucciones: instruccionesDeTrozo))
        }
        var ronda = 0
        while resumenes.count > 1, ronda < 3 {
            ronda += 1
            partes = trozos(de: resumenes.joined(separator: "\n"), maximo: maximo)
            let instrucciones = partes.count == 1 ? instruccionesDeUnion : instruccionesDeTrozo
            resumenes = []
            for parte in partes {
                resumenes.append(try await modelo.resumir(parte, instrucciones: instrucciones))
            }
        }
        let unido = resumenes.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizarNotaEstructurada(unido)
    }

    /// Asegura que la nota tenga exactamente `## Resumen`, `## Decisiones` y `## Tareas`.
    /// Si el modelo no respetó las secciones, coloca todo el contenido bajo `## Resumen`.
    public static func normalizarNotaEstructurada(_ texto: String) -> String {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return "" }

        var lineasResumen: [String] = []
        var lineasDecisiones: [String] = []
        var lineasTareas: [String] = []
        var seccionActual: SeccionDeNota?
        var encontroEncabezado = false
        var sueltasAntesDeSeccion: [String] = []

        for sublinea in limpio.split(separator: "\n", omittingEmptySubsequences: false) {
            let linea = sublinea.trimmingCharacters(in: .whitespaces)
            if let detectada = detectarEncabezado(linea) {
                encontroEncabezado = true
                seccionActual = detectada
                continue
            }
            guard !linea.isEmpty else { continue }
            switch seccionActual {
            case .resumen:
                lineasResumen.append(normalizarVineta(linea, esTarea: false))
            case .decisiones:
                lineasDecisiones.append(normalizarVineta(linea, esTarea: false))
            case .tareas:
                lineasTareas.append(normalizarVineta(linea, esTarea: true))
            case nil:
                sueltasAntesDeSeccion.append(normalizarVineta(linea, esTarea: false))
            }
        }

        if !encontroEncabezado {
            lineasResumen = sueltasAntesDeSeccion
        } else if !sueltasAntesDeSeccion.isEmpty {
            lineasResumen.insert(contentsOf: sueltasAntesDeSeccion, at: 0)
        }

        let cuerpoResumen = lineasResumen.isEmpty ? ["- Ninguna"] : lineasResumen
        let cuerpoDecisiones = lineasDecisiones.isEmpty ? ["- Ninguna"] : lineasDecisiones
        let cuerpoTareas = lineasTareas.isEmpty ? ["- Ninguna"] : lineasTareas

        return [
            "## Resumen",
            cuerpoResumen.joined(separator: "\n"),
            "",
            "## Decisiones",
            cuerpoDecisiones.joined(separator: "\n"),
            "",
            "## Tareas",
            cuerpoTareas.joined(separator: "\n"),
        ].joined(separator: "\n")
    }

    private static func detectarEncabezado(_ linea: String) -> SeccionDeNota? {
        guard linea.hasPrefix("#") else { return nil }
        let sinAlm = linea.drop(while: { $0 == "#" || $0 == " " })
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_MX"))
        if sinAlm == "resumen" || sinAlm.hasPrefix("resumen:") {
            return .resumen
        }
        if sinAlm == "decisiones" || sinAlm == "acuerdos" || sinAlm.hasPrefix("decisiones:") {
            return .decisiones
        }
        if sinAlm == "tareas" || sinAlm == "pendientes" || sinAlm.hasPrefix("tareas:") {
            return .tareas
        }
        return nil
    }

    private static func normalizarVineta(_ linea: String, esTarea: Bool) -> String {
        var contenido = linea
        if contenido.hasPrefix("- ") {
            contenido = String(contenido.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else if contenido.hasPrefix("* ") || contenido.hasPrefix("• ") {
            contenido = String(contenido.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        let sinAcentos = contenido.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "es_MX")
        )
        if sinAcentos == "ninguna" || sinAcentos == "ninguno" || sinAcentos == "ninguna."
            || sinAcentos == "ninguno." || sinAcentos == "sin decisiones" || sinAcentos == "sin tareas"
        {
            return "- Ninguna"
        }
        if esTarea {
            if contenido.hasPrefix("[ ] ") || contenido.hasPrefix("[x] ") || contenido.hasPrefix("[X] ") {
                return "- \(contenido)"
            }
            return "- [ ] \(contenido)"
        }
        return "- \(contenido)"
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

    // MARK: - Exportación a Markdown compatible con Obsidian (NOT-2)

    /// Convierte un texto a slug en minúsculas con guiones, sin acentos ni ñ.
    public static func slugParaArchivo(_ texto: String) -> String {
        let plegado = texto.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "es_MX")
        )
        var piezas: [String] = []
        var actual = ""
        for escalar in plegado.unicodeScalars {
            let v = escalar.value
            let esLetra = (v >= 97 && v <= 122) || (v >= 65 && v <= 90)
            let esDigito = (v >= 48 && v <= 57)
            if esLetra || esDigito {
                actual.append(Character(escalar).lowercased())
            } else if !actual.isEmpty {
                piezas.append(actual)
                actual = ""
            }
        }
        if !actual.isEmpty {
            piezas.append(actual)
        }
        let unido = piezas.joined(separator: "-")
        return unido.isEmpty ? "reunion" : unido
    }

    /// Nombre sugerido para el archivo exportado: `YYYY-MM-DD-titulo-en-minusculas-con-guiones.md`.
    public static func nombreArchivoMarkdown(
        titulo: String,
        fecha: Date,
        zonaHoraria: TimeZone = .current
    ) -> String {
        let fechaStr = formatearFechaISO(fecha, zonaHoraria: zonaHoraria)
        let slug = slugParaArchivo(titulo)
        return "\(fechaStr)-\(slug).md"
    }

    /// Arma el archivo Markdown completo con frontmatter YAML compatible con Obsidian, `# Título`,
    /// la nota estructurada y `## Transcripción` con segmentos `**[mm:ss] Hablante:** texto` (NOT-2).
    public static func markdownExportable(
        reunion: ReunionGrabada,
        notaMarkdown: String?,
        segmentos: [SegmentoDeTranscripcion],
        nombresHablantes: [String: String] = [:],
        zonaHoraria: TimeZone = .current
    ) -> String {
        let tituloLimpio = reunion.titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        let tituloFinal = tituloLimpio.isEmpty ? "Reunión" : tituloLimpio
        let fechaStr = formatearFechaISO(reunion.inicio, zonaHoraria: zonaHoraria)
        let duracionMin = max(1, Int((reunion.duracionSegundos / 60).rounded()))
        let tituloYAML = valorYAMLEscapado(tituloFinal)

        let cuerpoNota: String
        if let nota = notaMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines), !nota.isEmpty {
            cuerpoNota = nota
        } else {
            cuerpoNota = [
                "## Resumen",
                "- Ninguna",
                "",
                "## Decisiones",
                "- Ninguna",
                "",
                "## Tareas",
                "- Ninguna",
            ].joined(separator: "\n")
        }

        var lineasTranscripcion: [String] = []
        for seg in segmentos {
            let texto = seg.texto.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !texto.isEmpty else { continue }
            let nombre = seg.etiquetaDeHablante(nombres: nombresHablantes)
            lineasTranscripcion.append("**[\(seg.marcaDeTiempoFormateada)] \(nombre):** \(texto)")
        }
        let bloqueTranscripcion =
            lineasTranscripcion.isEmpty
            ? "- Sin transcripción registrada."
            : lineasTranscripcion.joined(separator: "\n")

        return [
            "---",
            "tipo: reunion",
            "titulo: \(tituloYAML)",
            "fecha: \(fechaStr)",
            "duracion_min: \(duracionMin)",
            "tags: [reunion]",
            "---",
            "",
            "# \(tituloFinal)",
            "",
            cuerpoNota,
            "",
            "## Transcripción",
            bloqueTranscripcion,
            "",
        ].joined(separator: "\n")
    }

    /// Escapa una cadena en YAML con comillas dobles si contiene caracteres especiales de YAML.
    public static func valorYAMLEscapado(_ texto: String) -> String {
        let especiales = CharacterSet(charactersIn: ":#[]{}&*!|>'\"%@`?,\\-\n\r\t")
        let necesitaComillas =
            texto.isEmpty
            || texto.unicodeScalars.contains(where: { especiales.contains($0) })
            || texto.hasPrefix(" ")
            || texto.hasSuffix(" ")
        guard necesitaComillas else { return texto }
        let escapado =
            texto
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escapado)\""
    }

    private static func formatearFechaISO(_ fecha: Date, zonaHoraria: TimeZone) -> String {
        let formato = DateFormatter()
        formato.calendar = Calendar(identifier: .gregorian)
        formato.locale = Locale(identifier: "en_US_POSIX")
        formato.timeZone = zonaHoraria
        formato.dateFormat = "yyyy-MM-dd"
        return formato.string(from: fecha)
    }
}
