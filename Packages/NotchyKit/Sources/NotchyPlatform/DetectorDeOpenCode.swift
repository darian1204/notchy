import Foundation
import NotchyCore

/// Comprueba si el binario de OpenCode está instalado en las rutas conocidas del Mac.
public enum DetectorDeOpenCode {
    public static let rutasCandidatas = [
        "/opt/homebrew/bin/opencode",
        "/usr/local/bin/opencode",
    ]

    public static func detectar(
        rutas: [String] = rutasCandidatas,
        esEjecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> EstadoDeOpenCode {
        for ruta in rutas where esEjecutable(ruta) {
            return .instalado(ruta: ruta)
        }
        return .noEncontrado
    }
}
