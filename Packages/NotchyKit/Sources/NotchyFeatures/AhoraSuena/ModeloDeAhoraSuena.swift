import Foundation
import NotchyCore
import Observation

/// Modelo observable del módulo Ahora suena (MUS-1, D-18).
@MainActor
@Observable
public final class ModeloDeAhoraSuena {
    public private(set) var estadoActual: EstadoDeAhoraSuena?
    @ObservationIgnored private let puerto: any PuertoDeAhoraSuena
    @ObservationIgnored private let bus: BusDeEventos?
    @ObservationIgnored private var pidioCompacto = false

    public init(puerto: any PuertoDeAhoraSuena, bus: BusDeEventos? = nil) {
        self.puerto = puerto
        self.bus = bus
    }

    public var salud: SaludDeModulo {
        .listo
    }

    public func iniciar() {
        puerto.iniciar { [weak self] nuevo in
            self?.actualizar(nuevo)
        }
    }

    public func detener() {
        puerto.detener()
        actualizar(nil)
    }

    public func alternarReproduccion() {
        puerto.enviar(.alternar)
    }

    public func siguiente() {
        puerto.enviar(.siguiente)
    }

    public func anterior() {
        puerto.enviar(.anterior)
    }

    private func actualizar(_ nuevo: EstadoDeAhoraSuena?) {
        let cambioRelevante = estadoActual != nuevo
        estadoActual = nuevo
        let debeMostrarCompacto = (nuevo?.reproduciendo == true)
        if debeMostrarCompacto != pidioCompacto {
            pidioCompacto = debeMostrarCompacto
            if let bus {
                let peticion = PeticionDeEstadoCompacto(
                    modulo: "musica",
                    prioridad: debeMostrarCompacto ? .musica : nil
                )
                Task { await bus.publicar(peticion) }
            }
        }
        if cambioRelevante, let bus {
            Task { await bus.publicar(CambioDeAhoraSuena(estado: nuevo)) }
        }
    }
}
