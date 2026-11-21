import Foundation
import FoundationModels
import NotchyCore

/// Resume con el modelo de Apple Intelligence que corre en la Mac: sin red, sin costo y sin API key.
public struct AdaptadorDeResumenLocal: PuertoDeResumenDeTexto {
    public init() {}

    public func disponible() async -> Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func resumir(_ texto: String, instrucciones: String) async throws -> String {
        let sesion = LanguageModelSession(instructions: instrucciones)
        let respuesta = try await sesion.respond(to: texto)
        return respuesta.content
    }
}

/// Chat local con el modelo de Apple Intelligence (`LanguageModelSession`) para modo Local y respaldo sin red (AGT-5, AGT-6).
public struct AdaptadorDeChatLocal: PuertoDeChatLocal {
    public init() {}

    public func disponible() async -> Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func responder(mensajes: [MensajeDeAgente], instrucciones: String) async throws -> String {
        let sesion = LanguageModelSession(instructions: instrucciones)
        let prompt = Self.construirPrompt(de: mensajes)
        let respuesta = try await sesion.respond(to: prompt)
        return respuesta.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func construirPrompt(de mensajes: [MensajeDeAgente]) -> String {
        let relevantes =
            mensajes
            .filter { $0.rol == .usuario || $0.rol == .asistente }
            .suffix(10)
        guard let ultimo = relevantes.last else {
            return "Hola"
        }
        let previos = relevantes.dropLast()
        if previos.isEmpty {
            return ultimo.texto
        }
        let historial =
            previos
            .map { msg in
                let etiqueta = msg.rol == .usuario ? "Usuario" : "Asistente"
                return "\(etiqueta): \(msg.texto)"
            }
            .joined(separator: "\n")
        return """
            Historial reciente de la conversación:
            \(historial)

            Usuario: \(ultimo.texto)
            """
    }
}
