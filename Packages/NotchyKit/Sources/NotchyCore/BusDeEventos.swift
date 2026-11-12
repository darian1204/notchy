import Foundation

/// Mensaje entre módulos. Los módulos no se llaman entre sí: publican y escuchan eventos.
public protocol Evento: Sendable {}

/// Bus de eventos con tipos. Cada suscripción recibe solo los eventos del tipo que pidió.
public actor BusDeEventos {
    private typealias Entrega = @Sendable (any Evento) -> Void
    private var suscriptores: [ObjectIdentifier: [UUID: Entrega]] = [:]

    public init() {}

    public func publicar(_ evento: some Evento) {
        guard let entregas = suscriptores[ObjectIdentifier(type(of: evento))] else { return }
        for entrega in entregas.values {
            entrega(evento)
        }
    }

    /// La suscripción queda activa cuando esta llamada regresa y termina al cancelar o soltar el flujo.
    /// Si el que escucha se atrasa, se conservan los 64 eventos más nuevos.
    public func suscribir<E: Evento>(a tipo: E.Type) -> AsyncStream<E> {
        let id = UUID()
        let clave = ObjectIdentifier(tipo)
        let (flujo, continuacion) = AsyncStream<E>.makeStream(bufferingPolicy: .bufferingNewest(64))
        suscriptores[clave, default: [:]][id] = { evento in
            if let evento = evento as? E {
                continuacion.yield(evento)
            }
        }
        continuacion.onTermination = { [weak self] _ in
            Task { await self?.quitar(id, de: clave) }
        }
        return flujo
    }

    public func cantidadDeSuscriptores<E: Evento>(de tipo: E.Type) -> Int {
        suscriptores[ObjectIdentifier(tipo)]?.count ?? 0
    }

    private func quitar(_ id: UUID, de clave: ObjectIdentifier) {
        suscriptores[clave]?[id] = nil
    }
}
