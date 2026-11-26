import SwiftUI

/// Dónde lleva liquid glass la isla. Lo decide Ajustes; aquí solo se pinta.
public struct VidrioDeIsla: Equatable, Sendable {
    /// Píldoras de pestañas, botones en píldora y accesos rápidos.
    public var pildoras: Bool
    /// Tarjetas del inicio y de los módulos.
    public var tarjetas: Bool
    /// La silueta completa de la isla abierta.
    public var fondo: Bool

    public init(pildoras: Bool = false, tarjetas: Bool = false, fondo: Bool = false) {
        self.pildoras = pildoras
        self.tarjetas = tarjetas
        self.fondo = fondo
    }

    public static let apagado = VidrioDeIsla()

    func aplica(a tipo: TipoDeSuperficie) -> Bool {
        switch tipo {
        case .pildora: pildoras
        case .tarjeta: tarjetas
        }
    }
}

/// Qué clase de superficie se pinta, para saber si lleva vidrio.
public enum TipoDeSuperficie: Sendable {
    case pildora, tarjeta
}

extension EnvironmentValues {
    @Entry public var vidrioDeIsla: VidrioDeIsla = .apagado
}

/// Superficie tenue de siempre, o liquid glass si el ajuste lo pide. Con "Reducir transparencia"
/// siempre es la superficie sólida (ISL-7).
struct SuperficieDeIsla<Forma: Shape>: ViewModifier {
    let tipo: TipoDeSuperficie
    let forma: Forma
    let alta: Bool
    let tinte: Color?
    @Environment(\.vidrioDeIsla) private var vidrio
    @Environment(\.accessibilityReduceTransparency) private var reducirTransparencia

    func body(content: Content) -> some View {
        if reducirTransparencia {
            content.background(tinte ?? (alta ? Paleta.superficieAltaSolida : Paleta.superficieSolida), in: forma)
        } else if vidrio.aplica(a: tipo) {
            content.glassEffect(tinte.map { Glass.regular.tint($0) } ?? .regular, in: forma)
        } else {
            content.background(tinte ?? (alta ? Paleta.superficieAlta : Paleta.superficie), in: forma)
        }
    }
}

extension View {
    /// Fondo de una tarjeta o píldora de la isla: superficie tenue o liquid glass según Ajustes.
    /// `tinte` sustituye el color de la superficie (por ejemplo, un estado activo).
    public func superficieDeIsla<Forma: Shape>(
        _ tipo: TipoDeSuperficie,
        en forma: Forma,
        alta: Bool = false,
        tinte: Color? = nil
    ) -> some View {
        modifier(SuperficieDeIsla(tipo: tipo, forma: forma, alta: alta, tinte: tinte))
    }
}
