import SwiftUI

/// Dónde lleva liquid glass la isla. Lo decide Ajustes; aquí solo se pinta.
public struct VidrioDeIsla: Equatable, Sendable {
    /// Píldoras de pestañas, botones en píldora y accesos rápidos.
    public var pildoras: Bool
    /// Tarjetas del inicio y de los módulos.
    public var tarjetas: Bool
    /// La silueta completa de la isla abierta.
    public var fondo: Bool
    /// 0 transparente, 1 tintado. Igual que el control de Liquid Glass de macOS.
    public var tintado: Double

    public init(pildoras: Bool = false, tarjetas: Bool = false, fondo: Bool = false, tintado: Double = 0.5) {
        self.pildoras = pildoras
        self.tarjetas = tarjetas
        self.fondo = fondo
        self.tintado = min(max(tintado.isFinite ? tintado : 0.5, 0), 1)
    }

    public static let apagado = VidrioDeIsla()

    /// Por debajo de este punto el vidrio es el transparente de Apple (`Glass.clear`), que deja ver
    /// más el fondo; por encima, el regular, que se va cubriendo de color.
    static let umbralTransparente = 0.25

    /// Material de una píldora o tarjeta. `tinte` es un estado propio (por ejemplo, activo) y
    /// manda sobre el tintado general.
    public func material(tinte: Color? = nil) -> Glass {
        let base: Glass = tintado < Self.umbralTransparente ? .clear : .regular
        if let tinte { return base.tint(tinte) }
        let opacidad = max(0, tintado - Self.umbralTransparente) / (1 - Self.umbralTransparente) * 0.55
        return opacidad > 0.01 ? base.tint(Color.black.opacity(opacidad)) : base
    }

    /// Material de la isla completa con el color del tema del panel. En transparente el tema apenas
    /// tiñe; en tintado cubre casi todo.
    public func materialDeFondo(color: Color) -> Glass {
        let base: Glass = tintado < Self.umbralTransparente ? .clear : .regular
        return base.tint(color.opacity(0.2 + 0.7 * tintado))
    }

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
            content.glassEffect(vidrio.material(tinte: tinte), in: forma)
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
