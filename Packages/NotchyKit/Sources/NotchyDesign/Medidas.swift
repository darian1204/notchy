import CoreGraphics

/// Medidas en puntos, tomadas de la tabla de estados del diseño.
public enum Medidas {
    /// Notch del MacBook Air M4 de 13". El real se lee de la pantalla; este es el respaldo.
    public static let notch = CGSize(width: 179, height: 32)
    /// Píldora flotante para pantallas sin notch.
    public static let pildora = CGSize(width: 300, height: 34)
    public static let compacto = CGSize(width: 283, height: 32)
    /// Ancho de cada oreja compacta por defecto y el de las actividades breves.
    public static let orejaCompacta: CGFloat = 52
    public static let orejaBreve: CGFloat = 64
    /// Separación entre el cuerpo de la isla y la burbuja de la segunda actividad.
    public static let separacionDeBurbuja: CGFloat = 8
    public static let aviso = CGSize(width: 440, height: 82)
    public static let inicio = CGSize(width: 620, height: 224)
    public static let portapapeles = CGSize(width: 620, height: 240)
    public static let bandeja = CGSize(width: 620, height: 236)
    public static let agenda = CGSize(width: 620, height: 232)
    public static let grabadora = CGSize(width: 620, height: 238)
    public static let ahoraSuena = CGSize(width: 620, height: 224)
    public static let espejo = CGSize(width: 620, height: 232)
    public static let airdrop = CGSize(width: 620, height: 212)
    public static let colorPicker = CGSize(width: 620, height: 232)
    public static let screenTime = CGSize(width: 620, height: 236)
    public static let clima = CGSize(width: 620, height: 238)
    public static let notificaciones = CGSize(width: 620, height: 238)
    public static let agente = CGSize(width: 620, height: 238)
    public static let traductor = CGSize(width: 620, height: 232)
    public static let windowSnap = CGSize(width: 620, height: 224)
    public static let monitorSistema = CGSize(width: 620, height: 238)

    /// Estilo tarjetas: todos los módulos se abren a este ancho, con la fila de puntos bajo el notch.
    public static let anchoTarjetas: CGFloat = 680
    public static let altoDePuntos: CGFloat = 8
    /// Inicio en estilo tarjetas, sin contar la fila de puntos (la suma la isla).
    public static let inicioTarjetas = CGSize(width: anchoTarjetas, height: 202)
    /// Ancho de cada píldora de pestañas; las dos miden igual para que la barra sea simétrica.
    public static let anchoDePestanas: CGFloat = 204

    /// Tamaño del panel fijo (D-04): cabe el estado más grande de los dos estilos más los hombros.
    public static let panel = CGSize(width: anchoTarjetas + 2 * hombro, height: 252)

    public static let radioCompacto: CGFloat = 12
    public static let radioExpandido: CGFloat = 24
    public static let radioDeTarjeta: CGFloat = 14
    /// Radio de las tarjetas del estilo tarjetas: concéntrico con la isla (24 − 12 de margen).
    public static let radioDeTarjetaInterna: CGFloat = 12
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
