import EventKit
import Foundation
import NotchyCore

/// Adaptador real de Recordatorios usando `EventKit` (AGD-3).
/// Prioriza la lista `"Obsidian"` comprobada en S10 y permite marcar pendientes como completados.
@MainActor
public final class AdaptadorDeRecordatoriosEventKit: PuertoDeRecordatorios {
    private let almacen: EKEventStore

    public init(almacen: EKEventStore = EKEventStore()) {
        self.almacen = almacen
    }

    public func estadoDePermiso() -> EstadoDePermiso {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: .sinPedir
        case .fullAccess, .authorized: .concedido
        case .writeOnly, .denied: .denegado
        case .restricted: .restringido
        @unknown default: .denegado
        }
    }

    public func pedirPermiso() async -> EstadoDePermiso {
        _ = try? await almacen.requestFullAccessToReminders()
        return estadoDePermiso()
    }

    public func pendientesIncompletos() async throws -> [PendienteDeRecordatorios] {
        guard estadoDePermiso() == .concedido else { return [] }
        let predicado = almacen.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        let recordatorios: [EKReminder] = await withCheckedContinuation { continuacion in
            almacen.fetchReminders(matching: predicado) { resultado in
                nonisolated(unsafe) let lista = resultado ?? []
                continuacion.resume(returning: lista)
            }
        }
        let calendario = Calendar.current
        let convertidos = recordatorios.map { recordatorio -> PendienteDeRecordatorios in
            let fecha = recordatorio.dueDateComponents.flatMap { calendario.date(from: $0) }
            return PendienteDeRecordatorios(
                id: recordatorio.calendarItemIdentifier,
                titulo: recordatorio.title ?? "Sin título",
                lista: recordatorio.calendar?.title ?? "Recordatorios",
                vencimiento: fecha,
                completado: recordatorio.isCompleted
            )
        }
        return convertidos.sorted { izquierda, derecha in
            let izqObsidian = izquierda.lista.localizedCaseInsensitiveCompare("Obsidian") == .orderedSame
            let derObsidian = derecha.lista.localizedCaseInsensitiveCompare("Obsidian") == .orderedSame
            if izqObsidian != derObsidian { return izqObsidian }
            switch (izquierda.vencimiento, derecha.vencimiento) {
            case (let f1?, let f2?):
                if f1 != f2 { return f1 < f2 }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return izquierda.titulo.localizedStandardCompare(derecha.titulo) == .orderedAscending
        }
    }

    public func completar(id: String) async throws {
        guard let item = almacen.calendarItem(withIdentifier: id) as? EKReminder else {
            throw NotchyError.datos("No se encontró el recordatorio solicitado")
        }
        item.isCompleted = true
        item.completionDate = .now
        try almacen.save(item, commit: true)
    }
}
