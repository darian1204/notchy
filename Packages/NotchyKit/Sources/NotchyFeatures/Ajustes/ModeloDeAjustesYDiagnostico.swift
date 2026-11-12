import Foundation
import NotchyCore
import NotchyStorage
import Observation

/// Modelo de vista para la ventana de Ajustes y el panel de Permisos y Diagnóstico (ISL-8, SIS-1, SIS-2).
@MainActor
@Observable
public final class ModeloDeAjustesYDiagnostico {
    public let ajustes: Ajustes
    public private(set) var modulosDisponibles: [IdentidadDeModulo]
    public private(set) var estadosDePermisos: [PermisoDelSistema: EstadoDePermiso] = [:]
    public private(set) var diagnosticoDeBase: DiagnosticoDeBase
    public private(set) var estadoDeOpenCode: EstadoDeOpenCode
    public private(set) var diagnosticoDeModulos: [DiagnosticoDeModulo] = []

    @ObservationIgnored private let proveedorDePermisos: any ProveedorDePermisos
    @ObservationIgnored private let consultarBase: @MainActor () -> DiagnosticoDeBase
    @ObservationIgnored private let consultarOpenCode: @MainActor () -> EstadoDeOpenCode
    @ObservationIgnored private let consultarModulos: @MainActor () -> [DiagnosticoDeModulo]
    @ObservationIgnored private let bus: BusDeEventos?

    public init(
        ajustes: Ajustes,
        modulosDisponibles: [IdentidadDeModulo] = [],
        proveedorDePermisos: any ProveedorDePermisos,
        consultarBase: @escaping @MainActor () -> DiagnosticoDeBase,
        consultarOpenCode: @escaping @MainActor () -> EstadoDeOpenCode,
        consultarModulos: @escaping @MainActor () -> [DiagnosticoDeModulo] = { [] },
        bus: BusDeEventos? = nil
    ) {
        self.ajustes = ajustes
        self.modulosDisponibles = modulosDisponibles
        self.proveedorDePermisos = proveedorDePermisos
        self.consultarBase = consultarBase
        self.consultarOpenCode = consultarOpenCode
        self.consultarModulos = consultarModulos
        self.bus = bus
        self.diagnosticoDeBase = consultarBase()
        self.estadoDeOpenCode = consultarOpenCode()
        refrescar()
    }

    /// Relee permisos, salud de la base, estado de OpenCode y módulos.
    public func refrescar() {
        var nuevos: [PermisoDelSistema: EstadoDePermiso] = [:]
        for permiso in PermisoDelSistema.allCases {
            nuevos[permiso] = proveedorDePermisos.estado(de: permiso)
        }
        estadosDePermisos = nuevos
        diagnosticoDeBase = consultarBase()
        estadoDeOpenCode = consultarOpenCode()
        diagnosticoDeModulos = consultarModulos()
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
            if !salud.integra { problemas.append("falló quick_check") }
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
}
