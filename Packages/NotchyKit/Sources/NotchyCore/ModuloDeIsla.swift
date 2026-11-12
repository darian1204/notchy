import SwiftUI

/// De qué lado del notch va el ícono del módulo en la barra de la isla.
public enum LadoDeLaBarra: Sendable, Equatable {
    case izquierda, derecha
}

public struct IdentidadDeModulo: Sendable, Equatable, Identifiable {
    public let id: String
    public let nombre: String
    /// Nombre de un SF Symbol.
    public let icono: String
    /// Color del módulo como `0xRRGGBB`.
    public let color: UInt32
    public let lado: LadoDeLaBarra

    public init(id: String, nombre: String, icono: String, color: UInt32, lado: LadoDeLaBarra) {
        self.id = id
        self.nombre = nombre
        self.icono = icono
        self.color = color
        self.lado = lado
    }
}

/// Estado simple que lee el panel de diagnóstico.
public enum SaludDeModulo: Sendable, Equatable {
    case listo
    case faltaPermiso(String)
    case error(String)
}

/// Quién gana el estado compacto cuando varios lo piden (ISL-6). Gana el de mayor valor.
public enum PrioridadCompacta: Int, Sendable, Comparable, CaseIterable {
    case musica = 1
    case reunionProxima
    case grabando
    case agenteEscuchando

    public static func < (izquierda: Self, derecha: Self) -> Bool {
        izquierda.rawValue < derecha.rawValue
    }
}

public struct PeticionCompacta: Sendable, Equatable {
    public let modulo: String
    public let prioridad: PrioridadCompacta

    public init(modulo: String, prioridad: PrioridadCompacta) {
        self.modulo = modulo
        self.prioridad = prioridad
    }
}

/// Contrato de un módulo de función. La isla solo conoce esto: agregar un módulo no toca el resto.
/// Permisos, ajustes propios y herramientas del agente se suman al contrato cuando llegue el primer
/// módulo que los use.
@MainActor
public protocol ModuloDeIsla: AnyObject {
    var identidad: IdentidadDeModulo { get }
    /// Tamaño de la isla con este módulo abierto, incluida la franja de arriba a la altura del notch.
    var tamanoExpandido: CGSize { get }
    /// Contenido que va debajo de la franja del notch.
    var vistaExpandida: AnyView { get }
    var salud: SaludDeModulo { get }
    /// Empieza a trabajar. Lo llama el registro al activarse el módulo; no debe bloquear.
    func arrancar()
    /// Suelta todo lo que tomó. Lo llama el registro al apagarse el módulo o al salir.
    func detener()
}

extension ModuloDeIsla {
    public var salud: SaludDeModulo { .listo }
    public func arrancar() {}
    public func detener() {}
}

/// Identificadores de módulos que la isla trata de forma especial.
public enum ModulosBase {
    /// El que abre el hover.
    public static let inicio = "inicio"
}

/// La isla cambió de estado. `moduloAbierto` es `nil` cuando no está expandida.
public struct IslaCambioDeEstado: Evento, Equatable {
    public let moduloAbierto: String?

    public init(moduloAbierto: String?) {
        self.moduloAbierto = moduloAbierto
    }
}
