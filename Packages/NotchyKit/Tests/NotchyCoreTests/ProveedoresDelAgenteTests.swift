import Testing

@testable import NotchyCore

@Suite("Proveedores del agente (D-15)")
struct ProveedoresDelAgenteTests {
    @Test("Quita los modelos de OpenAI y deja los de OpenCode sin repetir")
    func filtraOpenAI() {
        let lista = [
            "openai/gpt-5.4-fast", "opencode/glm-5.3-flash-free", "openai/gpt-5.6-luna",
            "opencode/big-pickle", "opencode/glm-5.3-flash-free", "sin-proveedor",
        ]
        #expect(ProveedoresDelAgente.filtrar(lista) == ["opencode/glm-5.3-flash-free", "opencode/big-pickle"])
    }

    @Test("Un modelo de OpenAI guardado se cambia por el de por defecto")
    func resuelveElegidoProhibido() {
        let disponibles = ["openai/gpt-5.4-fast", "opencode/glm-5.3-flash-free"]
        #expect(
            ProveedoresDelAgente.resolver(elegido: "openai/gpt-5.4-fast", disponibles: disponibles)
                == "opencode/glm-5.3-flash-free")
    }

    @Test("Respeta un modelo permitido y disponible")
    func respetaElegido() {
        let disponibles = ["opencode/glm-5.3-flash-free", "opencode/big-pickle"]
        #expect(
            ProveedoresDelAgente.resolver(elegido: "opencode/big-pickle", disponibles: disponibles)
                == "opencode/big-pickle")
    }

    @Test("Si el de por defecto no está en la lista, usa el primero permitido")
    func primeroPermitido() {
        let disponibles = ["openai/gpt-5.4-fast", "opencode/iceman-free"]
        #expect(ProveedoresDelAgente.resolver(elegido: nil, disponibles: disponibles) == "opencode/iceman-free")
    }

    @Test("Los modelos de respaldo y el de por defecto están permitidos")
    func respaldoPermitido() {
        #expect(ProveedoresDelAgente.modelosDeRespaldo.allSatisfy(ProveedoresDelAgente.estaPermitido))
        #expect(ProveedoresDelAgente.estaPermitido(ProveedoresDelAgente.modeloPorDefecto))
    }
}
