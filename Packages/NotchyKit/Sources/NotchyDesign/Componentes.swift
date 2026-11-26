import SwiftUI

/// Tarjeta del inicio y de los módulos: superficie tenue sobre el negro de la isla.
public struct Tarjeta<Contenido: View>: View {
    private let contenido: Contenido

    public init(@ViewBuilder _ contenido: () -> Contenido) {
        self.contenido = contenido()
    }

    public var body: some View {
        contenido
            .padding(.vertical, 8)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .superficieDeIsla(.tarjeta, en: RoundedRectangle(cornerRadius: Medidas.radioDeTarjeta))
    }
}

/// Tarjeta del estilo tarjetas: superficie tenue, borde fino y radio concéntrico con la isla.
public struct TarjetaConBorde<Contenido: View>: View {
    private let relleno: CGFloat
    private let contenido: Contenido
    @Environment(\.vidrioDeIsla) private var vidrio

    public init(relleno: CGFloat = 10, @ViewBuilder _ contenido: () -> Contenido) {
        self.relleno = relleno
        self.contenido = contenido()
    }

    public var body: some View {
        contenido
            .padding(relleno)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .superficieDeIsla(.tarjeta, en: RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna))
            .overlay(
                RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna)
                    .strokeBorder(vidrio.tarjetas ? Color.clear : Paleta.bordeSuave, lineWidth: 1)
            )
    }
}

/// Botón en píldora de 26 pt.
public struct EstiloDePildora: ButtonStyle {
    private let destacado: Bool

    public init(destacado: Bool = false) {
        self.destacado = destacado
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(destacado ? Paleta.fondo : Paleta.texto)
            .padding(.horizontal, 12)
            .frame(height: Medidas.altoDeBoton)
            .superficieDeIsla(.pildora, en: Capsule(), alta: true, tinte: destacado ? Paleta.texto : nil)
            .modifier(EfectoDePresion(presionado: configuration.isPressed))
    }
}

extension View {
    /// Texto principal: SF Pro de 13 pt en blanco.
    public func textoDeCuerpo() -> some View {
        font(.system(size: 13)).foregroundStyle(Paleta.texto)
    }

    /// Texto de apoyo: 11 pt al 64% de blanco.
    public func textoDeApoyo() -> some View {
        font(.system(size: 11)).foregroundStyle(Paleta.textoDeApoyo)
    }

    /// Rótulo de tarjeta: 11 pt, seminegrita, en el color del módulo.
    public func rotulo(_ color: Color) -> some View {
        font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
    }
}

/// Respuesta al presionar, como en macOS: se encoge un poco al instante y vuelve con un resorte
/// sin rebote. Solo escala y opacidad, que se componen en la GPU sin volver a dibujar.
/// Con "reducir movimiento" no escala: solo baja la opacidad.
struct EfectoDePresion: ViewModifier {
    let presionado: Bool
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento

    func body(content: Content) -> some View {
        content
            .scaleEffect(presionado && !reducirMovimiento ? 0.95 : 1)
            .opacity(presionado ? 0.82 : 1)
            .animation(Movimiento.presion(reducir: reducirMovimiento), value: presionado)
    }
}

/// Botón sin decoración que responde al presionar. Sustituye a `.plain` dentro de la isla.
public struct EstiloDePresion: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(EfectoDePresion(presionado: configuration.isPressed))
    }
}

extension ButtonStyle where Self == EstiloDePresion {
    public static var presion: EstiloDePresion { EstiloDePresion() }
}

/// Animaciones de la isla. Con "reducir movimiento" no hay resortes: un fundido de 150 ms.
/// Todas son críticamente amortiguadas (sin rebote): la isla no viene de un gesto con impulso.
public enum Movimiento {
    /// Al presionar: rápido para que se sienta inmediato.
    public static func presion(reducir: Bool) -> Animation {
        reducir ? .easeOut(duration: 0.1) : .spring(response: 0.22, dampingFraction: 1)
    }

    /// Cambiar de selección (pestaña activa, reordenar tarjetas).
    public static func seleccion(reducir: Bool) -> Animation {
        reducir ? .easeInOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.9)
    }

    public static func cambioDeEstado(reducir: Bool) -> Animation {
        reducir ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.82)
    }

    /// El contenido entra después de que crece la forma.
    public static func entradaDeContenido(reducir: Bool) -> Animation {
        reducir ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.2).delay(0.08)
    }
}
