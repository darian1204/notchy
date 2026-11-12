import EventKit
import Foundation
import NotchyCore

/// Adaptador real de Calendario usando `EventKit` (AGD-1, AGD-4).
@MainActor
public final class AdaptadorDeCalendarioEventKit: PuertoDeCalendario {
    private let almacen: EKEventStore

    public init(almacen: EKEventStore = EKEventStore()) {
        self.almacen = almacen
    }

    public func estadoDePermiso() -> EstadoDePermiso {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .sinPedir
        case .fullAccess, .authorized: .concedido
        case .writeOnly, .denied: .denegado
        case .restricted: .restringido
        @unknown default: .denegado
        }
    }

    public func pedirPermiso() async -> EstadoDePermiso {
        _ = try? await almacen.requestFullAccessToEvents()
        return estadoDePermiso()
    }

    public func eventos(desde: Date, hasta: Date) async throws -> [EventoDeCalendario] {
        guard estadoDePermiso() == .concedido else { return [] }
        let predicado = almacen.predicateForEvents(withStart: desde, end: hasta, calendars: nil)
        let encontrados = almacen.events(matching: predicado)
        return
            encontrados
            .sorted { $0.startDate < $1.startDate }
            .map { evento in
                let enlace = EnlaceDeLlamada.detectar(en: [
                    evento.url?.absoluteString,
                    evento.location,
                    evento.notes,
                ])
                let identificador =
                    evento.eventIdentifier
                    ?? "\(evento.title ?? "evento")-\( Int(evento.startDate.timeIntervalSince1970) )"
                return EventoDeCalendario(
                    id: "\(identificador)-\(Int(evento.startDate.timeIntervalSince1970))",
                    titulo: (evento.title?.isEmpty == false) ? evento.title! : "Sin título",
                    inicio: evento.startDate,
                    fin: evento.endDate,
                    todoElDia: evento.isAllDay,
                    calendario: evento.calendar.title,
                    ubicacion: evento.location,
                    enlaceDeLlamada: enlace
                )
            }
    }
}
