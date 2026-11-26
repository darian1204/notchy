import NotchyCore

/// Lo que la isla muestra en un momento dado.
public enum EstadoDeIsla: Equatable, Sendable {
    /// Solo el notch (o la píldora sin notch).
    case reposo
    /// Orejas a los lados del notch con el estado de un módulo.
    case compacto(PeticionCompacta)
    /// Aviso que se abre solo unos segundos.
    case aviso(modulo: String)
    case expandido(modulo: String)
}

/// Reglas de la isla, sin ventanas ni relojes: recibe entradas y contesta con el estado nuevo
/// y los temporizadores que hay que programar o cancelar. Así se prueba completa.
public struct MaquinaDeIsla: Sendable {
    public enum Temporizador: Hashable, Sendable, CaseIterable {
        case abrir, cerrar, aviso
        /// Olvida el último módulo abierto y vuelve al de por defecto.
        case olvidar
    }

    public enum Efecto: Equatable, Sendable {
        case programar(Temporizador, Duration)
        case cancelar(Temporizador)
    }

    public enum Entrada: Equatable, Sendable {
        case cursorEntro
        case cursorSalio
        case vencio(Temporizador)
        case clicFuera
        case escape
        /// Atajo global: abre si está cerrada y cierra si está abierta.
        case atajo
        case elegirModulo(String)
        case pedirCompacto(PeticionCompacta)
        case retirarCompacto(modulo: String)
        case mostrarAviso(modulo: String)
        /// Los módulos activos, en orden. Cambia con los ajustes.
        case modulosDisponibles([String])
    }

    public static let retardoAlAbrir: Duration = .milliseconds(120)
    public static let retardoAlCerrar: Duration = .milliseconds(350)
    /// Retardo especial para el espejo: permanece 2 segundos abierto al perder el cursor.
    public static let retardoAlCerrarEspejo: Duration = .seconds(2)
    public static let duracionDelAviso: Duration = .seconds(6)
    /// Tiempo que la isla recuerda el último módulo al cerrarse. Si se reabre antes, vuelve a él.
    public static let memoriaDelUltimoModulo: Duration = .seconds(10)
    /// El módulo que abre el hover cuando está activo.
    public static let moduloDeInicio = ModulosBase.inicio

    public private(set) var modulos: [String] = []
    public private(set) var cursorDentro = false
    /// Abierta con el atajo o desde un menú: no depende del cursor, así que Esc debe poder cerrarla.
    public private(set) var abiertaSinCursor = false
    private var expandido: String?
    /// Último módulo abierto, recordado durante `memoriaDelUltimoModulo` tras cerrar.
    private var recordado: String?
    private var peticiones: [PeticionCompacta] = []
    private var aviso: String?

    public init() {}

    public var estado: EstadoDeIsla {
        if let expandido {
            return .expandido(modulo: expandido)
        }
        if let aviso {
            return .aviso(modulo: aviso)
        }
        if let peticion = peticiones.max(by: { $0.prioridad < $1.prioridad }) {
            return .compacto(peticion)
        }
        return .reposo
    }

    public mutating func recibir(_ entrada: Entrada) -> [Efecto] {
        switch entrada {
        case .cursorEntro:
            cursorDentro = true
            if expandido != nil {
                abiertaSinCursor = false
                return [.cancelar(.cerrar)]
            }
            return modulos.isEmpty ? [] : [.cancelar(.cerrar), .programar(.abrir, Self.retardoAlAbrir)]

        case .cursorSalio:
            cursorDentro = false
            guard let expandido else {
                return [.cancelar(.abrir)]
            }
            let espera = expandido == "espejo" ? Self.retardoAlCerrarEspejo : Self.retardoAlCerrar
            return [.cancelar(.abrir), .programar(.cerrar, espera)]

        case .vencio(.abrir):
            guard cursorDentro, expandido == nil else { return [] }
            abrir(moduloAlAbrir, sinCursor: false)
            return [.cancelar(.olvidar)]

        case .vencio(.cerrar):
            return cursorDentro ? [] : cerrar()

        case .vencio(.aviso):
            aviso = nil
            return []

        case .vencio(.olvidar):
            recordado = nil
            return []

        case .clicFuera, .escape:
            return cerrar()

        case .atajo:
            if expandido != nil {
                return cerrar()
            }
            abrir(moduloAlAbrir, sinCursor: !cursorDentro)
            return [.cancelar(.abrir), .cancelar(.olvidar)]

        case .elegirModulo(let id):
            guard modulos.contains(id) else { return [] }
            if expandido == nil {
                abrir(id, sinCursor: !cursorDentro)
                recordado = nil
                return [.cancelar(.olvidar)]
            } else {
                expandido = id
            }
            return [.cancelar(.abrir), .cancelar(.cerrar)]

        case .pedirCompacto(let peticion):
            peticiones.removeAll { $0.modulo == peticion.modulo }
            peticiones.append(peticion)
            return []

        case .retirarCompacto(let modulo):
            peticiones.removeAll { $0.modulo == modulo }
            return []

        case .mostrarAviso(let modulo):
            aviso = modulo
            return [.programar(.aviso, Self.duracionDelAviso)]

        case .modulosDisponibles(let nuevos):
            modulos = nuevos
            peticiones.removeAll { !nuevos.contains($0.modulo) }
            if let recordado, !nuevos.contains(recordado) {
                self.recordado = nil
            }
            if let aviso, !nuevos.contains(aviso) {
                self.aviso = nil
            }
            guard let abierto = expandido, !nuevos.contains(abierto) else { return [] }
            guard let reemplazo = moduloPorDefecto else { return cerrar() }
            expandido = reemplazo
            return []
        }
    }

    private var moduloPorDefecto: String? {
        modulos.contains(Self.moduloDeInicio) ? Self.moduloDeInicio : modulos.first
    }

    /// Al reabrir antes de que venza la memoria, el último módulo; si no, el de por defecto.
    private var moduloAlAbrir: String? {
        if let recordado, modulos.contains(recordado) { return recordado }
        return moduloPorDefecto
    }

    private mutating func abrir(_ modulo: String?, sinCursor: Bool) {
        guard let modulo else { return }
        expandido = modulo
        abiertaSinCursor = sinCursor
    }

    private mutating func cerrar() -> [Efecto] {
        guard let abierto = expandido else {
            abiertaSinCursor = false
            return [.cancelar(.abrir), .cancelar(.cerrar)]
        }
        expandido = nil
        abiertaSinCursor = false
        recordado = abierto == moduloPorDefecto ? nil : abierto
        return [.cancelar(.abrir), .cancelar(.cerrar), .programar(.olvidar, Self.memoriaDelUltimoModulo)]
    }
}
