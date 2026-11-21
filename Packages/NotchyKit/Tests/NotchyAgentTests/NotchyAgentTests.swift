import Foundation
import MCP
import NotchyCore
import Testing

@testable import NotchyAgent

@MainActor
private final class HerramientasAgenteFalsas: PuertoDeHerramientasDelAgente {
    var lineasInbox: [String] = []
    var textosCopiados: [String] = []

    func agendaHoy() async -> [ItemAgendaHoyAgente] {
        [ItemAgendaHoyAgente(tipo: "evento", hora: "10:00", titulo: "Daily Notchy", ubicacion: "Sala 1")]
    }

    func portapapelesRecientes(limite: Int) -> [String] {
        Array(["uno", "dos"].prefix(limite))
    }

    func bandejaArchivos() -> [String] {
        ["captura.png", "nota.pdf"]
    }

    func reunionesRecientes(limite: Int) -> [ReunionRecienteAgente] {
        [
            ReunionRecienteAgente(
                titulo: "Revisión M6",
                fecha: "2026-11-21T10:00:00Z",
                duracionSegundos: 900,
                notaMarkdown: "# Resumen\nTodo bien"
            )
        ]
    }

    func ahoraSuena() -> AhoraSuenaAgente? {
        AhoraSuenaAgente(titulo: "Canción", artista: "Artista", reproduciendo: true)
    }

    func inboxAgregar(texto: String) throws -> String {
        lineasInbox.append(texto)
        return "Guardado"
    }

    func portapapelesCopiar(texto: String) throws -> String {
        textosCopiados.append(texto)
        return "Copiado"
    }
}

@Suite("Servidor MCP de Notchy (AGT-3, AGT-4, RNF-5)")
struct NotchyAgentTests {
    @Test func laCapaEnlaza() {
        #expect(NotchyAgentCapa.nombre == "NotchyAgent")
    }

    @Test @MainActor
    func peticionSinTokenRecibe401() async {
        let herramientas = HerramientasAgenteFalsas()
        let corredor = CorredorDePermisos()
        let servidor = ServidorMCPDeNotchy(
            herramientas: herramientas,
            corredorDePermisos: corredor,
            token: "tok-esperado-123"
        )

        let cuerpoInit = Data(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}"#
                .utf8
        )
        let sinAuth = HTTPRequest(
            method: "POST",
            headers: ["Content-Type": "application/json", "Host": "127.0.0.1"],
            body: cuerpoInit,
            path: "/mcp"
        )
        let respuestaSinAuth = await servidor.manejarPeticionHTTP(sinAuth)
        #expect(respuestaSinAuth.statusCode == 401)

        let tokenInvalido = HTTPRequest(
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "Host": "127.0.0.1",
                "Authorization": "Bearer otro-token",
            ],
            body: cuerpoInit,
            path: "/mcp"
        )
        let respuestaInvalida = await servidor.manejarPeticionHTTP(tokenInvalido)
        #expect(respuestaInvalida.statusCode == 401)
    }

    @Test @MainActor
    func toolsListExponeLasHerramientasDeNotchy() async throws {
        let herramientas = HerramientasAgenteFalsas()
        let corredor = CorredorDePermisos()
        let servidor = ServidorMCPDeNotchy(
            herramientas: herramientas,
            corredorDePermisos: corredor,
            token: "tok-lista-123"
        )

        let (transporteCliente, transporteServidor) = await InMemoryTransport.createConnectedPair()
        let instanciaServidor = try await servidor.conectar(transporte: transporteServidor)
        let cliente = Client(name: "PruebaNotchy", version: "1.0.0")
        _ = try await cliente.connect(transport: transporteCliente)

        let resultado = try await cliente.listTools()
        let nombres = Set(resultado.tools.map(\.name))
        #expect(
            nombres == [
                "agenda_hoy",
                "portapapeles_recientes",
                "bandeja_archivos",
                "reuniones_recientes",
                "ahora_suena",
                "inbox_agregar",
                "portapapeles_copiar",
            ]
        )

        await cliente.disconnect()
        await instanciaServidor.stop()
    }
}
