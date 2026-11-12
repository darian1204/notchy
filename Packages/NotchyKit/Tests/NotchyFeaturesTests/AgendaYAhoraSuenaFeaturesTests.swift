import Foundation
import NotchyCore
import NotchyFeatures
import NotchyTestSupport
import Testing

@MainActor
struct AgendaYAhoraSuenaFeaturesTests {
    @Test func puntosYCompletarPendiente() async {
        let cal = ModeloDeAgenda.calendarioLunes
        let hoy = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 10, minute: 0))!
        let diaEvento = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 14, minute: 0))!
        let diaPendiente = cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9, minute: 0))!

        let calendario = CalendarioFalso(
            permiso: .concedido,
            eventos: [
                EventoDeCalendario(
                    id: "ev-1",
                    titulo: "Clase de Sistemas Operativos",
                    inicio: hoy,
                    fin: hoy.addingTimeInterval(3600),
                    todoElDia: false,
                    calendario: "Clases"
                ),
                EventoDeCalendario(
                    id: "ev-2",
                    titulo: "Examen parcial",
                    inicio: diaEvento,
                    fin: diaEvento.addingTimeInterval(3600),
                    todoElDia: false,
                    calendario: "Clases"
                ),
            ]
        )
        let recordatorios = RecordatoriosFalso(
            permiso: .concedido,
            pendientes: [
                PendienteDeRecordatorios(
                    id: "rem-1",
                    titulo: "Entregar práctica 3",
                    lista: "Obsidian",
                    vencimiento: hoy
                ),
                PendienteDeRecordatorios(
                    id: "rem-2",
                    titulo: "Repasar apuntes",
                    lista: "Obsidian",
                    vencimiento: diaPendiente
                ),
            ]
        )

        let modelo = ModeloDeAgenda(
            calendario: calendario,
            recordatorios: recordatorios,
            reloj: { hoy }
        )
        await modelo.recargar()

        let puntos = modelo.puntosDelMes()
        #expect(puntos[12] == PuntoDelDia(tieneEvento: true, tienePendiente: true))
        #expect(puntos[15] == PuntoDelDia(tieneEvento: true, tienePendiente: false))
        #expect(puntos[18] == PuntoDelDia(tieneEvento: false, tienePendiente: true))

        await modelo.completarPendiente("rem-1")
        #expect(recordatorios.completados == ["rem-1"])
        #expect(modelo.pendientes.map(\.id) == ["rem-2"])
    }

    @Test func permisosAlAbrirYAvisoDeLlamada() async {
        let cal = ModeloDeAgenda.calendarioLunes
        let ahora = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 10, minute: 26))!
        let inicioReunion = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 10, minute: 30))!

        let enlace = EnlaceDeLlamada(
            plataforma: .googleMeet,
            url: URL(string: "https://meet.google.com/abc-defg-hij")!
        )
        let calendario = CalendarioFalso(
            permiso: .sinPedir,
            eventos: [
                EventoDeCalendario(
                    id: "ev-meet",
                    titulo: "Sync de producto",
                    inicio: inicioReunion,
                    fin: inicioReunion.addingTimeInterval(1800),
                    todoElDia: false,
                    calendario: "Trabajo",
                    enlaceDeLlamada: enlace
                )
            ]
        )
        let recordatorios = RecordatoriosFalso(permiso: .sinPedir)
        let bus = BusDeEventos()
        let flujoAvisos = await bus.suscribir(a: PeticionDeAvisoDeIsla.self)

        let modelo = ModeloDeAgenda(
            calendario: calendario,
            recordatorios: recordatorios,
            bus: bus,
            reloj: { ahora }
        )

        // Antes de abrir la Agenda no se piden permisos automáticamente.
        #expect(calendario.peticionesDePermiso == 0)
        #expect(recordatorios.peticionesDePermiso == 0)

        calendario.permiso = .sinPedir
        recordatorios.permiso = .sinPedir
        // Simulamos que al pedir permiso el usuario lo concede:
        await modelo.alAbrirAgenda()
        #expect(calendario.peticionesDePermiso == 1)
        #expect(recordatorios.peticionesDePermiso == 1)

        calendario.permiso = .concedido
        recordatorios.permiso = .concedido
        await modelo.recargar()

        #expect(modelo.eventoEnAviso?.id == "ev-meet")
        #expect(modelo.minutosParaAviso == 4)

        var iterator = flujoAvisos.makeAsyncIterator()
        let primerAviso = await iterator.next()
        #expect(primerAviso == PeticionDeAvisoDeIsla(modulo: "agenda"))

        // Recargar de nuevo con el mismo evento no vuelve a disparar el aviso.
        await modelo.recargar()
        #expect(modelo.eventoEnAviso?.id == "ev-meet")
    }

    @Test func ahoraSuenaCompactoYControles() async {
        let puerto = AhoraSuenaFalso()
        let bus = BusDeEventos()
        let flujoCompacto = await bus.suscribir(a: PeticionDeEstadoCompacto.self)

        let modelo = ModeloDeAhoraSuena(puerto: puerto, bus: bus)
        modelo.iniciar()
        #expect(puerto.activo == true)

        puerto.emitir(
            EstadoDeAhoraSuena(
                titulo: "Intro",
                artista: "The xx",
                appOrigen: "Música",
                reproduciendo: true
            ))

        var iterator = flujoCompacto.makeAsyncIterator()
        let peticionActiva = await iterator.next()
        #expect(peticionActiva == PeticionDeEstadoCompacto(modulo: "musica", prioridad: .musica))

        modelo.alternarReproduccion()
        modelo.siguiente()
        modelo.anterior()
        #expect(puerto.comandosEnviados == [.alternar, .siguiente, .anterior])

        puerto.emitir(
            EstadoDeAhoraSuena(
                titulo: "Intro",
                artista: "The xx",
                appOrigen: "Música",
                reproduciendo: false
            ))
        let peticionRetiro = await iterator.next()
        #expect(peticionRetiro == PeticionDeEstadoCompacto(modulo: "musica", prioridad: nil))
    }
}
