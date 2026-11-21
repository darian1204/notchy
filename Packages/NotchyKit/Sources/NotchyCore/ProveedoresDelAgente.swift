import Foundation

/// Clasificación de privacidad y ejecución de un modelo del agente (AGT-5).
public enum UbicacionDeModeloAgente: String, Sendable, Equatable, Codable {
    case local = "Local"
    case nube = "Nube"
}

/// Proveedores y modelos que el agente puede usar (D-15, AGT-5).
///
/// Desde 2026-11-16 solo se permite el proveedor gratis de OpenCode (`opencode/…`) y el modelo local de Apple (`apple/local`).
/// Los modelos de OpenAI quedan fuera aunque el OpenCode del Mac tenga la sesión iniciada.
public enum ProveedoresDelAgente {
    /// Identificador del modelo de Apple Intelligence que corre en la Mac.
    public static let modeloAppleLocal = "apple/local"

    /// Nombre legible para el selector cuando se trata del modelo local de Apple.
    public static let etiquetaAppleLocal = "Apple (en la Mac)"

    /// Proveedores permitidos; deben coincidir con `enabled_providers` de la plantilla de OpenCode más `apple`.
    public static let permitidos: Set<String> = ["opencode", "apple"]

    /// Proveedores clasificados como ejecución local en la Mac (AGT-5).
    public static let proveedoresLocales: Set<String> = ["apple", "local", "ollama", "lmstudio"]

    /// Modelo que se usa si no hay uno elegido o el elegido ya no está permitido.
    public static let modeloPorDefecto = "opencode/glm-5.3-flash-free"

    /// Lista corta cuando OpenCode no responde con la suya.
    public static let modelosDeRespaldo = [
        "opencode/glm-5.3-flash-free",
        "opencode/deepseek-v4.1-flash-free",
        "opencode/big-pickle",
    ]

    /// Proveedor de un identificador `proveedor/modelo` (o el propio identificador en minúsculas si no tiene `/`).
    public static func proveedor(de modelo: String) -> String {
        let limpio = modelo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return String(limpio.split(separator: "/", maxSplits: 1).first ?? "")
    }

    /// Clasifica un modelo como `.local` (`apple/...`, `local`, `ollama/...`, `lmstudio/...`) o `.nube` (`opencode/...`, etc.) (AGT-5).
    public static func clasificar(_ modelo: String) -> UbicacionDeModeloAgente {
        let limpio = modelo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if limpio == "local" || limpio == "apple" {
            return .local
        }
        let prov = proveedor(de: limpio)
        if proveedoresLocales.contains(prov) {
            return .local
        }
        return .nube
    }

    public static func esModeloDeApple(_ modelo: String) -> Bool {
        let limpio = modelo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return limpio == "local" || limpio == "apple" || proveedor(de: limpio) == "apple"
    }

    public static func nombreParaMostrar(_ modelo: String) -> String {
        if esModeloDeApple(modelo) {
            return etiquetaAppleLocal
        }
        return modelo
    }

    public static func nombreCortoParaMostrar(_ modelo: String) -> String {
        if esModeloDeApple(modelo) {
            return etiquetaAppleLocal
        }
        return modelo.components(separatedBy: "/").last ?? modelo
    }

    public static func estaPermitido(_ modelo: String) -> Bool {
        if esModeloDeApple(modelo) { return true }
        return modelo.contains("/") && permitidos.contains(proveedor(de: modelo))
    }

    /// Deja solo los modelos permitidos, sin repetir y en el mismo orden.
    public static func filtrar(_ modelos: [String]) -> [String] {
        var vistos = Set<String>()
        return modelos.filter { estaPermitido($0) && vistos.insert($0).inserted }
    }

    /// El modelo elegido si sigue permitido y disponible; si no, el de por defecto o el primero de la lista.
    public static func resolver(elegido: String?, disponibles: [String]) -> String {
        let lista = filtrar(disponibles)
        if let elegido, estaPermitido(elegido), lista.isEmpty || lista.contains(elegido) {
            return elegido
        }
        if lista.isEmpty || lista.contains(modeloPorDefecto) { return modeloPorDefecto }
        return lista[0]
    }
}
