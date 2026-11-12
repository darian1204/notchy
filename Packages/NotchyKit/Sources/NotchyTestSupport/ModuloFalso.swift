import NotchyCore
import SwiftUI

/// Módulo sin vistas que cuenta cuántas veces lo arrancan y lo detienen.
@MainActor
public final class ModuloFalso: ModuloDeIsla {
    public let identidad: IdentidadDeModulo
    public let tamanoExpandido: CGSize
    public private(set) var arranques = 0
    public private(set) var detenciones = 0

    public init(_ id: String, lado: LadoDeLaBarra = .izquierda, tamano: CGSize = CGSize(width: 500, height: 200)) {
        identidad = IdentidadDeModulo(id: id, nombre: id.capitalized, icono: "circle", color: 0xFFFFFF, lado: lado)
        tamanoExpandido = tamano
    }

    public var vistaExpandida: AnyView { AnyView(EmptyView()) }

    public func arrancar() {
        arranques += 1
    }

    public func detener() {
        detenciones += 1
    }
}
