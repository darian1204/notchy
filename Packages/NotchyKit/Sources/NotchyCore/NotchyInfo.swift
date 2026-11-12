/// Identidad de la app. El identificador coincide con `PRODUCT_BUNDLE_IDENTIFIER` de `Config/Base.xcconfig`.
public enum NotchyInfo {
    public static let nombre = "Notchy"
    public static let identificador = "dev.darian.notchy"

    public enum Compilacion: Sendable {
        case depuracion
        case publicacion
    }

    public static var compilacionActual: Compilacion {
        #if DEBUG
            .depuracion
        #else
            .publicacion
        #endif
    }

    /// Carpeta dentro de Application Support. La de depuración va aparte para no tocar los datos reales.
    public static func carpetaDeDatos(_ compilacion: Compilacion) -> String {
        switch compilacion {
        case .depuracion: "Notchy-Dev"
        case .publicacion: "Notchy"
        }
    }
}
