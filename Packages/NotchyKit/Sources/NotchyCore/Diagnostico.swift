import Foundation

/// Estado de OpenCode para el panel de diagnóstico (SIS-2).
public enum EstadoDeOpenCode: Sendable, Equatable {
    case instalado(ruta: String)
    case noEncontrado

    public var estaListo: Bool {
        if case .instalado = self { return true }
        return false
    }

    public var detalle: String {
        switch self {
        case .instalado(let ruta): "Instalado en \(ruta) (el supervisor se conecta en M6)"
        case .noEncontrado: "No se encontró el binario de OpenCode. Instálalo con: brew install opencode"
        }
    }
}

/// Estado de la base de datos para el panel de diagnóstico (SIS-2).
public struct DiagnosticoDeBase: Sendable, Equatable {
    public let estaBien: Bool
    public let detalle: String
    public let comoArreglarlo: String?

    public init(estaBien: Bool, detalle: String, comoArreglarlo: String? = nil) {
        self.estaBien = estaBien
        self.detalle = detalle
        self.comoArreglarlo = comoArreglarlo
    }
}

/// Resumen de un módulo para mostrar en el panel de diagnóstico.
public struct DiagnosticoDeModulo: Sendable, Equatable, Identifiable {
    public let id: String
    public let nombre: String
    public let activo: Bool
    public let salud: SaludDeModulo

    public init(id: String, nombre: String, activo: Bool, salud: SaludDeModulo) {
        self.id = id
        self.nombre = nombre
        self.activo = activo
        self.salud = salud
    }
}

/// Conteos agregados de elementos guardados para exportar en diagnóstico sin datos personales (SIS-4).
public struct ConteosDeDiagnostico: Sendable, Equatable, Codable {
    public let portapapeles: Int
    public let bandeja: Int
    public let reuniones: Int
    public let notasDeVoz: Int

    public init(portapapeles: Int = 0, bandeja: Int = 0, reuniones: Int = 0, notasDeVoz: Int = 0) {
        self.portapapeles = portapapeles
        self.bandeja = bandeja
        self.reuniones = reuniones
        self.notasDeVoz = notasDeVoz
    }
}

/// Metadatos de versión y equipo para el reporte de diagnóstico (SIS-4).
public struct EntornoDeDiagnostico: Sendable, Equatable, Codable {
    public let versionApp: String
    public let buildApp: String
    public let versionMacOS: String
    public let modeloMac: String
    public let arquitectura: String

    public init(
        versionApp: String,
        buildApp: String,
        versionMacOS: String,
        modeloMac: String,
        arquitectura: String
    ) {
        self.versionApp = versionApp
        self.buildApp = buildApp
        self.versionMacOS = versionMacOS
        self.modeloMac = modeloMac
        self.arquitectura = arquitectura
    }

    public static func actual(bundle: Bundle = .main) -> EntornoDeDiagnostico {
        let info = bundle.infoDictionary ?? [:]
        let versionApp = (info["CFBundleShortVersionString"] as? String) ?? "0.1.0"
        let buildApp = (info["CFBundleVersion"] as? String) ?? "1"
        let so = ProcessInfo.processInfo.operatingSystemVersion
        let versionMacOS = "\(so.majorVersion).\(so.minorVersion).\(so.patchVersion)"
        let modeloMac = Self.leerSysctl("hw.model") ?? "Mac"
        #if arch(arm64)
            let arquitectura = "arm64"
        #elseif arch(x86_64)
            let arquitectura = "x86_64"
        #else
            let arquitectura = "desconocida"
        #endif
        return EntornoDeDiagnostico(
            versionApp: versionApp,
            buildApp: buildApp,
            versionMacOS: versionMacOS,
            modeloMac: modeloMac,
            arquitectura: arquitectura
        )
    }

    private static func leerSysctl(_ nombre: String) -> String? {
        var tamano: Int = 0
        guard sysctlbyname(nombre, nil, &tamano, nil, 0) == 0, tamano > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: tamano)
        guard sysctlbyname(nombre, &buffer, &tamano, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
