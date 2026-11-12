/// Identidad de la app. El identificador coincide con `PRODUCT_BUNDLE_IDENTIFIER` de `Config/Base.xcconfig`.
public enum IslaInfo {
    public static let nombre = "Isla"
    public static let identificador = "dev.darian.isla"

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
        case .depuracion: "Isla-Dev"
        case .publicacion: "Isla"
        }
    }
}
