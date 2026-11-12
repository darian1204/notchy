import NotchyCore
import NotchyDesign
import SwiftUI

/// Módulo de Agenda: mini calendario del mes, eventos del día, pendientes con casilla y aviso de llamada (AGD-1 a AGD-4).
@MainActor
public final class ModuloDeAgenda: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "agenda",
        nombre: "Agenda",
        icono: "calendar",
        color: Paleta.hexAgenda,
        lado: .izquierda
    )
    public let tamanoExpandido = Medidas.agenda
    public let modelo: ModeloDeAgenda

    public init(modelo: ModeloDeAgenda) {
        self.modelo = modelo
    }

    public var salud: SaludDeModulo {
        modelo.salud
    }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeAgenda(modelo: modelo))
    }

    public var vistaDeAviso: AnyView? {
        AnyView(VistaDeAvisoDeReunion(modelo: modelo))
    }

    public func arrancar() {
        modelo.iniciar()
    }

    public func detener() {
        modelo.detener()
    }
}

struct VistaDeAgenda: View {
    let modelo: ModeloDeAgenda
    private let columnas = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let diasSemana = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        HStack(spacing: 10) {
            panelMiniCalendario
                .frame(width: 232)
            VStack(spacing: 8) {
                panelEventos
                panelPendientes
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await modelo.alAbrirAgenda()
        }
    }

    private var panelMiniCalendario: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(modelo.tituloDelMesVisible)
                        .rotulo(Paleta.textoDeApoyo)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        Task { await modelo.cambiarMes(delta: -1) }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Paleta.textoDeApoyo)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mes anterior")

                    Button {
                        Task { await modelo.irAHoy() }
                    } label: {
                        Text("Hoy")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Paleta.agenda)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ir a hoy")

                    Button {
                        Task { await modelo.cambiarMes(delta: 1) }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Paleta.textoDeApoyo)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mes siguiente")
                }

                LazyVGrid(columns: columnas, spacing: 2) {
                    ForEach(Array(diasSemana.enumerated()), id: \.offset) { _, inicial in
                        Text(inicial)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Paleta.textoDeApoyo)
                            .frame(height: 14)
                    }
                    ForEach(modelo.celdasDelMes()) { celda in
                        celdaDeDia(celda)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func celdaDeDia(_ celda: CeldaDeCalendario) -> some View {
        if let dia = celda.dia, let fecha = celda.fecha {
            Button {
                modelo.seleccionarDia(fecha)
            } label: {
                VStack(spacing: 1) {
                    Text("\(dia)")
                        .font(.system(size: 11, weight: celda.esHoy ? .bold : .regular).monospacedDigit())
                        .foregroundStyle(celda.esHoy ? Paleta.fondo : Paleta.texto)
                    HStack(spacing: 2) {
                        if celda.punto.tieneEvento {
                            Circle()
                                .fill(celda.esHoy ? Paleta.fondo : Paleta.agenda)
                                .frame(width: 3, height: 3)
                        }
                        if celda.punto.tienePendiente {
                            Circle()
                                .fill(Paleta.portapapeles)
                                .frame(width: 3, height: 3)
                        }
                    }
                    .frame(height: 3)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .background(
                    celda.esHoy
                        ? Paleta.texto
                        : (celda.esSeleccionado ? Paleta.superficieAlta : Color.clear),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Día \(dia)")
        } else {
            Color.clear.frame(height: 18)
        }
    }

    private var panelEventos: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 4) {
                Text(modelo.tituloDelDiaSeleccionado.uppercased())
                    .rotulo(Paleta.agenda)
                if modelo.permisoCalendario != .concedido {
                    avisoDePermiso(permiso: .calendario, estado: modelo.permisoCalendario)
                } else if modelo.eventosDelDiaSeleccionado.isEmpty {
                    Spacer(minLength: 0)
                    Text("Sin eventos programados").textoDeApoyo()
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(modelo.eventosDelDiaSeleccionado) { evento in
                                filaDeEvento(evento)
                            }
                        }
                    }
                }
            }
        }
    }

    private func filaDeEvento(_ evento: EventoDeCalendario) -> some View {
        HStack(spacing: 8) {
            Text(horaFormateada(evento))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Paleta.textoDeApoyo)
                .frame(width: 42, alignment: .leading)
            Text(evento.titulo)
                .textoDeCuerpo()
                .lineLimit(1)
            Spacer(minLength: 0)
            if let minutos = modelo.minutosRestantes(para: evento) {
                Text(minutos == 0 ? "ahora" : "en \(minutos) min")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Paleta.agenda)
            }
            if let enlace = evento.enlaceDeLlamada {
                Button {
                    modelo.unirseALlamada(enlace)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Paleta.agenda)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Paleta.superficieAlta, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Unirse a \(enlace.plataforma.nombreVisible)")
                .accessibilityLabel("Unirse a \(enlace.plataforma.nombreVisible)")
            }
        }
    }

    private var panelPendientes: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 4) {
                Text("PENDIENTES")
                    .rotulo(Paleta.portapapeles)
                if modelo.permisoRecordatorios != .concedido {
                    avisoDePermiso(permiso: .recordatorios, estado: modelo.permisoRecordatorios)
                } else if modelo.pendientes.isEmpty {
                    Spacer(minLength: 0)
                    Text("Sin pendientes en Recordatorios").textoDeApoyo()
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(modelo.pendientes.prefix(12)) { pendiente in
                                filaDePendiente(pendiente)
                            }
                        }
                    }
                }
            }
        }
    }

    private func filaDePendiente(_ pendiente: PendienteDeRecordatorios) -> some View {
        Button {
            Task { await modelo.completarPendiente(pendiente.id) }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(Paleta.textoDeApoyo, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                Text(pendiente.titulo)
                    .textoDeCuerpo()
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(etiquetaDePendiente(pendiente))
                    .font(.system(size: 11))
                    .foregroundStyle(Paleta.portapapeles)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Completar \(pendiente.titulo)")
    }

    private func avisoDePermiso(permiso: PermisoDelSistema, estado: EstadoDePermiso) -> some View {
        HStack(spacing: 8) {
            Text(
                estado == .sinPedir ? "Requiere permiso de \(permiso.nombre)" : "Permiso de \(permiso.nombre) denegado"
            )
            .textoDeApoyo()
            .lineLimit(1)
            Spacer(minLength: 0)
            if estado == .sinPedir {
                Button("Permitir") {
                    Task { await modelo.pedirPermisos() }
                }
                .buttonStyle(EstiloDePildora(destacado: true))
            } else {
                Button("Ajustes…") {
                    modelo.abrirAjustesDePermiso(permiso)
                }
                .buttonStyle(EstiloDePildora())
            }
        }
    }

    private func horaFormateada(_ evento: EventoDeCalendario) -> String {
        if evento.todoElDia {
            return "Todo"
        }
        let formateador = DateFormatter()
        formateador.locale = Locale(identifier: "es_MX")
        formateador.dateFormat = "HH:mm"
        return formateador.string(from: evento.inicio)
    }

    private func etiquetaDePendiente(_ pendiente: PendienteDeRecordatorios) -> String {
        if let vencimiento = pendiente.vencimiento {
            let cal = ModeloDeAgenda.calendarioLunes
            if cal.isDateInToday(vencimiento) {
                return "hoy"
            }
            let formateador = DateFormatter()
            formateador.locale = Locale(identifier: "es_MX")
            formateador.dateFormat = "EEE d"
            return formateador.string(from: vencimiento).lowercased()
        }
        return pendiente.lista
    }
}

/// Vista del aviso automático 5 minutos antes de una reunión con videollamada (`440 × 82 pt`, AGD-4).
struct VistaDeAvisoDeReunion: View {
    let modelo: ModeloDeAgenda

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Paleta.agenda)
                    Text(textoDeMinutos)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Paleta.texto)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: Medidas.notch.width)

                Color.clear.frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Medidas.margenLateral)
            .frame(height: Medidas.notch.height)

            if let evento = modelo.eventoEnAviso {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(evento.titulo)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Paleta.texto)
                            .lineLimit(1)
                        Text(subtitulo(para: evento))
                            .textoDeApoyo()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let enlace = evento.enlaceDeLlamada {
                        Button("Unirme") {
                            modelo.unirseALlamada(enlace)
                        }
                        .buttonStyle(EstiloDePildora(destacado: true))
                    }
                }
                .padding(.horizontal, Medidas.margenLateral + 2)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var textoDeMinutos: String {
        guard let minutos = modelo.minutosParaAviso else { return "Próxima" }
        return minutos <= 0 ? "Ahora" : "En \(minutos) min"
    }

    private func subtitulo(para evento: EventoDeCalendario) -> String {
        let formateador = DateFormatter()
        formateador.locale = Locale(identifier: "es_MX")
        formateador.dateFormat = "HH:mm"
        let hora = formateador.string(from: evento.inicio)
        if let plataforma = evento.enlaceDeLlamada?.plataforma.nombreVisible {
            return "\(hora) · \(plataforma)"
        }
        return hora
    }
}
