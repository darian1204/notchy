import Foundation

/// Dónde guarda Notchy sus archivos. Todo cuelga de una sola carpeta para poder borrarlo todo.
public struct RutasDeDatos: Sendable, Equatable {
    public let raiz: URL

    public init(raiz: URL) {
        self.raiz = raiz
    }

    /// `~/Library/Application Support/Notchy`, o `Notchy-Dev` en depuración.
    public static func porDefecto(_ compilacion: NotchyInfo.Compilacion = NotchyInfo.compilacionActual) throws
        -> RutasDeDatos
    {
        let soporte = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return RutasDeDatos(
            raiz: soporte.appending(path: NotchyInfo.carpetaDeDatos(compilacion), directoryHint: .isDirectory))
    }

    public var baseDeDatos: URL { raiz.appending(path: "notchy.sqlite") }
    public var portapapeles: URL { raiz.appending(path: "clipboard", directoryHint: .isDirectory) }
    public var bandeja: URL { raiz.appending(path: "tray", directoryHint: .isDirectory) }
    public var audio: URL { raiz.appending(path: "audio", directoryHint: .isDirectory) }
    public var modelos: URL { raiz.appending(path: "models", directoryHint: .isDirectory) }
    public var configOpenCode: URL { raiz.appending(path: "opencode.json") }
    public var promptAgenteOpenCode: URL { raiz.appending(path: "prompt-agente.md") }

    public func crearCarpetas() throws {
        for carpeta in [raiz, portapapeles, bandeja, audio, modelos] {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        }
    }
}
