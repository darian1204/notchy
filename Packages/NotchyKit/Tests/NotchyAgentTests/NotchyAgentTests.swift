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

    var recordatoriosCreados: [(titulo: String, fecha: String?)] = []

    func recordatorioCrear(titulo: String, fechaISO8601: String?) async throws -> String {
        recordatoriosCreados.append((titulo, fechaISO8601))
        return "Recordatorio creado: \(titulo)"
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
                "recordatorio_crear",
            ]
        )

        await cliente.disconnect()
        await instanciaServidor.stop()
    }

    @Test @MainActor
    func recordatorioCrearYPermisoDeLecturasSensiblesEnMCP() async throws {
        let herramientas = HerramientasAgenteFalsas()
        let estado = EstadoDelAgente(modeloActivo: "opencode/glm-5.3-flash-free")
        let corredor = CorredorDePermisos(estadoDelAgente: estado)
        let servidor = ServidorMCPDeNotchy(
            herramientas: herramientas,
            corredorDePermisos: corredor,
            token: "tok-call-123"
        )

        let (transporteCliente, transporteServidor) = await InMemoryTransport.createConnectedPair()
        let instanciaServidor = try await servidor.conectar(transporte: transporteServidor)
        let cliente = Client(name: "PruebaNotchyCall", version: "1.0.0")
        _ = try await cliente.connect(transport: transporteCliente)

        let llamadaCrear = Task {
            try await cliente.callTool(
                name: "recordatorio_crear",
                arguments: [
                    "titulo": .string("Entregar práctica"),
                    "fecha": .string("2026-11-22T09:00:00Z"),
                ]
            )
        }
        for _ in 0..<20 where corredor.solicitudActual == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(corredor.solicitudActual?.herramienta == "recordatorio_crear")
        corredor.responder(.permitirUnaVez)
        let resCrear = try await llamadaCrear.value
        #expect(resCrear.isError != true)
        #expect(herramientas.recordatoriosCreados.count == 1)
        #expect(herramientas.recordatoriosCreados.first?.titulo == "Entregar práctica")

        // Con modelo Nube, portapapeles_recientes pide permiso:
        let llamadaClipNube = Task {
            try await cliente.callTool(
                name: "portapapeles_recientes",
                arguments: ["limite": .int(2)]
            )
        }
        for _ in 0..<20 where corredor.solicitudActual == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(corredor.solicitudActual?.herramienta == "portapapeles_recientes")
        corredor.responder(.negar)
        let resClipNegado = try await llamadaClipNube.value
        #expect(resClipNegado.isError == true)

        // Con modelo Local, portapapeles_recientes NO pide permiso:
        estado.actualizarModelo("apple/local")
        let resClipLocal = try await cliente.callTool(
            name: "portapapeles_recientes",
            arguments: ["limite": .int(2)]
        )
        #expect(resClipLocal.isError != true)
        #expect(corredor.solicitudActual == nil)

        await cliente.disconnect()
        await instanciaServidor.stop()
    }
}
