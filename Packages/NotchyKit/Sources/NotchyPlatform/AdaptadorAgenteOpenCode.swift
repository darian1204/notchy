import Foundation
import NotchyCore
import OSLog

/// Adaptador que ejecuta `opencode run --format json` y transmite fragmentos en vivo al minichatbot agéntico.
@MainActor
public final class AdaptadorAgenteOpenCode: PuertoAgenteOpenCode {
    private let log = Registro.de(.agente)

    public init() {}

    public func estaDisponible() -> Bool {
        DetectorDeOpenCode.detectar().estaListo
    }

    public func modelosDisponibles() async -> [String] {
        guard case .instalado(let ruta) = DetectorDeOpenCode.detectar() else {
            return ProveedoresDelAgente.modelosDeRespaldo
        }
        return await Task.detached {
            let proceso = Process()
            proceso.executableURL = URL(fileURLWithPath: ruta)
            proceso.arguments = ["models"]
            let pipe = Pipe()
            proceso.standardOutput = pipe
            proceso.standardError = FileHandle.nullDevice
            do {
                try proceso.run()
                let datos = pipe.fileHandleForReading.readDataToEndOfFile()
                proceso.waitUntilExit()
                let salida = String(data: datos, encoding: .utf8) ?? ""
                let lineas =
                    salida
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.contains("/") }
                let permitidos = ProveedoresDelAgente.filtrar(lineas)
                return permitidos.isEmpty ? ProveedoresDelAgente.modelosDeRespaldo : permitidos
            } catch {
                return ProveedoresDelAgente.modelosDeRespaldo
            }
        }.value
    }

    public func enviarMensaje(
        prompt: String,
        modelo: String?,
        sesionID: String?,
        directorio: String?,
        alRecibirFragmento: @escaping @MainActor (String, String?) -> Void
    ) async throws -> (textoFinal: String, sesionID: String?) {
        guard case .instalado(let ruta) = DetectorDeOpenCode.detectar() else {
            throw NSError(
                domain: "NotchyOpenCode",
                code: 404,
                userInfo: [
                    NSLocalizedDescriptionKey: "No se encontró el binario opencode en /opt/homebrew/bin/opencode."
                ]
            )
        }

        var argumentos = ["run", "--format", "json"]
        if let modelo, !modelo.isEmpty {
            argumentos.append(contentsOf: ["-m", modelo])
        }
        if let sesionID, !sesionID.isEmpty {
            argumentos.append(contentsOf: ["-s", sesionID])
        }
        if let directorio, !directorio.isEmpty {
            argumentos.append(contentsOf: ["--dir", directorio])
        }
        argumentos.append(prompt)

        return try await Task.detached {
            let proceso = Process()
            proceso.executableURL = URL(fileURLWithPath: ruta)
            proceso.arguments = argumentos
            var entorno = ProcessInfo.processInfo.environment
            let pathActual = entorno["PATH"] ?? "/usr/bin:/bin"
            entorno["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(pathActual)"
            proceso.environment = entorno

            let pipeSalida = Pipe()
            let pipeError = Pipe()
            proceso.standardOutput = pipeSalida
            proceso.standardError = pipeError

            try proceso.run()
            let datosSalida = pipeSalida.fileHandleForReading.readDataToEndOfFile()
            let datosError = pipeError.fileHandleForReading.readDataToEndOfFile()
            proceso.waitUntilExit()

            let textoCrudo = String(data: datosSalida, encoding: .utf8) ?? ""
            var acumulado = ""
            var sesionDetectada: String? = sesionID

            for linea in textoCrudo.components(separatedBy: .newlines) {
                let limpia = linea.trimmingCharacters(in: .whitespacesAndNewlines)
                guard limpia.hasPrefix("{"),
                    let data = limpia.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    continue
                }
                if let sid = json["sessionID"] as? String, !sid.isEmpty {
                    sesionDetectada = sid
                }
                let tipo = json["type"] as? String ?? ""
                if tipo == "text",
                    let part = json["part"] as? [String: Any],
                    let fragmento = part["text"] as? String,
                    !fragmento.isEmpty
                {
                    if acumulado.isEmpty {
                        acumulado = fragmento
                    } else {
                        acumulado += "\n" + fragmento
                    }
                    let copiaAcumulado = acumulado
                    let copiaSesion = sesionDetectada
                    await MainActor.run {
                        alRecibirFragmento(copiaAcumulado, copiaSesion)
                    }
                }
            }

            if acumulado.isEmpty {
                let respaldo = Self.limpiarSalidaPlana(textoCrudo)
                if !respaldo.isEmpty {
                    acumulado = respaldo
                } else {
                    let errTexto =
                        String(data: datosError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    acumulado = errTexto.isEmpty ? "Listo." : errTexto
                }
            }
            return (acumulado, sesionDetectada)
        }.value
    }

    private nonisolated static func limpiarSalidaPlana(_ texto: String) -> String {
        let lineas = texto.components(separatedBy: .newlines).filter { linea in
            let l = linea.trimmingCharacters(in: .whitespaces)
            return !l.isEmpty && !l.hasPrefix(">") && !l.hasPrefix("{")
        }
        return lineas.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
