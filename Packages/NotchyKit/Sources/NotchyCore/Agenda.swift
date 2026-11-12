import Foundation

/// Plataforma de videollamada reconocida en eventos del calendario (AGD-4).
public enum PlataformaDeLlamada: String, Codable, Sendable, Equatable, CaseIterable {
    case googleMeet
    case zoom
    case teams

    public var nombreVisible: String {
        switch self {
        case .googleMeet: "Google Meet"
        case .zoom: "Zoom"
        case .teams: "Teams"
        }
    }
}

/// Enlace de videollamada extraído de un evento (AGD-4).
public struct EnlaceDeLlamada: Codable, Sendable, Equatable {
    public let plataforma: PlataformaDeLlamada
    public let url: URL

    public init(plataforma: PlataformaDeLlamada, url: URL) {
        self.plataforma = plataforma
        self.url = url
    }

    /// Busca el primer enlace de Meet, Zoom o Teams dentro de textos (URL, ubicación o notas).
    public static func detectar(en textos: [String?]) -> EnlaceDeLlamada? {
        let patrones: [(PlataformaDeLlamada, String)] = [
            (.googleMeet, #"https?://meet\.google\.com/[A-Za-z0-9\-_?=&/]+"#),
            (.zoom, #"https?://(?:[A-Za-z0-9\-]+\.)?zoom\.us/(?:j|my|w)/[A-Za-z0-9\-_?=&/]+"#),
            (.teams, #"https?://teams\.(?:microsoft|live)\.com/l/meetup-join/[A-Za-z0-9\-_%?=&/.]+"#),
        ]
        for texto in textos.compactMap({ $0 }) where !texto.isEmpty {
            for (plataforma, patron) in patrones {
                if let rango = texto.range(of: patron, options: [.regularExpression, .caseInsensitive]),
                    let url = URL(string: String(texto[rango]))
                {
                    return EnlaceDeLlamada(plataforma: plataforma, url: url)
                }
            }
        }
        return nil
    }
}

/// Evento del Calendario del Mac (AGD-1, AGD-4).
public struct EventoDeCalendario: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let titulo: String
    public let inicio: Date
    public let fin: Date
    public let todoElDia: Bool
    public let calendario: String
    public let ubicacion: String?
    public let enlaceDeLlamada: EnlaceDeLlamada?

    public init(
        id: String,
        titulo: String,
        inicio: Date,
        fin: Date,
        todoElDia: Bool,
        calendario: String,
        ubicacion: String? = nil,
        enlaceDeLlamada: EnlaceDeLlamada? = nil
    ) {
        self.id = id
        self.titulo = titulo
        self.inicio = inicio
        self.fin = fin
        self.todoElDia = todoElDia
        self.calendario = calendario
        self.ubicacion = ubicacion
        self.enlaceDeLlamada = enlaceDeLlamada
    }
}

/// Pendiente de Recordatorios del Mac (AGD-3).
public struct PendienteDeRecordatorios: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let titulo: String
    public let lista: String
    public let vencimiento: Date?
    public let completado: Bool

    public init(
        id: String,
        titulo: String,
        lista: String,
        vencimiento: Date? = nil,
        completado: Bool = false
    ) {
        self.id = id
        self.titulo = titulo
        self.lista = lista
        self.vencimiento = vencimiento
        self.completado = completado
    }
}

/// Puntos que muestra cada día del mini calendario (AGD-2).
public struct PuntoDelDia: Sendable, Equatable {
    public var tieneEvento: Bool
    public var tienePendiente: Bool

    public init(tieneEvento: Bool = false, tienePendiente: Bool = false) {
        self.tieneEvento = tieneEvento
        self.tienePendiente = tienePendiente
    }
}

/// Puerto para leer eventos del Calendario del Mac (AGD-1).
@MainActor
public protocol PuertoDeCalendario: AnyObject {
    func estadoDePermiso() -> EstadoDePermiso
    func pedirPermiso() async -> EstadoDePermiso
    func eventos(desde: Date, hasta: Date) async throws -> [EventoDeCalendario]
}

/// Puerto para leer y completar pendientes de Recordatorios del Mac (AGD-3).
@MainActor
public protocol PuertoDeRecordatorios: AnyObject {
    func estadoDePermiso() -> EstadoDePermiso
    func pedirPermiso() async -> EstadoDePermiso
    func pendientesIncompletos() async throws -> [PendienteDeRecordatorios]
    func completar(id: String) async throws
}

/// Se publicó un aviso de reunión próxima con enlace de videollamada (AGD-4).
public struct ReunionProximaDetectada: Evento, Equatable {
    public let evento: EventoDeCalendario
    public let minutosRestantes: Int

    public init(evento: EventoDeCalendario, minutosRestantes: Int) {
        self.evento = evento
        self.minutosRestantes = minutosRestantes
    }
}
