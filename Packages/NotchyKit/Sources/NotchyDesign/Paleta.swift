import SwiftUI

/// Colores de la isla. Negro puro por defecto para fundirse con el notch, o el tema elegido.
public enum Paleta {
    public static let fondo = Color.black
    public static let texto = Color.white
    /// Texto de apoyo: 64% de blanco (≈ 7.8:1 sobre negro). El texto esencial nunca baja de aquí.
    public static let textoDeApoyo = Color.white.opacity(0.64)
    /// Solo decorativo: 40% de blanco (≈ 3.4:1). No usar para texto que haya que leer.
    public static let decorativo = Color.white.opacity(0.4)
    public static let superficie = Color.white.opacity(0.075)
    public static let superficieAlta = Color.white.opacity(0.14)
    public static let borde = Color.white.opacity(0.14)
    /// Borde de las tarjetas del estilo tarjetas: apenas se nota sobre la superficie.
    public static let bordeSuave = Color.white.opacity(0.10)

    public static let hexAgenda: UInt32 = 0x5AA9FF
    public static let hexGrabadora: UInt32 = 0xFF5D55
    public static let hexMusica: UInt32 = 0x3DDC97
    public static let hexBandeja: UInt32 = 0xA58BFF
    public static let hexPortapapeles: UInt32 = 0xFFB84D
    public static let hexEspejo: UInt32 = 0xFF8FB8
    public static let hexAirdrop: UInt32 = 0x35C3FF
    public static let hexColorPicker: UInt32 = 0xD97D98
    public static let hexScreenTime: UInt32 = 0x5AA9FF
    public static let hexClima: UInt32 = 0x4FC3F7
    public static let hexNotificaciones: UInt32 = 0xFF9F0A
    public static let hexAgente: UInt32 = 0xBF5AF2
    public static let hexTraductor: UInt32 = 0x64D2FF
    public static let hexWindowSnap: UInt32 = 0x30D158
    public static let hexMonitorSistema: UInt32 = 0x32D74B

    public static let agenda = Color(hex: hexAgenda)
    public static let grabadora = Color(hex: hexGrabadora)
    public static let musica = Color(hex: hexMusica)
    public static let bandeja = Color(hex: hexBandeja)
    public static let portapapeles = Color(hex: hexPortapapeles)
    public static let espejo = Color(hex: hexEspejo)
    public static let airdrop = Color(hex: hexAirdrop)
    public static let colorPicker = Color(hex: hexColorPicker)
    public static let screenTime = Color(hex: hexScreenTime)
    public static let clima = Color(hex: hexClima)
    public static let notificaciones = Color(hex: hexNotificaciones)
    public static let agente = Color(hex: hexAgente)
    public static let traductor = Color(hex: hexTraductor)
    public static let windowSnap = Color(hex: hexWindowSnap)
    public static let monitorSistema = Color(hex: hexMonitorSistema)
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
