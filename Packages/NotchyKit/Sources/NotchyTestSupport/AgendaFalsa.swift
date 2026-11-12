import Foundation
import NotchyCore

/// Falso de `PuertoDeCalendario` para pruebas deterministas de Agenda.
@MainActor
public final class CalendarioFalso: PuertoDeCalendario {
    public var permiso: EstadoDePermiso
    public var eventosDisponibles: [EventoDeCalendario]
    public private(set) var peticionesDePermiso = 0

    public init(
        permiso: EstadoDePermiso = .concedido,
        eventos: [EventoDeCalendario] = []
    ) {
        self.permiso = permiso
        self.eventosDisponibles = eventos
    }

    public func estadoDePermiso() -> EstadoDePermiso {
        permiso
    }

    public func pedirPermiso() async -> EstadoDePermiso {
        peticionesDePermiso += 1
        return permiso
    }

    public func eventos(desde: Date, hasta: Date) async throws -> [EventoDeCalendario] {
        guard permiso == .concedido else { return [] }
        return
            eventosDisponibles
            .filter { $0.fin >= desde && $0.inicio < hasta }
            .sorted { $0.inicio < $1.inicio }
    }
}

/// Falso de `PuertoDeRecordatorios` para pruebas deterministas de Agenda.
@MainActor
public final class RecordatoriosFalso: PuertoDeRecordatorios {
    public var permiso: EstadoDePermiso
    public var pendientes: [PendienteDeRecordatorios]
    public private(set) var peticionesDePermiso = 0
    public private(set) var completados: [String] = []

    public init(
        permiso: EstadoDePermiso = .concedido,
        pendientes: [PendienteDeRecordatorios] = []
    ) {
        self.permiso = permiso
        self.pendientes = pendientes
    }

    public func estadoDePermiso() -> EstadoDePermiso {
        permiso
    }

    public func pedirPermiso() async -> EstadoDePermiso {
        peticionesDePermiso += 1
        return permiso
    }

    public func pendientesIncompletos() async throws -> [PendienteDeRecordatorios] {
        guard permiso == .concedido else { return [] }
        return pendientes.filter { !$0.completado }
    }

    public func completar(id: String) async throws {
        completados.append(id)
        for indice in pendientes.indices where pendientes[indice].id == id {
            let anterior = pendientes[indice]
            pendientes[indice] = PendienteDeRecordatorios(
                id: anterior.id,
                titulo: anterior.titulo,
                lista: anterior.lista,
                vencimiento: anterior.vencimiento,
                completado: true
            )
        }
    }
}
