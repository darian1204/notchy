import AppKit
import Foundation
import NotchyCore
import OSLog

/// Acumula fragmentos de `stdout` y entrega líneas UTF-8 completas.
nonisolated final class LectorDeLineas: @unchecked Sendable {
    private let candado = NSLock()
    private var buffer = Data()

    func agregar(_ datos: Data) -> [String] {
        candado.lock()
        defer { candado.unlock() }
        buffer.append(datos)
        var lineas: [String] = []
        while let salto = buffer.firstIndex(of: 0x0A) {
            let linea = String(decoding: buffer[buffer.startIndex..<salto], as: UTF8.self)
            lineas.append(linea)
            buffer.removeSubrange(buffer.startIndex...salto)
        }
        return lineas
    }
}

/// Decodifica líneas JSON emitidas por `mediaremote-adapter` manteniendo el estado entre diffs.
public struct DecodificadorDeMediaRemote {
    private var campos: [String: Any] = [:]

    public init() {}

    /// Procesa una línea JSON de `stream` y devuelve el `EstadoDeAhoraSuena` resultante (`nil` si no suena nada).
    public mutating func procesar(
        linea: String,
        en fecha: Date = .now,
        resolverNombreApp: (String) -> String = DecodificadorDeMediaRemote.nombreDeAppPorDefecto
    ) -> EstadoDeAhoraSuena? {
        guard
            let datos = linea.data(using: .utf8),
            let raiz = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
            let payload = raiz["payload"] as? [String: Any]
        else {
            return nil
        }
        let esDiff = (raiz["diff"] as? Bool) ?? false
        if !esDiff {
            campos.removeAll()
            for (clave, valor) in payload where !(valor is NSNull) {
                campos[clave] = valor
            }
        } else {
            for (clave, valor) in payload {
                if valor is NSNull {
                    campos.removeValue(forKey: clave)
                } else {
                    campos[clave] = valor
                }
            }
        }

        guard let titulo = (campos["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !titulo.isEmpty
        else {
            return nil
        }

        let artista = (campos["artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = (campos["album"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reproduciendo = (campos["playing"] as? Bool) ?? false
        let duracion = Self.numero(campos["duration"])
        let transcurrido = Self.numero(campos["elapsedTimeNow"]) ?? Self.numero(campos["elapsedTime"])
        let bundle =
            (campos["parentApplicationBundleIdentifier"] as? String)
            ?? (campos["bundleIdentifier"] as? String)
        let appOrigen = bundle.map(resolverNombreApp)
        let caratulaBase64 = campos["artworkData"] as? String
        let caratula = caratulaBase64.flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }

        return EstadoDeAhoraSuena(
            titulo: titulo,
            artista: (artista?.isEmpty == false) ? artista : nil,
            album: (album?.isEmpty == false) ? album : nil,
            appOrigen: appOrigen,
            bundleIdentifier: bundle,
            reproduciendo: reproduciendo,
            duracionSegundos: duracion,
            transcurridoSegundos: transcurrido,
            fechaDeMuestra: fecha,
            caratulaPNG: caratula,
            usandoRespaldoAppleScript: false
        )
    }

    private static func numero(_ valor: Any?) -> Double? {
        if let doble = valor as? Double { return doble }
        if let entero = valor as? Int { return Double(entero) }
        if let num = valor as? NSNumber { return num.doubleValue }
        return nil
    }

    public static func nombreDeAppPorDefecto(_ bundleId: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return bundleId
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}

/// Rutas del adaptador `mediaremote-adapter` (D-18).
public struct RutasDeMediaRemote: Sendable, Equatable {
    public let scriptPerl: String
    public let framework: String
    public let clienteDePrueba: String?

    public init(scriptPerl: String, framework: String, clienteDePrueba: String?) {
        self.scriptPerl = scriptPerl
        self.framework = framework
        self.clienteDePrueba = clienteDePrueba
    }

    public static func detectar() -> RutasDeMediaRemote? {
        let raizDelPaquete = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let carpetasCandidatas: [URL] = [
            raizDelPaquete.appending(path: "Resources/mediaremote-adapter"),
            Bundle.main.resourceURL?.appending(path: "mediaremote-adapter"),
            home.appending(path: "Developer/notchy/Resources/mediaremote-adapter"),
            home.appending(path: "Developer/isla-spikes/vendor/mediaremote-adapter"),
        ].compactMap { $0 }

        let fm = FileManager.default
        for carpeta in carpetasCandidatas {
            let scripts = [
                carpeta.appending(path: "mediaremote-adapter.pl").path,
                carpeta.appending(path: "bin/mediaremote-adapter.pl").path,
            ]
            let frameworks = [
                carpeta.appending(path: "MediaRemoteAdapter.framework").path,
                carpeta.appending(path: "build/MediaRemoteAdapter.framework").path,
            ]
            let clientes = [
                carpeta.appending(path: "MediaRemoteAdapterTestClient").path,
                carpeta.appending(path: "build/MediaRemoteAdapterTestClient").path,
            ]
            if let script = scripts.first(where: { fm.fileExists(atPath: $0) }),
                let framework = frameworks.first(where: { fm.fileExists(atPath: $0) })
            {
                let cliente = clientes.first(where: { fm.isExecutableFile(atPath: $0) })
                return RutasDeMediaRemote(
                    scriptPerl: script,
                    framework: framework,
                    clienteDePrueba: cliente
                )
            }
        }
        return nil
    }
}

/// Adaptador real de Ahora suena: usa `mediaremote-adapter` en modo `stream` y cae a AppleScript
/// si el adaptador no está disponible o termina con error (D-18, MUS-1).
@MainActor
public final class AdaptadorDeAhoraSuena: PuertoDeAhoraSuena {
    private let rutas: RutasDeMediaRemote?
    private let log = Registro.de(.musica)
    private var proceso: Process?
    private var temporizadorRespaldo: Task<Void, Never>?
    private var alCambiar: (@MainActor (EstadoDeAhoraSuena?) -> Void)?
    private var decodificador = DecodificadorDeMediaRemote()
    private var usandoRespaldo = false
    private var detenidoPorUsuario = false

    public init(rutas: RutasDeMediaRemote? = RutasDeMediaRemote.detectar()) {
        self.rutas = rutas
    }

    public func iniciar(alCambiar: @escaping @MainActor (EstadoDeAhoraSuena?) -> Void) {
        detener()
        self.alCambiar = alCambiar
        self.detenidoPorUsuario = false
        self.decodificador = DecodificadorDeMediaRemote()

        guard let rutas else {
            log.info("No se encontró mediaremote-adapter; activando respaldo AppleScript")
            iniciarRespaldoAppleScript()
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [rutas.scriptPerl, rutas.framework, "stream", "--debounce=150"]
        let salida = Pipe()
        let errores = Pipe()
        proc.standardOutput = salida
        proc.standardError = errores

        let lector = LectorDeLineas()
        salida.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let datos = handle.availableData
            guard !datos.isEmpty else { return }
            let lineas = lector.agregar(datos)
            let fecha = Date()
            Task { @MainActor [weak self] in
                guard let self else { return }
                for linea in lineas where !linea.isEmpty {
                    let estado = self.decodificador.procesar(linea: linea, en: fecha)
                    self.alCambiar?(estado)
                }
            }
        }
        errores.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        proc.terminationHandler = { [weak self] terminado in
            let codigo = terminado.terminationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.proceso = nil
                guard !self.detenidoPorUsuario, codigo != 0 else { return }
                self.log.error(
                    "mediaremote-adapter terminó con código \(codigo, privacy: .public); activando AppleScript")
                self.iniciarRespaldoAppleScript()
            }
        }

        do {
            try proc.run()
            proceso = proc
            usandoRespaldo = false
        } catch {
            log.error("No se pudo lanzar mediaremote-adapter: \(error.localizedDescription, privacy: .public)")
            iniciarRespaldoAppleScript()
        }
    }

    public func detener() {
        detenidoPorUsuario = true
        temporizadorRespaldo?.cancel()
        temporizadorRespaldo = nil
        if let proc = proceso {
            if let salida = proc.standardOutput as? Pipe {
                salida.fileHandleForReading.readabilityHandler = nil
            }
            if let errores = proc.standardError as? Pipe {
                errores.fileHandleForReading.readabilityHandler = nil
            }
            proc.terminate()
            proceso = nil
        }
    }

    public func enviar(_ comando: ComandoDeReproduccion) {
        if !usandoRespaldo, let rutas {
            let script = rutas.scriptPerl
            let framework = rutas.framework
            let valor = String(comando.rawValue)
            Task.detached {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
                proc.arguments = [script, framework, "send", valor]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                try? proc.run()
                proc.waitUntilExit()
            }
        } else {
            enviarConAppleScript(comando)
        }
    }

    public func saltarA(segundos: Double) {
        let destinoSegundos = max(0, segundos)
        // 1. Intentar vía MediaRemote privado (MRMediaRemoteSetElapsedTime)
        if let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
            let sym = dlsym(handle, "MRMediaRemoteSetElapsedTime")
        {
            typealias SetElapsedFn = @convention(c) (Double) -> Void
            let fn = unsafeBitCast(sym, to: SetElapsedFn.self)
            fn(destinoSegundos)
        }
        // 2. Respaldo directo AppleScript para Spotify y Music (garantiza salto exacto en macOS 27)
        let abiertas = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let destinoApp: String? =
            if abiertas.contains("com.spotify.client") {
                "Spotify"
            } else if abiertas.contains("com.apple.Music") {
                "Music"
            } else {
                nil
            }
        if let destinoApp {
            let valorTexto = String(format: "%.1f", destinoSegundos)
            let fuente = "tell application \"\(destinoApp)\" to set player position to \(valorTexto)"
            Task.detached {
                var error: NSDictionary?
                _ = NSAppleScript(source: fuente)?.executeAndReturnError(&error)
            }
        }
    }

    public func probarAdaptador() async -> Bool {
        guard let rutas, let cliente = rutas.clienteDePrueba else { return false }
        let script = rutas.scriptPerl
        let framework = rutas.framework
        return await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            proc.arguments = [script, framework, cliente, "test"]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
                return proc.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }

    // MARK: Respaldo con AppleScript (D-18)

    private func iniciarRespaldoAppleScript() {
        usandoRespaldo = true
        temporizadorRespaldo?.cancel()
        temporizadorRespaldo = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let estado = self.consultarAppleScript()
                self.alCambiar?(estado)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func consultarAppleScript() -> EstadoDeAhoraSuena? {
        let abiertas = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if abiertas.contains("com.spotify.client"),
            let spotify = ejecutarConsultaAppleScript(
                appName: "Spotify",
                bundleId: "com.spotify.client",
                nombreVisible: "Spotify"
            )
        {
            return spotify
        }
        if abiertas.contains("com.apple.Music"),
            let musica = ejecutarConsultaAppleScript(
                appName: "Music",
                bundleId: "com.apple.Music",
                nombreVisible: "Música"
            )
        {
            return musica
        }
        return nil
    }

    private func ejecutarConsultaAppleScript(
        appName: String,
        bundleId: String,
        nombreVisible: String
    ) -> EstadoDeAhoraSuena? {
        let fuente = """
            tell application "\(appName)"
                if player state is stopped then return ""
                set estadoTexto to (player state as text)
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set d to duration of current track
                set p to player position
                return estadoTexto & "||" & t & "||" & a & "||" & al & "||" & (d as text) & "||" & (p as text)
            end tell
            """
        var error: NSDictionary?
        guard let resultado = NSAppleScript(source: fuente)?.executeAndReturnError(&error).stringValue,
            !resultado.isEmpty
        else {
            return nil
        }
        let partes = resultado.components(separatedBy: "||")
        guard partes.count >= 6 else { return nil }
        let reproduciendo = partes[0].lowercased().contains("playing")
        let titulo = partes[1]
        let artista = partes[2].isEmpty ? nil : partes[2]
        let album = partes[3].isEmpty ? nil : partes[3]
        var duracion = Double(partes[4].replacingOccurrences(of: ",", with: "."))
        if let d = duracion, bundleId == "com.spotify.client", d > 10_000 {
            duracion = d / 1000.0
        }
        let posicion = Double(partes[5].replacingOccurrences(of: ",", with: "."))
        return EstadoDeAhoraSuena(
            titulo: titulo,
            artista: artista,
            album: album,
            appOrigen: nombreVisible,
            bundleIdentifier: bundleId,
            reproduciendo: reproduciendo,
            duracionSegundos: duracion,
            transcurridoSegundos: posicion,
            fechaDeMuestra: .now,
            caratulaPNG: nil,
            usandoRespaldoAppleScript: true
        )
    }

    private func enviarConAppleScript(_ comando: ComandoDeReproduccion) {
        let abiertas = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let destino: String? =
            if abiertas.contains("com.spotify.client") {
                "Spotify"
            } else if abiertas.contains("com.apple.Music") {
                "Music"
            } else {
                nil
            }
        guard let destino else { return }
        let verbo: String =
            switch comando {
            case .reproducir: "play"
            case .pausar: "pause"
            case .alternar: "playpause"
            case .siguiente: "next track"
            case .anterior: "previous track"
            }
        let fuente = "tell application \"\(destino)\" to \(verbo)"
        var error: NSDictionary?
        _ = NSAppleScript(source: fuente)?.executeAndReturnError(&error)
    }
}
