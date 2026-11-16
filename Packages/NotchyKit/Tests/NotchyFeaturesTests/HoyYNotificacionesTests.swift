import Foundation
import NotchyCore
import NotchyFeatures
import NotchyTestSupport
import Testing

@MainActor
struct HoyYNotificacionesTests {
    @Test func elPanelHoyIncluyePendientesDeHoyYAtrasados() async {
        let cal = ModeloDeAgenda.calendarioLunes
        let hoy = cal.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 16, minute: 0))!
        let ayer = cal.date(byAdding: .day, value: -1, to: hoy)!
        let manana = cal.date(byAdding: .day, value: 1, to: hoy)!
        let recordatorios = RecordatoriosFalso(
            permiso: .concedido,
            pendientes: [
                PendienteDeRecordatorios(id: "hoy", titulo: "Review and doubts", lista: "Obsidian", vencimiento: hoy),
                PendienteDeRecordatorios(id: "ayer", titulo: "Atrasado", lista: "Obsidian", vencimiento: ayer),
                PendienteDeRecordatorios(id: "manana", titulo: "Mañana", lista: "Obsidian", vencimiento: manana),
                PendienteDeRecordatorios(id: "sin", titulo: "Sin fecha", lista: "Obsidian"),
            ]
        )
        let modelo = ModeloDeAgenda(
            calendario: CalendarioFalso(permiso: .concedido, eventos: []),
            recordatorios: recordatorios,
            reloj: { hoy }
        )
        await modelo.recargar()
        #expect(modelo.pendientesDelDiaSeleccionado.map(\.id) == ["ayer", "hoy"])

        modelo.seleccionarDia(manana)
        #expect(modelo.pendientesDelDiaSeleccionado.map(\.id) == ["manana"])
    }

    @Test func lasNotificacionesDelSistemaRespetanDescartadasYLimpiar() async {
        let defaults = UserDefaults(suiteName: "notchy.pruebas.\(UUID().uuidString)")!
        let puerto = NotificacionesDelSistemaFalso(items: [
            NotificacionReciente(
                id: "nc-1", bundleId: "com.tinyspeck.slackmacgap", nombreApp: "Slack", titulo: "Hola", cuerpo: "a"),
            NotificacionReciente(
                id: "nc-2", bundleId: "com.apple.MobileSMS", nombreApp: "Mensajes", titulo: "Lebebe", cuerpo: "b"),
        ])
        let modelo = ModeloDeNotificaciones(sistema: puerto, defaults: defaults)
        #expect(modelo.notificaciones.isEmpty)

        await modelo.sincronizarConElSistema()
        #expect(Set(modelo.notificaciones.map(\.id)) == ["nc-1", "nc-2"])

        modelo.descartar("nc-1")
        await modelo.sincronizarConElSistema()
        #expect(modelo.notificaciones.map(\.id) == ["nc-2"])

        modelo.limpiarTodas()
        await modelo.sincronizarConElSistema()
        #expect(modelo.notificaciones.isEmpty)
    }

    @Test func sinAccesoAlDiscoSeAvisa() async {
        let defaults = UserDefaults(suiteName: "notchy.pruebas.\(UUID().uuidString)")!
        let modelo = ModeloDeNotificaciones(
            sistema: NotificacionesDelSistemaFalso(items: [], acceso: false), defaults: defaults)
        await modelo.sincronizarConElSistema()
        #expect(!modelo.accesoAlSistema)
    }
}

final class NotificacionesDelSistemaFalso: PuertoDeNotificacionesDelSistema {
    let items: [NotificacionReciente]
    let acceso: Bool

    init(items: [NotificacionReciente], acceso: Bool = true) {
        self.items = items
        self.acceso = acceso
    }

    func tieneAcceso() -> Bool { acceso }
    func recientes(limite: Int) async throws -> [NotificacionReciente] { Array(items.prefix(limite)) }
}
