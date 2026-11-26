import CoreGraphics
import NotchyCore
import NotchyDesign
import Observation

/// Une la máquina de estados con el mundo: programa los temporizadores, publica los cambios
/// y le dice a la vista qué dibujar.
@MainActor
@Observable
public final class CoordinadorDeIsla {
    public private(set) var estado: EstadoDeIsla = .reposo
    /// La pone el panel al leer la pantalla.
    public var geometria = GeometriaDeIsla()
    public let registro: RegistroDeModulos
    /// Color dominante de la carátula en reproducción (para el tema dinámico de panel o barra).
    public private(set) var hexCaratulaActual: UInt32?
    /// HUD efímero de volumen, brillo o batería que se muestra en las orejas compactas del notch.
    public private(set) var hudActual: EstadoDeHUDSistema?
    /// Estado de grabación activo para garantizar que nunca se oculte el indicador (GRB-6).
    public private(set) var grabacionActual: GrabacionCambiada?

    /// Acciones del menú del engrane. Las pone la aplicación.
    @ObservationIgnored public var alAbrirAjustes: (@MainActor () -> Void)?
    @ObservationIgnored public var alSalir: (@MainActor () -> Void)?
    @ObservationIgnored private var observadores: [@MainActor () -> Void] = []

    @ObservationIgnored private var maquina = MaquinaDeIsla()
    @ObservationIgnored private var temporizadores: [MaquinaDeIsla.Temporizador: Task<Void, Never>] = [:]
    @ObservationIgnored private var tareaHUD: Task<Void, Never>?
    @ObservationIgnored private var tareasDeBus: [Task<Void, Never>] = []
    @ObservationIgnored private let bus: BusDeEventos?
    @ObservationIgnored private let dormir: @Sendable (Duration) async throws -> Void

    public init(
        registro: RegistroDeModulos,
        bus: BusDeEventos? = nil,
        dormir: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.registro = registro
        self.bus = bus
        self.dormir = dormir
        registro.alCambiar = { [weak self] in self?.sincronizarModulos() }
        sincronizarModulos()
        suscribirAlBus()
    }

    public var moduloAbierto: (any ModuloDeIsla)? {
        guard case .expandido(let id) = estado else { return nil }
        return registro.modulo(id)
    }

    public var moduloCompacto: (any ModuloDeIsla)? {
        guard case .compacto(let peticion) = estado else { return nil }
        return registro.modulo(peticion.modulo)
    }

    public var moduloEnAviso: (any ModuloDeIsla)? {
        guard case .aviso(let id) = estado else { return nil }
        return registro.modulo(id)
    }

    /// El cursor está sobre una actividad compacta y las orejas se agrandan.
    public private(set) var asomando = false

    /// Qué ocupa las orejas con la isla cerrada.
    public enum ContenidoDeOrejas {
        case modulo(any ModuloDeIsla, ampliado: Bool)
        case breve(EstadoDeHUDSistema)
    }

    /// Qué va en la burbuja de la segunda actividad.
    public enum ContenidoDeBurbuja {
        case modulo(any ModuloDeIsla)
        case breve(EstadoDeHUDSistema)
    }

    /// La grabación nunca se oculta: con ella en las orejas, la actividad breve va a la burbuja.
    private var grabacionEnOrejas: Bool {
        guard case .compacto(let peticion) = estado else { return false }
        return peticion.prioridad == .grabando
    }

    private var moduloSecundario: (any ModuloDeIsla)? {
        maquina.secundaria.flatMap { registro.modulo($0.modulo) }
    }

    /// Las orejas con la isla en reposo o compacta. `nil` si no hay nada que mostrar.
    public var orejas: ContenidoDeOrejas? {
        switch estado {
        case .reposo, .compacto: break
        case .aviso, .expandido: return nil
        }
        if let hudActual, !grabacionEnOrejas { return .breve(hudActual) }
        guard let modulo = moduloCompacto else { return nil }
        return .modulo(modulo, ampliado: asomando && modulo.orejaIzquierdaAmpliada != nil)
    }

    /// La burbuja: la actividad que pierde las orejas o la segunda en prioridad.
    public var burbuja: ContenidoDeBurbuja? {
        switch estado {
        case .reposo, .compacto: break
        case .aviso, .expandido: return nil
        }
        if let hudActual {
            if grabacionEnOrejas { return .breve(hudActual) }
            if let modulo = moduloCompacto ?? moduloSecundario { return .modulo(modulo) }
            return nil
        }
        return moduloSecundario.map { .modulo($0) }
    }

    /// Ancho de cada oreja para lo que ocupa las orejas ahora.
    private var anchoDeOreja: CGFloat {
        switch orejas {
        case .breve: Medidas.orejaBreve
        case .modulo(let modulo, let ampliado): ampliado ? modulo.anchoDeOrejaAmpliada : modulo.anchoDeOreja
        case nil: Medidas.orejaCompacta
        }
    }

    /// Tamaño del cuerpo de la isla en el estado actual.
    public var tamano: CGSize {
        if estado == .reposo, hudActual != nil {
            return geometria.tamano(
                de: .compacto(PeticionCompacta(modulo: "hud", prioridad: .musica)),
                expandido: nil,
                anchoDeOreja: anchoDeOreja
            )
        }
        if case .compacto = estado {
            return geometria.tamano(de: estado, expandido: nil, anchoDeOreja: anchoDeOreja)
        }
        if case .expandido = estado, registro.ajustes.estiloDeIsla == .tarjetas {
            return geometria.tamanoEnTarjetas(expandido: moduloAbierto?.tamanoExpandido)
        }
        return geometria.tamano(de: estado, expandido: moduloAbierto?.tamanoExpandido)
    }

    /// Abierta sin el cursor encima (atajo o menú): quien registra atajos debe ofrecer Esc para cerrarla.
    public var abiertaSinCursor: Bool { maquina.abiertaSinCursor }

    /// Llama a `accion` después de cada cambio de estado. Para quien no es una vista (panel, atajos).
    public func observar(_ accion: @escaping @MainActor () -> Void) {
        observadores.append(accion)
    }

    /// Muestra una actividad breve; dura lo que diga su tipo salvo que se pida otra cosa.
    public func mostrarHUD(_ hud: EstadoDeHUDSistema, duracion: Duration? = nil) {
        let duracion = duracion ?? hud.tipo.duracion
        hudActual = hud
        tareaHUD?.cancel()
        let dormir = self.dormir
        tareaHUD = Task { [weak self] in
            guard (try? await dormir(duracion)) != nil, !Task.isCancelled else { return }
            self?.hudActual = nil
        }
    }

    public func recibir(_ entrada: MaquinaDeIsla.Entrada) {
        for efecto in maquina.recibir(entrada) {
            switch efecto {
            case .cancelar(let temporizador):
                temporizadores.removeValue(forKey: temporizador)?.cancel()
            case .programar(let temporizador, let espera):
                temporizadores[temporizador]?.cancel()
                temporizadores[temporizador] = Task { [weak self, dormir] in
                    guard (try? await dormir(espera)) != nil, !Task.isCancelled else { return }
                    self?.recibir(.vencio(temporizador))
                }
            }
        }
        if maquina.asomando != asomando { asomando = maquina.asomando }
        guard maquina.estado != estado else { return }
        estado = maquina.estado
        for accion in observadores {
            accion()
        }
        if let bus {
            let evento = IslaCambioDeEstado(moduloAbierto: moduloAbierto?.identidad.id)
            Task { await bus.publicar(evento) }
        }
    }

    private func sincronizarModulos() {
        recibir(.modulosDisponibles(registro.activos.map(\.identidad.id)))
    }

    private func suscribirAlBus() {
        guard let bus else { return }
        let tareaCompacto = Task { [weak self] in
            let flujo = await bus.suscribir(a: PeticionDeEstadoCompacto.self)
            for await peticion in flujo {
                guard let self else { break }
                if let prioridad = peticion.prioridad {
                    self.recibir(
                        .pedirCompacto(PeticionCompacta(modulo: peticion.modulo, prioridad: prioridad)))
                } else {
                    self.recibir(.retirarCompacto(modulo: peticion.modulo))
                }
            }
        }
        let tareaAviso = Task { [weak self] in
            let flujo = await bus.suscribir(a: PeticionDeAvisoDeIsla.self)
            for await aviso in flujo {
                guard let self else { break }
                self.recibir(.mostrarAviso(modulo: aviso.modulo))
            }
        }
        let tareaColorCaratula = Task { [weak self] in
            let flujo = await bus.suscribir(a: ColorDeCaratulaActualizado.self)
            for await cambio in flujo {
                guard let self else { break }
                self.hexCaratulaActual = cambio.hex
            }
        }
        let tareaGrabacion = Task { [weak self] in
            let flujo = await bus.suscribir(a: GrabacionCambiada.self)
            for await estado in flujo {
                guard let self else { break }
                self.grabacionActual = estado.activa ? estado : nil
            }
        }
        let tareaBreve = Task { [weak self] in
            let flujo = await bus.suscribir(a: ActividadBreveSolicitada.self)
            for await solicitud in flujo {
                guard let self else { break }
                self.mostrarHUD(solicitud.actividad)
            }
        }
        tareasDeBus = [tareaCompacto, tareaAviso, tareaColorCaratula, tareaGrabacion, tareaBreve]
    }
}
