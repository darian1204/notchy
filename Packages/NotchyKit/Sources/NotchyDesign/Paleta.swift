import SwiftUI

/// Colores de la isla. Negro puro para fundirse con el notch; el color solo aparece en íconos y estados vivos.
public enum Paleta {
    public static let fondo = Color.black
    public static let texto = Color.white
    /// Texto de apoyo: 64% de blanco (≈ 7.8:1 sobre negro). El texto esencial nunca baja de aquí.
    public static let textoDeApoyo = Color.white.opacity(0.64)
    /// Solo decorativo: 40% de blanco (≈ 3.4:1). No usar para texto que haya que leer.
    public static let decorativo = Color.white.opacity(0.4)
    public static let superficie = Color.white.opacity(0.075)
    public static let superficieAlta = Color.white.opacity(0.14)

    public static let hexAgenda: UInt32 = 0x5AA9FF
    public static let hexGrabadora: UInt32 = 0xFF5D55
    public static let hexMusica: UInt32 = 0x3DDC97
    public static let hexBandeja: UInt32 = 0xA58BFF
    public static let hexPortapapeles: UInt32 = 0xFFB84D
    public static let hexEspejo: UInt32 = 0xFF8FB8
    public static let hexAirdrop: UInt32 = 0x35C3FF

    public static let agenda = Color(hex: hexAgenda)
    public static let grabadora = Color(hex: hexGrabadora)
    public static let musica = Color(hex: hexMusica)
    public static let bandeja = Color(hex: hexBandeja)
    public static let portapapeles = Color(hex: hexPortapapeles)
    public static let espejo = Color(hex: hexEspejo)
    public static let airdrop = Color(hex: hexAirdrop)
    public static let agente = Color.white
}

extension Color {
    /// Color sRGB opaco a partir de `0xRRGGBB`.
    public init(hex: UInt32) {
        let (rojo, verde, azul) = ColorHex.componentes(hex)
        self.init(.sRGB, red: rojo, green: verde, blue: azul, opacity: 1)
    }
}

public enum ColorHex {
    /// Componentes de 0 a 1 de `0xRRGGBB`.
    public static func componentes(_ hex: UInt32) -> (rojo: Double, verde: Double, azul: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}
