import CoreGraphics
import NotchyDesign

/// Lo que la isla necesita saber de la pantalla. Coordenadas de AppKit: origen abajo a la izquierda.
public struct PantallaDeIsla: Equatable, Sendable {
    public var marco: CGRect
    /// Tamaño del notch; `nil` en pantallas sin notch.
    public var notch: CGSize?
    public var altoDeBarraDeMenus: CGFloat

    public init(marco: CGRect, notch: CGSize?, altoDeBarraDeMenus: CGFloat) {
        self.marco = marco
        self.notch = notch
        self.altoDeBarraDeMenus = altoDeBarraDeMenus
    }

    /// MacBook Air M4 de 13". Solo se usa hasta que el panel lee la pantalla real.
    public static let porDefecto = PantallaDeIsla(
        marco: CGRect(x: 0, y: 0, width: 1470, height: 956), notch: Medidas.notch, altoDeBarraDeMenus: 32)
}

/// Dónde va la isla y cuánto mide en cada estado. Cálculo puro, sin ventanas.
public struct GeometriaDeIsla: Equatable, Sendable {
    public var pantalla: PantallaDeIsla

    public init(pantalla: PantallaDeIsla = .porDefecto) {
        self.pantalla = pantalla
    }

    public var tieneNotch: Bool { pantalla.notch != nil }

    /// Con notch, el notch mismo. Sin notch, la píldora flotante.
    public var tamanoDeReposo: CGSize { pantalla.notch ?? Medidas.pildora }

    /// Borde superior de la isla: el de la pantalla con notch; debajo de la barra de menús sin notch.
    public var techo: CGFloat {
        tieneNotch
            ? pantalla.marco.maxY
            : pantalla.marco.maxY - pantalla.altoDeBarraDeMenus - Medidas.separacionDePildora
    }

    /// Tamaño del cuerpo de la isla, sin contar los hombros.
    /// `anchoDeOreja` es el de cada lado en compacto; cada actividad trae el suyo.
    public func tamano(
        de estado: EstadoDeIsla,
        expandido: CGSize?,
        anchoDeOreja: CGFloat = Medidas.orejaCompacta
    ) -> CGSize {
        let reposo = tamanoDeReposo
        switch estado {
        case .reposo:
            return reposo
        case .compacto:
            // Las orejas se suman al notch real. La píldora crece igual para que quepan.
            let base = tieneNotch ? reposo : CGSize(width: Medidas.notch.width, height: reposo.height)
            let ancho = max(base.width + 2 * anchoDeOreja, tieneNotch ? 0 : reposo.width)
            return CGSize(width: ancho, height: reposo.height)
        case .aviso:
            return CGSize(width: Medidas.aviso.width, height: max(Medidas.aviso.height, reposo.height))
        case .expandido:
            return expandido ?? Medidas.inicio
        }
    }

    /// En estilo tarjetas todo se abre al mismo ancho y suma la fila de puntos bajo el notch.
    public func tamanoEnTarjetas(expandido: CGSize?) -> CGSize {
        let base = expandido ?? Medidas.inicioTarjetas
        return CGSize(
            width: max(Medidas.anchoTarjetas, base.width),
            height: min(base.height + Medidas.altoDePuntos, Medidas.panel.height)
        )
    }

    /// Marco del panel fijo (D-04): siempre del tamaño mayor, centrado y pegado al techo.
    public var marcoDelPanel: CGRect {
        zona(Medidas.panel)
    }

    /// Rectángulo en pantalla de una isla de ese tamaño.
    public func zona(_ tamano: CGSize) -> CGRect {
        CGRect(
            x: pantalla.marco.midX - tamano.width / 2, y: techo - tamano.height, width: tamano.width,
            height: tamano.height)
    }

    /// Burbuja de la segunda actividad: un círculo a la derecha del cuerpo de la isla, fuera de los
    /// hombros, a la altura del notch.
    public func zonaDeBurbuja(cuerpo tamano: CGSize) -> CGRect {
        let cuerpo = zona(tamano)
        let lado = tamanoDeReposo.height
        let hombro = tieneNotch ? Medidas.hombro : 0
        return CGRect(
            x: cuerpo.maxX + hombro + Medidas.separacionDeBurbuja, y: techo - lado, width: lado, height: lado)
    }

    /// Zona que cuenta como "cursor dentro". En reposo se agranda un poco para que el notch sea fácil de tocar.
    public func zonaDeCursor(estado: EstadoDeIsla, tamano: CGSize) -> CGRect {
        estado == .reposo ? zona(tamano).insetBy(dx: -6, dy: -2) : zona(tamano)
    }

    /// `CGRect.contains` deja fuera el borde de arriba, y el cursor pegado al borde superior de la
    /// pantalla está justo ahí. Aquí los bordes cuentan (hallazgo de S2).
    public static func contiene(_ zona: CGRect, _ punto: CGPoint) -> Bool {
        punto.x >= zona.minX && punto.x <= zona.maxX && punto.y >= zona.minY && punto.y <= zona.maxY + 1
    }
}
