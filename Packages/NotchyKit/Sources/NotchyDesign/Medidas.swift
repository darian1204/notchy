import CoreGraphics

/// Medidas en puntos, tomadas de la tabla de estados del diseño.
public enum Medidas {
    /// Notch del MacBook Air M4 de 13". El real se lee de la pantalla; este es el respaldo.
    public static let notch = CGSize(width: 179, height: 32)
    /// Píldora flotante para pantallas sin notch.
    public static let pildora = CGSize(width: 300, height: 34)
    public static let compacto = CGSize(width: 283, height: 32)
    public static let aviso = CGSize(width: 440, height: 82)
    public static let inicio = CGSize(width: 620, height: 208)
    public static let portapapeles = CGSize(width: 620, height: 240)
    public static let bandeja = CGSize(width: 560, height: 168)
    public static let agenda = CGSize(width: 620, height: 232)
    public static let ahoraSuena = CGSize(width: 560, height: 176)
    public static let espejo = CGSize(width: 300, height: 232)
    public static let airdrop = CGSize(width: 560, height: 196)

    /// Tamaño del panel fijo (D-04): cabe el estado más grande del diseño más los hombros.
    public static let panel = CGSize(width: 640 + 2 * hombro, height: 244)

    public static let radioCompacto: CGFloat = 12
    public static let radioExpandido: CGFloat = 24
    public static let radioDeTarjeta: CGFloat = 14
    /// Curva de las esquinas de arriba, para fundirse con la barra de menús.
    public static let hombro: CGFloat = 10

    public static let margenSuperior: CGFloat = 4
    public static let margenInferior: CGFloat = 12
    public static let margenLateral: CGFloat = 12
    public static let separacion: CGFloat = 8
    public static let altoDeFila: CGFloat = 28
    public static let altoDeBoton: CGFloat = 26
    public static let altoDeBarraDeModulos: CGFloat = 28

    /// Separación entre la barra de menús y la píldora en pantallas sin notch.
    public static let separacionDePildora: CGFloat = 6
}
