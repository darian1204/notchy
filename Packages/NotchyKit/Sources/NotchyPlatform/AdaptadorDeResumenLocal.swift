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
