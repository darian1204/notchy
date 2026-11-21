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
    /// Oreja izquierda cuando el módulo gana el estado compacto (`283 × 32`).
    var orejaIzquierdaCompacta: AnyView? { get }
    /// Oreja derecha cuando el módulo gana el estado compacto (`283 × 32`).
    var orejaDerechaCompacta: AnyView? { get }
    /// Vista completa cuando el módulo muestra un aviso temporal (`440 × 82`).
    var vistaDeAviso: AnyView? { get }
    var salud: SaludDeModulo { get }
    /// Número que se muestra junto a su pestaña en el estilo tarjetas (Flujo). `nil` = sin número.
    var insignia: Int? { get }
    /// Si tiene ícono en la barra del estilo clásico. Flujo solo existe como pestaña.
    var enBarraClasica: Bool { get }
    /// Empieza a trabajar. Lo llama el registro al activarse el módulo; no debe bloquear.
    func arrancar()
    /// Suelta todo lo que tomó. Lo llama el registro al apagarse el módulo o al salir.
    func detener()
}

extension ModuloDeIsla {
    public var orejaIzquierdaCompacta: AnyView? { nil }
    public var orejaDerechaCompacta: AnyView? { nil }
    public var vistaDeAviso: AnyView? { nil }
    public var salud: SaludDeModulo { .listo }
    public var insignia: Int? { nil }
    public var enBarraClasica: Bool { true }
    public func arrancar() {}
    public func detener() {}
}

/// Identificadores de módulos que la isla trata de forma especial.
public enum ModulosBase {
    /// El que abre el hover.
    public static let inicio = "inicio"
    /// Pestaña del estilo tarjetas con lo que está activo ahora.
    public static let flujo = "flujo"
    public static let agente = "agente"
}

/// La isla cambió de estado. `moduloAbierto` es `nil` cuando no está expandida.
public struct IslaCambioDeEstado: Evento, Equatable {
    public let moduloAbierto: String?

    public init(moduloAbierto: String?) {
        self.moduloAbierto = moduloAbierto
    }
}

/// Petición de un módulo para mostrarse o retirarse del estado compacto sin importar `NotchyIsland`.
public struct PeticionDeEstadoCompacto: Evento, Equatable {
    public let modulo: String
    public let prioridad: PrioridadCompacta?

    public init(modulo: String, prioridad: PrioridadCompacta?) {
        self.modulo = modulo
        self.prioridad = prioridad
    }
}

/// Petición de un módulo para abrir un aviso temporal de 6 s en la isla (AGD-4).
public struct PeticionDeAvisoDeIsla: Evento, Equatable {
    public let modulo: String

    public init(modulo: String) {
        self.modulo = modulo
    }
}
