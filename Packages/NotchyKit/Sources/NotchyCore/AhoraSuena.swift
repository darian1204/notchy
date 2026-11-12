import Foundation

/// Comandos de control multimedia compatibles con MediaRemote (MUS-1).
public enum ComandoDeReproduccion: Int, Sendable, Equatable, CaseIterable {
    case reproducir = 0
    case pausar = 1
    case alternar = 2
    case siguiente = 4
    case anterior = 5
}

/// Estado actual de reproducción multimedia en el Mac (MUS-1, D-18).
public struct EstadoDeAhoraSuena: Sendable, Equatable {
    public let titulo: String
    public let artista: String?
    public let album: String?
    public let appOrigen: String?
    public let bundleIdentifier: String?
    public let reproduciendo: Bool
    public let duracionSegundos: Double?
    public let transcurridoSegundos: Double?
    public let fechaDeMuestra: Date
    public let caratulaPNG: Data?
    public let usandoRespaldoAppleScript: Bool

    public init(
        titulo: String,
        artista: String? = nil,
        album: String? = nil,
        appOrigen: String? = nil,
        bundleIdentifier: String? = nil,
        reproduciendo: Bool,
        duracionSegundos: Double? = nil,
        transcurridoSegundos: Double? = nil,
        fechaDeMuestra: Date = .now,
        caratulaPNG: Data? = nil,
        usandoRespaldoAppleScript: Bool = false
    ) {
        self.titulo = titulo
        self.artista = artista
        self.album = album
        self.appOrigen = appOrigen
        self.bundleIdentifier = bundleIdentifier
        self.reproduciendo = reproduciendo
        self.duracionSegundos = duracionSegundos
        self.transcurridoSegundos = transcurridoSegundos
        self.fechaDeMuestra = fechaDeMuestra
        self.caratulaPNG = caratulaPNG
        self.usandoRespaldoAppleScript = usandoRespaldoAppleScript
    }

    /// Calcula el tiempo transcurrido estimado en `fecha` sin hacer polling constante.
    public func transcurridoActual(en fecha: Date) -> Double? {
        guard let base = transcurridoSegundos else { return nil }
        let avance = reproduciendo ? max(0, fecha.timeIntervalSince(fechaDeMuestra)) : 0
        let total = base + avance
        if let duracion = duracionSegundos, duracion > 0 {
            return min(total, duracion)
        }
        return total
    }

    /// Fracción de progreso entre 0 y 1 en `fecha`.
    public func fraccionDeProgreso(en fecha: Date) -> Double {
        guard let duracion = duracionSegundos, duracion > 0,
            let actual = transcurridoActual(en: fecha)
        else {
            return 0
        }
        return min(max(actual / duracion, 0), 1)
    }
}

/// Puerto de lectura y control de lo que suena en el Mac (D-18, MUS-1).
@MainActor
public protocol PuertoDeAhoraSuena: AnyObject {
    func iniciar(alCambiar: @escaping @MainActor (EstadoDeAhoraSuena?) -> Void)
    func detener()
    func enviar(_ comando: ComandoDeReproduccion)
    func probarAdaptador() async -> Bool
}

/// Evento publicado cuando cambia la canción o el estado de reproducción.
public struct CambioDeAhoraSuena: Evento, Equatable {
    public let estado: EstadoDeAhoraSuena?

    public init(estado: EstadoDeAhoraSuena?) {
        self.estado = estado
    }
}
