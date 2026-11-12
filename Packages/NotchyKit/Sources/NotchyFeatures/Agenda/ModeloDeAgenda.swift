import Foundation
import NotchyCore
import OSLog
import Observation

/// Celda individual de la cuadrícula del mini calendario (AGD-2).
public struct CeldaDeCalendario: Identifiable, Sendable, Equatable {
    public let id: String
    public let dia: Int?
    public let fecha: Date?
    public let esHoy: Bool
    public let esSeleccionado: Bool
    public let punto: PuntoDelDia

    public init(
        id: String,
        dia: Int?,
        fecha: Date?,
        esHoy: Bool,
        esSeleccionado: Bool,
        punto: PuntoDelDia
    ) {
        self.id = id
        self.dia = dia
        self.fecha = fecha
        self.esHoy = esHoy
        self.esSeleccionado = esSeleccionado
        self.punto = punto
    }
}

/// Modelo observable del módulo de Agenda: mini calendario, eventos, pendientes y aviso 5 min antes (AGD-1 a AGD-4).
@MainActor
@Observable
public final class ModeloDeAgenda {
    public private(set) var permisoCalendario: EstadoDePermiso
    public private(set) var permisoRecordatorios: EstadoDePermiso
    public private(set) var mesVisible: Date
    public private(set) var diaSeleccionado: Date
    public private(set) var eventosDelMes: [EventoDeCalendario] = []
    public private(set) var pendientes: [PendienteDeRecordatorios] = []
    public private(set) var eventoEnAviso: EventoDeCalendario?
    public private(set) var minutosParaAviso: Int?
    public private(set) var mensajeDeError: String?

    @ObservationIgnored private let puertoCalendario: any PuertoDeCalendario
    @ObservationIgnored private let puertoRecordatorios: any PuertoDeRecordatorios
    @ObservationIgnored private let bus: BusDeEventos?
    @ObservationIgnored private let reloj: @Sendable () -> Date
    @ObservationIgnored private let alAbrirURL: (@MainActor (URL) -> Void)?
    @ObservationIgnored private var tareaVigilancia: Task<Void, Never>?
    @ObservationIgnored private var tareaEventosIsla: Task<Void, Never>?
    @ObservationIgnored private var observadorEventKit: NSObjectProtocol?
    @ObservationIgnored private var avisosEmitidos: Set<String> = []
    @ObservationIgnored private var yaPidioPermisosAlAbrir = false
    @ObservationIgnored private let log = Registro.de(.agenda)

    public static var calendarioLunes: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "es_MX")
        cal.firstWeekday = 2
        return cal
    }

    public init(
        calendario: any PuertoDeCalendario,
        recordatorios: any PuertoDeRecordatorios,
        bus: BusDeEventos? = nil,
        reloj: @escaping @Sendable () -> Date = { .now },
        alAbrirURL: (@MainActor (URL) -> Void)? = nil
    ) {
        self.puertoCalendario = calendario
        self.puertoRecordatorios = recordatorios
        self.bus = bus
        self.reloj = reloj
        self.alAbrirURL = alAbrirURL
        let ahora = reloj()
        let cal = Self.calendarioLunes
        self.permisoCalendario = calendario.estadoDePermiso()
        self.permisoRecordatorios = recordatorios.estadoDePermiso()
        self.diaSeleccionado = cal.startOfDay(for: ahora)
        self.mesVisible = Self.inicioDeMes(para: ahora, calendario: cal)
    }

    public var salud: SaludDeModulo {
        if permisoCalendario != .concedido {
            return .faltaPermiso(PermisoDelSistema.calendario.nombre)
        }
        if permisoRecordatorios != .concedido {
            return .faltaPermiso(PermisoDelSistema.recordatorios.nombre)
        }
        if let mensajeDeError {
            return .error(mensajeDeError)
        }
        return .listo
    }

    public func iniciar() {
        detener()
        actualizarEstadosDePermiso()
        if permisoCalendario == .concedido || permisoRecordatorios == .concedido {
            Task { await recargar() }
        }
        observadorEventKit = NotificationCenter.default.addObserver(
            forName: Notification.Name("EKEventStoreChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.recargar()
            }
        }
        tareaVigilancia = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { break }
                await self.recargar()
            }
        }
        if let bus {
            tareaEventosIsla = Task { [weak self] in
                let flujo = await bus.suscribir(a: IslaCambioDeEstado.self)
                for await cambio in flujo {
                    guard let self else { break }
                    if cambio.moduloAbierto == "agenda" {
                        await self.alAbrirAgenda()
                    }
                }
            }
        }
    }

    public func detener() {
        tareaVigilancia?.cancel()
        tareaVigilancia = nil
        tareaEventosIsla?.cancel()
        tareaEventosIsla = nil
        if let observadorEventKit {
            NotificationCenter.default.removeObserver(observadorEventKit)
            self.observadorEventKit = nil
        }
    }

    /// Pide permisos la primera vez que se abre la Agenda (Principio 4: permiso al usar).
    public func alAbrirAgenda() async {
        actualizarEstadosDePermiso()
        if !yaPidioPermisosAlAbrir,
            permisoCalendario == .sinPedir || permisoRecordatorios == .sinPedir
        {
            yaPidioPermisosAlAbrir = true
            await pedirPermisos()
        } else {
            await recargar()
        }
    }

    public func pedirPermisos() async {
        if puertoCalendario.estadoDePermiso() == .sinPedir {
            permisoCalendario = await puertoCalendario.pedirPermiso()
        } else {
            permisoCalendario = puertoCalendario.estadoDePermiso()
        }
        if puertoRecordatorios.estadoDePermiso() == .sinPedir {
            permisoRecordatorios = await puertoRecordatorios.pedirPermiso()
        } else {
            permisoRecordatorios = puertoRecordatorios.estadoDePermiso()
        }
        if let bus {
            await bus.publicar(
                CambioDePermiso(permiso: .calendario, estado: permisoCalendario))
            await bus.publicar(
                CambioDePermiso(permiso: .recordatorios, estado: permisoRecordatorios))
        }
        await recargar()
    }

    public func abrirAjustesDePermiso(_ permiso: PermisoDelSistema) {
        if let url = permiso.enlaceDeAjustesDelSistema { alAbrirURL?(url) }
    }

    public func unirseALlamada(_ enlace: EnlaceDeLlamada) {
        alAbrirURL?(enlace.url)
    }

    public func recargar() async {
        actualizarEstadosDePermiso()
        let cal = Self.calendarioLunes
        let inicioMes = Self.inicioDeMes(para: mesVisible, calendario: cal)
        let finMes = cal.date(byAdding: .month, value: 1, to: inicioMes) ?? inicioMes.addingTimeInterval(86_400 * 31)

        if permisoCalendario == .concedido {
            do {
                eventosDelMes = try await puertoCalendario.eventos(desde: inicioMes, hasta: finMes)
                mensajeDeError = nil
            } catch {
                log.error("No se pudieron leer eventos: \(error.localizedDescription, privacy: .public)")
                mensajeDeError = "No se pudo leer el Calendario"
            }
        } else {
            eventosDelMes = []
        }

        if permisoRecordatorios == .concedido {
            do {
                pendientes = try await puertoRecordatorios.pendientesIncompletos()
                mensajeDeError = nil
            } catch {
                log.error("No se pudieron leer recordatorios: \(error.localizedDescription, privacy: .public)")
                mensajeDeError = "No se pudieron leer Recordatorios"
            }
        } else {
            pendientes = []
        }

        await evaluarAvisosDeLlamada()
    }

    public func completarPendiente(_ id: String) async {
        do {
            try await puertoRecordatorios.completar(id: id)
            await recargar()
        } catch {
            log.error("No se pudo completar el pendiente: \(error.localizedDescription, privacy: .public)")
            mensajeDeError = "No se pudo completar el recordatorio"
        }
    }

    // MARK: Navegación del mini calendario

    public func seleccionarDia(_ fecha: Date) {
        let cal = Self.calendarioLunes
        diaSeleccionado = cal.startOfDay(for: fecha)
        mesVisible = Self.inicioDeMes(para: diaSeleccionado, calendario: cal)
    }

    public func irAHoy() async {
        let cal = Self.calendarioLunes
        let hoy = cal.startOfDay(for: reloj())
        diaSeleccionado = hoy
        mesVisible = Self.inicioDeMes(para: hoy, calendario: cal)
        await recargar()
    }

    public func cambiarMes(delta: Int) async {
        let cal = Self.calendarioLunes
        guard let nuevoMes = cal.date(byAdding: .month, value: delta, to: mesVisible) else { return }
        mesVisible = Self.inicioDeMes(para: nuevoMes, calendario: cal)
        let hoy = cal.startOfDay(for: reloj())
        if cal.isDate(hoy, equalTo: mesVisible, toGranularity: .month) {
            diaSeleccionado = hoy
        } else {
            diaSeleccionado = mesVisible
        }
        await recargar()
    }

    // MARK: Consultas derivadas

    public var tituloDelMesVisible: String {
        let formateador = DateFormatter()
        formateador.locale = Locale(identifier: "es_MX")
        formateador.dateFormat = "LLLL yyyy"
        return formateador.string(from: mesVisible).capitalized
    }

    public var esHoyElDiaSeleccionado: Bool {
        let cal = Self.calendarioLunes
        return cal.isDate(diaSeleccionado, inSameDayAs: reloj())
    }

    public var tituloDelDiaSeleccionado: String {
        if esHoyElDiaSeleccionado {
            return "Hoy"
        }
        let formateador = DateFormatter()
        formateador.locale = Locale(identifier: "es_MX")
        formateador.dateFormat = "EEE d MMM"
        return formateador.string(from: diaSeleccionado).capitalized
    }

    public var eventosDeHoy: [EventoDeCalendario] {
        eventos(en: reloj())
    }

    public var eventosDelDiaSeleccionado: [EventoDeCalendario] {
        eventos(en: diaSeleccionado)
    }

    public func eventos(en fecha: Date) -> [EventoDeCalendario] {
        let cal = Self.calendarioLunes
        let inicioDia = cal.startOfDay(for: fecha)
        guard let finDia = cal.date(byAdding: .day, value: 1, to: inicioDia) else { return [] }
        return eventosDelMes.filter { evento in
            evento.fin > inicioDia && evento.inicio < finDia
        }
    }

    /// Minutos restantes si el evento empieza dentro de los próximos 60 minutos (AGD-4).
    public func minutosRestantes(para evento: EventoDeCalendario) -> Int? {
        guard !evento.todoElDia else { return nil }
        let ahora = reloj()
        let diferencia = evento.inicio.timeIntervalSince(ahora)
        guard diferencia >= -60, diferencia <= 3600 else { return nil }
        return max(0, Int(ceil(diferencia / 60.0)))
    }

    /// Puntos por día del mes visible (`1...31`) para eventos y pendientes con fecha (AGD-2).
    public func puntosDelMes() -> [Int: PuntoDelDia] {
        let cal = Self.calendarioLunes
        guard let rangoDias = cal.range(of: .day, in: .month, for: mesVisible) else { return [:] }
        var resultado: [Int: PuntoDelDia] = [:]

        for dia in rangoDias {
            guard let fechaDia = cal.date(bySetting: .day, value: dia, of: mesVisible) else { continue }
            let inicioDia = cal.startOfDay(for: fechaDia)
            guard let finDia = cal.date(byAdding: .day, value: 1, to: inicioDia) else { continue }

            let hayEvento = eventosDelMes.contains { $0.fin > inicioDia && $0.inicio < finDia }
            let hayPendiente = pendientes.contains { pendiente in
                guard !pendiente.completado, let vencimiento = pendiente.vencimiento else { return false }
                return cal.isDate(vencimiento, inSameDayAs: inicioDia)
            }
            if hayEvento || hayPendiente {
                resultado[dia] = PuntoDelDia(tieneEvento: hayEvento, tienePendiente: hayPendiente)
            }
        }
        return resultado
    }

    /// Celdas listas para dibujar la cuadrícula `L M M J V S D` del mes visible.
    public func celdasDelMes() -> [CeldaDeCalendario] {
        let cal = Self.calendarioLunes
        let inicioMes = Self.inicioDeMes(para: mesVisible, calendario: cal)
        guard let rangoDias = cal.range(of: .day, in: .month, for: inicioMes) else { return [] }
        let diaSemanaPrimero = cal.component(.weekday, from: inicioMes)
        // En calendario gregoriano: domingo = 1, lunes = 2 ... sábado = 7.
        // Desplazamiento desde lunes (0 a 6):
        let desplazamiento = (diaSemanaPrimero + 5) % 7
        let puntos = puntosDelMes()
        let hoy = cal.startOfDay(for: reloj())

        var celdas: [CeldaDeCalendario] = []
        for vacio in 0..<desplazamiento {
            celdas.append(
                CeldaDeCalendario(
                    id: "vacio-\(vacio)",
                    dia: nil,
                    fecha: nil,
                    esHoy: false,
                    esSeleccionado: false,
                    punto: PuntoDelDia()
                ))
        }
        for dia in rangoDias {
            let fecha = cal.date(byAdding: .day, value: dia - 1, to: inicioMes)
            let inicioDia = fecha.map { cal.startOfDay(for: $0) }
            let esHoy = inicioDia.map { cal.isDate($0, inSameDayAs: hoy) } ?? false
            let esSeleccionado = inicioDia.map { cal.isDate($0, inSameDayAs: diaSeleccionado) } ?? false
            celdas.append(
                CeldaDeCalendario(
                    id: "dia-\(dia)",
                    dia: dia,
                    fecha: inicioDia,
                    esHoy: esHoy,
                    esSeleccionado: esSeleccionado,
                    punto: puntos[dia] ?? PuntoDelDia()
                ))
        }
        return celdas
    }

    // MARK: Aviso 5 minutos antes (AGD-4)

    private func evaluarAvisosDeLlamada() async {
        let ahora = reloj()
        let proximo = eventosDeHoy.first { evento in
            guard !evento.todoElDia, evento.enlaceDeLlamada != nil else { return false }
            let segundos = evento.inicio.timeIntervalSince(ahora)
            return segundos >= -60 && segundos <= 5 * 60
        }
        guard let proximo else { return }
        let minutos = max(0, Int(ceil(proximo.inicio.timeIntervalSince(ahora) / 60.0)))
        eventoEnAviso = proximo
        minutosParaAviso = minutos

        guard !avisosEmitidos.contains(proximo.id) else { return }
        avisosEmitidos.insert(proximo.id)
        if let bus {
            await bus.publicar(ReunionProximaDetectada(evento: proximo, minutosRestantes: minutos))
            await bus.publicar(PeticionDeAvisoDeIsla(modulo: "agenda"))
        }
    }

    private func actualizarEstadosDePermiso() {
        permisoCalendario = puertoCalendario.estadoDePermiso()
        permisoRecordatorios = puertoRecordatorios.estadoDePermiso()
    }

    private static func inicioDeMes(para fecha: Date, calendario: Calendar) -> Date {
        let componentes = calendario.dateComponents([.year, .month], from: fecha)
        return calendario.date(from: componentes) ?? calendario.startOfDay(for: fecha)
    }
}
