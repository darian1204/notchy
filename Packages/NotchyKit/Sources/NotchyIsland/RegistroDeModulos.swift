import NotchyCore
import Observation

/// Lista de módulos, cuáles están activos y en qué orden. Arranca y detiene según los ajustes (ISL-8).
@MainActor
@Observable
public final class RegistroDeModulos {
    /// Módulos activos, en el orden de los ajustes.
    public private(set) var activos: [any ModuloDeIsla] = []
    /// Todos los registrados, activos o no, en el orden de los ajustes. Para la pantalla de ajustes.
    public private(set) var todos: [any ModuloDeIsla] = []

    @ObservationIgnored public var alCambiar: (@MainActor () -> Void)?
    @ObservationIgnored private var registrados: [any ModuloDeIsla] = []
    @ObservationIgnored private var arrancados: Set<String> = []
    @ObservationIgnored public let ajustes: Ajustes

    public init(ajustes: Ajustes) {
        self.ajustes = ajustes
        ajustes.observar { [weak self] in self?.aplicar() }
    }

    public func registrar(_ modulo: any ModuloDeIsla) {
        guard !registrados.contains(where: { $0.identidad.id == modulo.identidad.id }) else { return }
        registrados.append(modulo)
        aplicar()
    }

    public func modulo(_ id: String) -> (any ModuloDeIsla)? {
        activos.first { $0.identidad.id == id }
    }

    /// Detiene todo. Se llama al salir de la app.
    public func detenerTodo() {
        for modulo in registrados where arrancados.remove(modulo.identidad.id) != nil {
            modulo.detener()
        }
    }

    private func aplicar() {
        let orden = ajustes.ordenar(registrados.map(\.identidad.id))
        todos = orden.compactMap { id in registrados.first { $0.identidad.id == id } }
        let nuevos = todos.filter { ajustes.estaActivo($0.identidad.id) }

        for modulo in todos {
            let id = modulo.identidad.id
            let activo = nuevos.contains { $0.identidad.id == id }
            if activo, arrancados.insert(id).inserted {
                modulo.arrancar()
            } else if !activo, arrancados.remove(id) != nil {
                modulo.detener()
            }
        }
        activos = nuevos
        alCambiar?()
    }
}
