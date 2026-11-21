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
            .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: Medidas.radioDeTarjeta))
    }
}

/// Tarjeta del estilo tarjetas: superficie tenue, borde fino y radio concéntrico con la isla.
public struct TarjetaConBorde<Contenido: View>: View {
    private let relleno: CGFloat
    private let contenido: Contenido

    public init(relleno: CGFloat = 10, @ViewBuilder _ contenido: () -> Contenido) {
        self.relleno = relleno
        self.contenido = contenido()
    }

    public var body: some View {
        contenido
            .padding(relleno)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna))
            .overlay(
                RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna)
                    .strokeBorder(Paleta.bordeSuave, lineWidth: 1)
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
            .background(destacado ? Paleta.texto : Paleta.superficieAlta, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
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

/// Animaciones de la isla. Con "reducir movimiento" no hay resortes: un fundido de 150 ms.
public enum Movimiento {
    public static func cambioDeEstado(reducir: Bool) -> Animation {
        reducir ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.82)
    }

    /// El contenido entra después de que crece la forma.
    public static func entradaDeContenido(reducir: Bool) -> Animation {
        reducir ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.2).delay(0.08)
    }
}
