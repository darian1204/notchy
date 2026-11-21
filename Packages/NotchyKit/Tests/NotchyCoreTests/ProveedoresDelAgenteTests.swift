import Foundation
import Testing

@testable import NotchyCore

@Suite("Proveedores del agente (D-15)")
struct ProveedoresDelAgenteTests {
    @Test
    func filtraOpenAI() {
        let lista = [
            "openai/gpt-5.4-fast", "opencode/glm-5.3-flash-free", "openai/gpt-5.6-luna",
            "opencode/big-pickle", "opencode/glm-5.3-flash-free", "sin-proveedor",
        ]
        #expect(ProveedoresDelAgente.filtrar(lista) == ["opencode/glm-5.3-flash-free", "opencode/big-pickle"])
    }

    @Test
    func resuelveElegidoProhibido() {
        let disponibles = ["openai/gpt-5.4-fast", "opencode/glm-5.3-flash-free"]
        #expect(
            ProveedoresDelAgente.resolver(elegido: "openai/gpt-5.4-fast", disponibles: disponibles)
                == "opencode/glm-5.3-flash-free")
    }

    @Test
    func respetaElegido() {
        let disponibles = ["opencode/glm-5.3-flash-free", "opencode/big-pickle"]
        #expect(
            ProveedoresDelAgente.resolver(elegido: "opencode/big-pickle", disponibles: disponibles)
                == "opencode/big-pickle")
    }

    @Test
    func primeroPermitido() {
        let disponibles = ["openai/gpt-5.4-fast", "opencode/iceman-free"]
        #expect(ProveedoresDelAgente.resolver(elegido: nil, disponibles: disponibles) == "opencode/iceman-free")
    }

    @Test
    func respaldoPermitido() {
        #expect(ProveedoresDelAgente.modelosDeRespaldo.allSatisfy(ProveedoresDelAgente.estaPermitido))
        #expect(ProveedoresDelAgente.estaPermitido(ProveedoresDelAgente.modeloPorDefecto))
    }

    @Test
    func clasificaModelosLocalesYNube() {
        #expect(ProveedoresDelAgente.clasificar("apple/local") == .local)
        #expect(ProveedoresDelAgente.clasificar("apple/foundation-model") == .local)
        #expect(ProveedoresDelAgente.clasificar("local") == .local)
        #expect(ProveedoresDelAgente.clasificar("ollama/llama3.3") == .local)
        #expect(ProveedoresDelAgente.clasificar("lmstudio/qwen2.5") == .local)
        #expect(ProveedoresDelAgente.clasificar("opencode/glm-5.3-flash-free") == .nube)
        #expect(ProveedoresDelAgente.clasificar("opencode/big-pickle") == .nube)
        #expect(ProveedoresDelAgente.esModeloDeApple("apple/local"))
        #expect(ProveedoresDelAgente.nombreParaMostrar("apple/local") == "Apple (en la Mac)")
    }
}

private final class AlmacenMemoriaAgente: AlmacenDeAjustes, @unchecked Sendable {
    private var datos: [String: Data] = [:]
    func leer(_ clave: String) -> Data? { datos[clave] }
    func guardar(_ dato: Data?, en clave: String) { datos[clave] = dato }
}

@Suite("Corredor de permisos y config OpenCode (AGT-4, AGT-7)")
struct AgenteMCPCoreTests {
    @Test @MainActor
    func corredorSiempreRecordadoEnAjustes() async throws {
        let almacen = AlmacenMemoriaAgente()
        let ajustes = Ajustes(almacen: almacen)
        let corredor = CorredorDePermisos(ajustes: ajustes)

        var ejecuciones = 0
        let tareaPrimera = Task { @MainActor in
            try await corredor.ejecutarConPermiso(
                herramienta: "inbox_agregar",
                argumentos: ["texto": "nota 1"]
            ) {
                ejecuciones += 1
                return "ok"
            }
        }

        await Task.yield()
        #expect(corredor.solicitudActual?.herramienta == "inbox_agregar")
        corredor.responder(.siempre)
        let res1 = try await tareaPrimera.value
        #expect(res1 == "ok")
        #expect(ejecuciones == 1)
        #expect(ajustes.herramientasAgenteSiemprePermitidas.contains("inbox_agregar"))

        // La segunda llamada no pide permiso porque quedó recordado en Ajustes.
        let res2 = try await corredor.ejecutarConPermiso(
            herramienta: "inbox_agregar",
            argumentos: ["texto": "nota 2"]
        ) {
            ejecuciones += 1
            return "ok2"
        }
        #expect(res2 == "ok2")
        #expect(ejecuciones == 2)
        #expect(corredor.solicitudActual == nil)
    }

    @Test @MainActor
    func corredorNegarNoEjecutaYNotifica() async {
        let corredor = CorredorDePermisos()
        var negadas: [String] = []
        corredor.alDenegar = { solicitud in
            negadas.append(solicitud.herramienta)
        }

        var ejecutado = false
        let tarea = Task { @MainActor in
            try await corredor.ejecutarConPermiso(
                herramienta: "portapapeles_copiar",
                argumentos: ["texto": "secreto"]
            ) {
                ejecutado = true
                return "copiado"
            }
        }

        await Task.yield()
        #expect(corredor.solicitudActual?.herramienta == "portapapeles_copiar")
        corredor.responder(.negar)

        do {
            _ = try await tarea.value
            Issue.record("Debió lanzar ErrorDePermisoAgente.negadoPorElUsuario")
        } catch let error as ErrorDePermisoAgente {
            #expect(error == .negadoPorElUsuario)
            #expect(error.localizedDescription == "Negado por el usuario")
        } catch {
            Issue.record("Error inesperado: \(error)")
        }

        #expect(!ejecutado)
        #expect(negadas == ["portapapeles_copiar"])
    }

    @Test @MainActor
    func corredorTimeoutNiegaAutomaticamente() async {
        let corredor = CorredorDePermisos(
            tiempoLimite: .milliseconds(20),
            dormir: { try await Task.sleep(for: $0) }
        )
        var negadoPorTimeout = false
        corredor.alDenegar = { _ in
            negadoPorTimeout = true
        }

        var ejecutado = false
        do {
            _ = try await corredor.ejecutarConPermiso(
                herramienta: "inbox_agregar",
                argumentos: ["texto": "tarde"]
            ) {
                ejecutado = true
                return "ok"
            }
            Issue.record("Debió negar por timeout")
        } catch let error as ErrorDePermisoAgente {
            #expect(error == .negadoPorElUsuario)
        } catch {
            Issue.record("Error inesperado: \(error)")
        }

        #expect(!ejecutado)
        #expect(negadoPorTimeout)
        #expect(corredor.solicitudActual == nil)
    }

    @Test
    func generadorConfigReemplazaPuertoTokenYDesactivaToolsIntegradas() throws {
        let jsonTexto = try GeneradorConfigOpenCode.generarJSON(
            puerto: 54_321,
            token: "tok-prueba-987"
        )
        #expect(!jsonTexto.contains("{{"))
        #expect(jsonTexto.contains("http://127.0.0.1:54321/mcp"))
        #expect(jsonTexto.contains("tok-prueba-987"))

        let datos = try #require(jsonTexto.data(using: .utf8))
        let objeto = try #require(try JSONSerialization.jsonObject(with: datos) as? [String: Any])
        let tools = try #require(objeto["tools"] as? [String: Any])

        for herramienta in GeneradorConfigOpenCode.herramientasIntegradasDesactivadas {
            #expect(tools[herramienta] as? Bool == false)
        }
        #expect(tools["notchy_*"] as? Bool == true)

        let permisos = try #require(objeto["permission"] as? [String: Any])
        #expect(permisos["*"] as? String == "deny")
        #expect(permisos["notchy_*"] as? String == "allow")
    }

    @Test @MainActor
    func lecturasSensiblesPidenPermisoSoloCuandoElModeloEsNube() async throws {
        let estado = EstadoDelAgente(modeloActivo: "apple/local")
        let corredor = CorredorDePermisos(estadoDelAgente: estado)
        #expect(!estado.modeloEsNube)
        #expect(!corredor.requierePermisoDeLectura("portapapeles_recientes"))
        #expect(!corredor.requierePermisoDeLectura("reuniones_recientes"))

        let resultadoLocal = try await corredor.ejecutarLectura(
            herramienta: "portapapeles_recientes",
            argumentos: ["limite": "5"]
        ) {
            ["clip-local"]
        }
        #expect(resultadoLocal == ["clip-local"])
        #expect(corredor.solicitudActual == nil)

        estado.actualizarModelo("opencode/glm-5.3-flash-free")
        #expect(estado.modeloEsNube)
        #expect(corredor.requierePermisoDeLectura("portapapeles_recientes"))
        #expect(corredor.requierePermisoDeLectura("reuniones_recientes"))
        #expect(!corredor.requierePermisoDeLectura("agenda_hoy"))

        let tareaNube = Task { @MainActor in
            try await corredor.ejecutarLectura(
                herramienta: "reuniones_recientes",
                argumentos: ["limite": "3"]
            ) {
                ["reunion-nube"]
            }
        }
        await Task.yield()
        #expect(corredor.solicitudActual?.herramienta == "reuniones_recientes")
        corredor.responder(.permitirUnaVez)
        let resultadoNube = try await tareaNube.value
        #expect(resultadoNube == ["reunion-nube"])
    }
}
