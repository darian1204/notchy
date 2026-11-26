import Foundation
import NotchyCore
import NotchyStorage
import Observation

/// Modelo de vista para la ventana de Ajustes y el panel de Permisos y Diagnóstico (ISL-8, SIS-1, SIS-2, SIS-3, SIS-4).
@MainActor
@Observable
public final class ModeloDeAjustesYDiagnostico {
    public let ajustes: Ajustes
    public private(set) var modulosDisponibles: [IdentidadDeModulo]
    public private(set) var estadosDePermisos: [PermisoDelSistema: EstadoDePermiso] = [:]
    public private(set) var diagnosticoDeBase: DiagnosticoDeBase
    public private(set) var estadoDeOpenCode: EstadoDeOpenCode
    public private(set) var diagnosticoDeModulos: [DiagnosticoDeModulo] = []
    public private(set) var estadoDeInicioAlAbrirSesion: EstadoDeInicioAlAbrirSesion = .inactivo
    public private(set) var conteosDeDiagnostico = ConteosDeDiagnostico()

    @ObservationIgnored private let proveedorDePermisos: any ProveedorDePermisos
    @ObservationIgnored private let servicioDeInicio: (any ServicioDeInicioAlAbrirSesion)?
    @ObservationIgnored private let consultarBase: @MainActor () -> DiagnosticoDeBase
    @ObservationIgnored private let consultarOpenCode: @MainActor () -> EstadoDeOpenCode
    @ObservationIgnored private let consultarModulos: @MainActor () -> [DiagnosticoDeModulo]
    @ObservationIgnored private let consultarConteos: @MainActor () -> ConteosDeDiagnostico
    @ObservationIgnored private let bus: BusDeEventos?
    @ObservationIgnored private var ultimoValorInicioAplicado: Bool

    public init(
        ajustes: Ajustes,
        modulosDisponibles: [IdentidadDeModulo] = [],
        proveedorDePermisos: any ProveedorDePermisos,
        servicioDeInicio: (any ServicioDeInicioAlAbrirSesion)? = nil,
        consultarBase: @escaping @MainActor () -> DiagnosticoDeBase,
        consultarOpenCode: @escaping @MainActor () -> EstadoDeOpenCode,
        consultarModulos: @escaping @MainActor () -> [DiagnosticoDeModulo] = { [] },
        consultarConteos: @escaping @MainActor () -> ConteosDeDiagnostico = { ConteosDeDiagnostico() },
        bus: BusDeEventos? = nil
    ) {
        self.ajustes = ajustes
        self.modulosDisponibles = modulosDisponibles
        self.proveedorDePermisos = proveedorDePermisos
        self.servicioDeInicio = servicioDeInicio
        self.consultarBase = consultarBase
        self.consultarOpenCode = consultarOpenCode
        self.consultarModulos = consultarModulos
        self.consultarConteos = consultarConteos
        self.bus = bus
        self.diagnosticoDeBase = consultarBase()
        self.estadoDeOpenCode = consultarOpenCode()
        self.ultimoValorInicioAplicado = ajustes.iniciarAlAbrirSesion
        if let servicioDeInicio {
            self.estadoDeInicioAlAbrirSesion = servicioDeInicio.aplicar(activo: ajustes.iniciarAlAbrirSesion)
        }
        ajustes.observar { [weak self] in
            self?.sincronizarInicioSiCambio()
        }
        refrescar()
    }

    /// Relee permisos, salud de la base, estado de OpenCode, módulos, inicio de sesión y conteos.
    public func refrescar() {
        var nuevos: [PermisoDelSistema: EstadoDePermiso] = [:]
        for permiso in PermisoDelSistema.allCases {
            nuevos[permiso] = proveedorDePermisos.estado(de: permiso)
        }
        estadosDePermisos = nuevos
        diagnosticoDeBase = consultarBase()
        estadoDeOpenCode = consultarOpenCode()
        diagnosticoDeModulos = consultarModulos()
        conteosDeDiagnostico = consultarConteos()
        if let servicioDeInicio {
            estadoDeInicioAlAbrirSesion = servicioDeInicio.estado()
        }
    }

    // MARK: Inicio al abrir sesión (SIS-3)

    public func aplicarInicioAlAbrirSesion() {
        ultimoValorInicioAplicado = ajustes.iniciarAlAbrirSesion
        guard let servicioDeInicio else { return }
        estadoDeInicioAlAbrirSesion = servicioDeInicio.aplicar(activo: ajustes.iniciarAlAbrirSesion)
    }

    public func abrirAjustesDeItemsDeInicio() {
        servicioDeInicio?.abrirAjustesDeItemsDeInicio()
    }

    private func sincronizarInicioSiCambio() {
        guard ajustes.iniciarAlAbrirSesion != ultimoValorInicioAplicado else { return }
        aplicarInicioAlAbrirSesion()
    }

    public func actualizarModulosDisponibles(_ modulos: [IdentidadDeModulo]) {
        modulosDisponibles = modulos
        diagnosticoDeModulos = consultarModulos()
    }

    // MARK: Módulos y orden (ISL-8)

    public var modulosOrdenados: [IdentidadDeModulo] {
        let orden = ajustes.ordenar(modulosDisponibles.map(\.id))
        return orden.compactMap { id in modulosDisponibles.first { $0.id == id } }
    }

    public func estaModuloActivo(_ id: String) -> Bool {
        ajustes.estaActivo(id)
    }

    public func cambiarModuloActivo(_ id: String, _ activo: Bool) {
        // El módulo de Inicio siempre debe poder abrirse si no hay otros, pero permitimos
        // encender o apagar cualquier módulo salvo dejar la isla completamente vacía si es Inicio.
        ajustes.activar(id, activo)
        diagnosticoDeModulos = consultarModulos()
    }

    public func moverModuloArriba(_ id: String) {
        var ids = modulosOrdenados.map(\.id)
        guard let indice = ids.firstIndex(of: id), indice > 0 else { return }
        ids.swapAt(indice, indice - 1)
        ajustes.ordenDeModulos = ids
        diagnosticoDeModulos = consultarModulos()
    }

    public func moverModuloAbajo(_ id: String) {
        var ids = modulosOrdenados.map(\.id)
        guard let indice = ids.firstIndex(of: id), indice + 1 < ids.count else { return }
        ids.swapAt(indice, indice + 1)
        ajustes.ordenDeModulos = ids
        diagnosticoDeModulos = consultarModulos()
    }

    // MARK: Permisos (SIS-2)

    public func estado(de permiso: PermisoDelSistema) -> EstadoDePermiso {
        estadosDePermisos[permiso] ?? .sinPedir
    }

    public func pedirPermiso(_ permiso: PermisoDelSistema) async {
        let nuevo = await proveedorDePermisos.pedir(permiso)
        estadosDePermisos[permiso] = nuevo
        if let bus {
            await bus.publicar(CambioDePermiso(permiso: permiso, estado: nuevo))
        }
    }

    // MARK: Diagnóstico de la base

    public static func diagnosticarBase(_ base: BaseDeDatos?) -> DiagnosticoDeBase {
        guard let base else {
            return DiagnosticoDeBase(
                estaBien: false,
                detalle: "La base de datos no está abierta.",
                comoArreglarlo:
                    "Revisa que la carpeta en Application Support tenga permisos de escritura y reinicia Notchy."
            )
        }
        do {
            let salud = try base.salud()
            if salud.estaBien {
                let lista = salud.migraciones.joined(separator: ", ")
                return DiagnosticoDeBase(
                    estaBien: true,
                    detalle: "SQLite \(salud.versionDeSQLite) · FTS5 activo · migraciones: \(lista)"
                )
            }
            var problemas: [String] = []
            if !salud.integra {
                problemas.append("falló la revisión de integridad (\(salud.problemaDeIntegridad ?? "sin detalle"))")
            }
            if !salud.busquedaDeTexto { problemas.append("sin soporte FTS5") }
            if salud.migraciones.isEmpty { problemas.append("sin migraciones aplicadas") }
            return DiagnosticoDeBase(
                estaBien: false,
                detalle: "Problemas en la base: \(problemas.joined(separator: ", ")).",
                comoArreglarlo: "Cierra Notchy y verifica el archivo notchy.sqlite en Application Support."
            )
        } catch {
            return DiagnosticoDeBase(
                estaBien: false,
                detalle: error.localizedDescription,
                comoArreglarlo: "Cierra Notchy y verifica el archivo notchy.sqlite en Application Support."
            )
        }
    }

    // MARK: Exportación de diagnóstico sin datos personales (SIS-4)

    public func construirReporteDeDiagnostico(
        entorno: EntornoDeDiagnostico = .actual()
    ) -> String {
        refrescar()
        return Self.construirReporteDeDiagnostico(
            entorno: entorno,
            ajustes: ajustes,
            estadosDePermisos: estadosDePermisos,
            diagnosticoDeBase: diagnosticoDeBase,
            estadoDeOpenCode: estadoDeOpenCode,
            modulos: diagnosticoDeModulos,
            conteos: conteosDeDiagnostico
        )
    }

    /// Función pura que construye el JSON de diagnóstico sin incluir nunca textos copiados, rutas del usuario,
    /// transcripciones, títulos de eventos o reuniones, ruta del vault ni nombres personales (SIS-4).
    public static func construirReporteDeDiagnostico(
        entorno: EntornoDeDiagnostico,
        ajustes: Ajustes,
        estadosDePermisos: [PermisoDelSistema: EstadoDePermiso],
        diagnosticoDeBase: DiagnosticoDeBase,
        estadoDeOpenCode: EstadoDeOpenCode,
        modulos: [DiagnosticoDeModulo],
        conteos: ConteosDeDiagnostico
    ) -> String {
        let permisos = PermisoDelSistema.allCases.map { permiso in
            PermisoExportado(
                id: permiso.id,
                estado: (estadosDePermisos[permiso] ?? .sinPedir).rawValue
            )
        }
        let modulosExportados = modulos.map { modulo in
            ModuloExportado(
                id: modulo.id,
                activo: modulo.activo,
                salud: Self.etiquetaSaludSinRutas(modulo.salud)
            )
        }
        let reporte = ReporteDeDiagnosticoExportado(
            entorno: entorno,
            baseDeDatosLista: diagnosticoDeBase.estaBien,
            openCodeInstalado: estadoDeOpenCode.estaListo,
            permisos: permisos,
            modulos: modulosExportados,
            ajustes: AjustesNoSensiblesExportados(
                estiloDeIsla: ajustes.estiloDeIsla.rawValue,
                vidrio: ajustes.vidrio.rawValue,
                temaPanel: ajustes.temaPanel.rawValue,
                temaBarra: ajustes.temaBarra.rawValue,
                pantalla: ajustes.pantalla.rawValue,
                atajo: ajustes.atajo.rawValue,
                iconoEnBarraDeMenus: ajustes.iconoEnBarraDeMenus,
                iniciarAlAbrirSesion: ajustes.iniciarAlAbrirSesion,
                hudSistemaActivo: ajustes.hudSistemaActivo,
                horasRetencionPortapapeles: ajustes.horasRetencionPortapapeles,
                limiteElementosPortapapeles: ajustes.limiteElementosPortapapeles,
                diasRetencionAudioReuniones: ajustes.diasRetencionAudioReuniones,
                guardarAudioReuniones: ajustes.guardarAudioReuniones,
                resumirReunionesEnInbox: ajustes.resumirReunionesEnInbox,
                separarVocesEnReuniones: ajustes.separarVocesEnReuniones,
                idiomaTranscripcionPorDefecto: ajustes.idiomaTranscripcionPorDefecto.rawValue,
                preferirMicrofonoInternoConBluetooth: ajustes.preferirMicrofonoInternoConBluetooth,
                accesosRapidos: ajustes.accesosRapidos
            ),
            conteos: conteos
        )
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let datos = try? codificador.encode(reporte),
            let texto = String(data: datos, encoding: .utf8)
        else {
            return "{}"
        }
        return texto
    }

    private static func etiquetaSaludSinRutas(_ salud: SaludDeModulo) -> String {
        switch salud {
        case .listo:
            "listo"
        case .faltaPermiso(let cual):
            "falta_permiso:\(cual)"
        case .error:
            "error"
        }
    }
}

private struct ReporteDeDiagnosticoExportado: Codable, Sendable {
    let entorno: EntornoDeDiagnostico
    let baseDeDatosLista: Bool
    let openCodeInstalado: Bool
    let permisos: [PermisoExportado]
    let modulos: [ModuloExportado]
    let ajustes: AjustesNoSensiblesExportados
    let conteos: ConteosDeDiagnostico
}

private struct PermisoExportado: Codable, Sendable {
    let id: String
    let estado: String
}

private struct ModuloExportado: Codable, Sendable {
    let id: String
    let activo: Bool
    let salud: String
}

private struct AjustesNoSensiblesExportados: Codable, Sendable {
    let estiloDeIsla: String
    let vidrio: String
    let temaPanel: String
    let temaBarra: String
    let pantalla: String
    let atajo: String
    let iconoEnBarraDeMenus: Bool
    let iniciarAlAbrirSesion: Bool
    let hudSistemaActivo: Bool
    let horasRetencionPortapapeles: Int
    let limiteElementosPortapapeles: Int
    let diasRetencionAudioReuniones: Int
    let guardarAudioReuniones: Bool
    let resumirReunionesEnInbox: Bool
    let separarVocesEnReuniones: Bool
    let idiomaTranscripcionPorDefecto: String
    let preferirMicrofonoInternoConBluetooth: Bool
    let accesosRapidos: [String]
}
