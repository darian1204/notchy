import Foundation
import Observation

// MARK: - Permisos de escritura del agente (AGT-4)

/// Decisión del usuario ante una herramienta de escritura del agente.
public enum DecisionDePermisoAgente: String, Sendable, Equatable, Codable {
    case negar
    case permitirUnaVez
    case siempre
}

/// Solicitud activa de permiso mostrada en la tarjeta del agente.
public struct SolicitudDePermisoAgente: Identifiable, Sendable, Equatable {
    public let id: String
    public let herramienta: String
    public let argumentos: [String: String]
    public let fecha: Date

    public init(
        id: String = UUID().uuidString,
        herramienta: String,
        argumentos: [String: String],
        fecha: Date = .now
    ) {
        self.id = id
        self.herramienta = herramienta
        self.argumentos = argumentos
        self.fecha = fecha
    }

    /// Resumen legible de los argumentos para mostrar en la tarjeta de permiso.
    public var resumenArgumentos: String {
        guard !argumentos.isEmpty else { return "Sin argumentos" }
        return
            argumentos
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
    }
}

/// Error devuelto cuando el usuario niega o expira una solicitud de permiso.
public enum ErrorDePermisoAgente: LocalizedError, Sendable, Equatable {
    case negadoPorElUsuario

    public var errorDescription: String? {
        switch self {
        case .negadoPorElUsuario:
            "Negado por el usuario"
        }
    }
}

/// Estado compartido del modelo activo del agente para coordinar permisos de lecturas sensibles (AGT-9).
@MainActor
@Observable
public final class EstadoDelAgente {
    public var modeloActivo: String {
        didSet {
            modeloEsNube = ProveedoresDelAgente.clasificar(modeloActivo) == .nube
        }
    }
    public var modeloEsNube: Bool

    public init(modeloActivo: String = ProveedoresDelAgente.modeloPorDefecto) {
        self.modeloActivo = modeloActivo
        self.modeloEsNube = ProveedoresDelAgente.clasificar(modeloActivo) == .nube
    }

    public func actualizarModelo(_ modelo: String) {
        self.modeloActivo = modelo
        self.modeloEsNube = ProveedoresDelAgente.clasificar(modelo) == .nube
    }
}

/// Coordina las solicitudes de permiso para herramientas de escritura y lecturas sensibles del agente (AGT-4, AGT-9).
///
/// Soporta tres opciones: Negar, Permitir (una vez) y Siempre (persistido en `Ajustes`).
/// Si no hay respuesta antes de `tiempoLimite` (60 s por defecto), se niega automáticamente.
@MainActor
@Observable
public final class CorredorDePermisos {
    /// Herramientas de lectura que contienen datos sensibles y piden permiso si el modelo activo es de Nube (AGT-9).
    public static let herramientasDeLecturaSensibles: Set<String> = [
        "portapapeles_recientes",
        "reuniones_recientes",
    ]

    public private(set) var solicitudActual: SolicitudDePermisoAgente?
    public let estadoDelAgente: EstadoDelAgente

    @ObservationIgnored public var alDenegar: (@MainActor (SolicitudDePermisoAgente) -> Void)?
    @ObservationIgnored private let ajustes: Ajustes?
    @ObservationIgnored private let tiempoLimite: Duration
    @ObservationIgnored private let dormir: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var siemprePermitidasEnMemoria: Set<String> = []
    @ObservationIgnored private var continuacionActual: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var tareaTimeout: Task<Void, Never>?

    public init(
        ajustes: Ajustes? = nil,
        estadoDelAgente: EstadoDelAgente? = nil,
        tiempoLimite: Duration = .seconds(60),
        dormir: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.ajustes = ajustes
        self.estadoDelAgente = estadoDelAgente ?? EstadoDelAgente()
        self.tiempoLimite = tiempoLimite
        self.dormir = dormir
    }

    public static func esLecturaSensible(_ herramienta: String) -> Bool {
        let base =
            herramienta.hasPrefix("notchy_")
            ? String(herramienta.dropFirst("notchy_".count))
            : herramienta
        return herramientasDeLecturaSensibles.contains(base)
    }

    /// Indica si una herramienta de lectura debe pasar por la tarjeta de permiso según el modelo activo (AGT-9).
    public func requierePermisoDeLectura(_ herramienta: String) -> Bool {
        Self.esLecturaSensible(herramienta) && estadoDelAgente.modeloEsNube
    }

    /// Ejecuta una lectura pidiendo permiso únicamente cuando la herramienta es sensible y el modelo activo es de Nube (AGT-9).
    public func ejecutarLectura<T: Sendable>(
        herramienta: String,
        argumentos: [String: String],
        accion: @MainActor () async throws -> T
    ) async throws -> T {
        if requierePermisoDeLectura(herramienta) {
            return try await ejecutarConPermiso(
                herramienta: herramienta,
                argumentos: argumentos,
                accion: accion
            )
        }
        return try await accion()
    }

    public func estaSiemprePermitida(_ herramienta: String) -> Bool {
        if siemprePermitidasEnMemoria.contains(herramienta) {
            return true
        }
        return ajustes?.herramientasAgenteSiemprePermitidas.contains(herramienta) ?? false
    }

    public func solicitarPermiso(
        herramienta: String,
        argumentos: [String: String]
    ) async -> Bool {
        if estaSiemprePermitida(herramienta) {
            return true
        }

        if continuacionActual != nil {
            responder(.negar)
        }

        let solicitud = SolicitudDePermisoAgente(
            herramienta: herramienta,
            argumentos: argumentos
        )
        solicitudActual = solicitud
        let idSolicitud = solicitud.id
        let limite = tiempoLimite
        let funcionDormir = dormir

        tareaTimeout = Task { [weak self] in
            do {
                try await funcionDormir(limite)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            if self.solicitudActual?.id == idSolicitud {
                self.responder(.negar)
            }
        }

        return await withCheckedContinuation { continuacion in
            self.continuacionActual = continuacion
        }
    }

    public func responder(_ decision: DecisionDePermisoAgente) {
        tareaTimeout?.cancel()
        tareaTimeout = nil

        guard let solicitud = solicitudActual else {
            if let continuacion = continuacionActual {
                continuacionActual = nil
                continuacion.resume(returning: false)
            }
            return
        }

        solicitudActual = nil
        let continuacion = continuacionActual
        continuacionActual = nil

        switch decision {
        case .negar:
            alDenegar?(solicitud)
            continuacion?.resume(returning: false)
        case .permitirUnaVez:
            continuacion?.resume(returning: true)
        case .siempre:
            siemprePermitidasEnMemoria.insert(solicitud.herramienta)
            ajustes?.herramientasAgenteSiemprePermitidas.insert(solicitud.herramienta)
            continuacion?.resume(returning: true)
        }
    }

    public func ejecutarConPermiso<T: Sendable>(
        herramienta: String,
        argumentos: [String: String],
        accion: @MainActor () async throws -> T
    ) async throws -> T {
        let permitido = await solicitarPermiso(herramienta: herramienta, argumentos: argumentos)
        guard permitido else {
            throw ErrorDePermisoAgente.negadoPorElUsuario
        }
        return try await accion()
    }
}

// MARK: - Puerto de herramientas del agente (AGT-3, AGT-4)

public struct ItemAgendaHoyAgente: Sendable, Equatable, Codable {
    public let tipo: String
    public let hora: String
    public let titulo: String
    public let ubicacion: String?

    public init(tipo: String, hora: String, titulo: String, ubicacion: String? = nil) {
        self.tipo = tipo
        self.hora = hora
        self.titulo = titulo
        self.ubicacion = ubicacion
    }
}

public struct ReunionRecienteAgente: Sendable, Equatable, Codable {
    public let titulo: String
    public let fecha: String
    public let duracionSegundos: Int
    public let notaMarkdown: String?

    public init(titulo: String, fecha: String, duracionSegundos: Int, notaMarkdown: String? = nil) {
        self.titulo = titulo
        self.fecha = fecha
        self.duracionSegundos = duracionSegundos
        self.notaMarkdown = notaMarkdown
    }
}

public struct AhoraSuenaAgente: Sendable, Equatable, Codable {
    public let titulo: String
    public let artista: String?
    public let album: String?
    public let appOrigen: String?
    public let reproduciendo: Bool

    public init(
        titulo: String,
        artista: String? = nil,
        album: String? = nil,
        appOrigen: String? = nil,
        reproduciendo: Bool
    ) {
        self.titulo = titulo
        self.artista = artista
        self.album = album
        self.appOrigen = appOrigen
        self.reproduciendo = reproduciendo
    }
}

/// Puerto mediante el cual el servidor MCP consulta y ejecuta acciones sobre los módulos de Notchy.
@MainActor
public protocol PuertoDeHerramientasDelAgente: AnyObject, Sendable {
    func agendaHoy() async -> [ItemAgendaHoyAgente]
    func portapapelesRecientes(limite: Int) -> [String]
    func bandejaArchivos() -> [String]
    func reunionesRecientes(limite: Int) -> [ReunionRecienteAgente]
    func ahoraSuena() -> AhoraSuenaAgente?
    func inboxAgregar(texto: String) throws -> String
    func portapapelesCopiar(texto: String) throws -> String
    func recordatorioCrear(titulo: String, fechaISO8601: String?) async throws -> String
}

extension PuertoDeHerramientasDelAgente {
    public func recordatorioCrear(titulo: String, fechaISO8601: String?) async throws -> String {
        "Recordatorio creado: \(titulo)"
    }
}

/// Puerto de ciclo de vida del servidor MCP local del agente.
@MainActor
public protocol PuertoServidorMCPAgente: AnyObject {
    func arrancar() async throws
    func detener() async
}

// MARK: - Generador de configuración de OpenCode (AGT-7)

public enum GeneradorConfigOpenCode {
    public static let herramientasIntegradasDesactivadas: [String] = [
        "bash", "edit", "write", "read", "glob", "grep",
        "list", "patch", "webfetch", "todowrite", "todoread", "task",
    ]

    public static let promptAgentePorDefecto =
        "Eres Notchy, el asistente del notch del usuario. Responde en español, en una o dos frases. Usa las herramientas de Notchy cuando hagan falta y no inventes datos de la agenda, del portapapeles ni de las reuniones.\n"

    public static let plantillaPorDefecto = """
        {
          "$schema": "https://opencode.ai/config.json",
          "autoupdate": false,
          "share": "disabled",
          "default_agent": "notchy",
          "enabled_providers": ["opencode"],
          "model": "opencode/glm-5.3-flash-free",
          "agent": {
            "notchy": {
              "description": "Agente de voz de Notchy",
              "mode": "primary",
              "prompt": "{file:./prompt-agente.md}"
            }
          },
          "mcp": {
            "notchy": {
              "type": "remote",
              "enabled": true,
              "url": "http://127.0.0.1:{{PUERTO}}/mcp",
              "headers": { "Authorization": "Bearer {{TOKEN}}" }
            }
          },
          "tools": {
            "bash": false,
            "edit": false,
            "write": false,
            "read": false,
            "glob": false,
            "grep": false,
            "list": false,
            "patch": false,
            "webfetch": false,
            "todowrite": false,
            "todoread": false,
            "task": false,
            "notchy_*": true
          },
          "permission": {
            "*": "deny",
            "notchy_*": "allow"
          }
        }
        """

    /// Función pura que rellena `{{PUERTO}}` y `{{TOKEN}}` y garantiza que todas las tools integradas estén en `false`.
    public static func generarJSON(
        plantilla: String = plantillaPorDefecto,
        puerto: UInt16,
        token: String
    ) throws -> String {
        let reemplazada =
            plantilla
            .replacingOccurrences(of: "{{PUERTO}}", with: String(puerto))
            .replacingOccurrences(of: "{{TOKEN}}", with: token)

        guard let datos = reemplazada.data(using: .utf8),
            var objeto = try JSONSerialization.jsonObject(with: datos) as? [String: Any]
        else {
            throw NotchyError.datos("La plantilla de OpenCode no es un JSON válido")
        }

        var tools = (objeto["tools"] as? [String: Any]) ?? [:]
        for nombre in herramientasIntegradasDesactivadas {
            tools[nombre] = false
        }
        tools["notchy_*"] = true
        objeto["tools"] = tools

        var permisos = (objeto["permission"] as? [String: Any]) ?? [:]
        permisos["*"] = "deny"
        permisos["notchy_*"] = "allow"
        objeto["permission"] = permisos

        let salidaDatos = try JSONSerialization.data(
            withJSONObject: objeto,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        guard let texto = String(data: salidaDatos, encoding: .utf8),
            !texto.contains("{{")
        else {
            throw NotchyError.datos("Quedaron marcadores sin reemplazar en opencode.json")
        }
        return texto
    }

    /// Escribe `opencode.json` (con permisos 0600) y `prompt-agente.md` en `Application Support` de Notchy.
    @discardableResult
    public static func escribirEnDisco(
        rutas: RutasDeDatos,
        puerto: UInt16,
        token: String,
        plantilla: String = plantillaPorDefecto,
        promptAgente: String = promptAgentePorDefecto
    ) throws -> URL {
        try FileManager.default.createDirectory(at: rutas.raiz, withIntermediateDirectories: true)
        try promptAgente.write(to: rutas.promptAgenteOpenCode, atomically: true, encoding: .utf8)

        let json = try generarJSON(plantilla: plantilla, puerto: puerto, token: token)
        let urlConfig = rutas.configOpenCode
        try json.write(to: urlConfig, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: urlConfig.path
        )
        return urlConfig
    }
}
