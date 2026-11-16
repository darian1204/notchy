import Foundation

/// Proveedores y modelos que el agente puede usar (D-15).
///
/// Desde 2026-11-16 solo se permite el proveedor gratis de OpenCode (`opencode/…`).
/// Los modelos de OpenAI quedan fuera aunque el OpenCode del Mac tenga la sesión iniciada.
public enum ProveedoresDelAgente {
    /// Proveedores permitidos; deben coincidir con `enabled_providers` de la plantilla de OpenCode.
    public static let permitidos: Set<String> = ["opencode"]

    /// Modelo que se usa si no hay uno elegido o el elegido ya no está permitido.
    public static let modeloPorDefecto = "opencode/glm-5.3-flash-free"

    /// Lista corta cuando OpenCode no responde con la suya.
    public static let modelosDeRespaldo = [
        "opencode/glm-5.3-flash-free",
        "opencode/deepseek-v4.1-flash-free",
        "opencode/big-pickle",
    ]

    /// Proveedor de un identificador `proveedor/modelo`.
    public static func proveedor(de modelo: String) -> String {
        String(modelo.split(separator: "/", maxSplits: 1).first ?? "")
    }

    public static func estaPermitido(_ modelo: String) -> Bool {
        modelo.contains("/") && permitidos.contains(proveedor(de: modelo))
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
