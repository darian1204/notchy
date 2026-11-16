import NotchyCore
import NotchyDesign
import SwiftUI

/// Módulo de Agenda: mini calendario del mes, eventos del día, pendientes con casilla y Dynamic Mac Notch Call UI (AGD-1 a AGD-4).
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

    public var orejaIzquierdaCompacta: AnyView? {
        guard modelo.llamadaActiva != nil else { return nil }
        return AnyView(
            HStack(spacing: 5) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x30D158))
                Text(modelo.duracionLlamadaFormateada)
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color(hex: 0x30D158))
            }
            .accessibilityLabel("Llamada activa \(modelo.duracionLlamadaFormateada)")
        )
    }

    public var orejaDerechaCompacta: AnyView? {
        guard modelo.llamadaActiva != nil else { return nil }
        return AnyView(
            EspectroDeAudio(
                niveles: modelo.nivelesOndaLlamada,
                alto: 13,
                reproduciendo: true,
                color: Color(hex: 0x30D158)
            )
            .accessibilityHidden(true)
        )
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
                        .font(.system(size: 10, weight: celda.esHoy ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(colorDeTexto(celda))
                    HStack(spacing: 2) {
                        if celda.punto.tieneEvento {
                            Circle()
                                .fill(celda.esHoy ? Color.black : Paleta.agenda)
                                .frame(width: 3.5, height: 3.5)
                        }
                        if celda.punto.tienePendiente {
                            Circle()
                                .fill(celda.esHoy ? Color.black : Paleta.portapapeles)
                                .frame(width: 3.5, height: 3.5)
                        }
                    }
                    .frame(height: 4)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .background(fondoDeCelda(celda))
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 20)
        }
    }

    private func colorDeTexto(_ celda: CeldaDeCalendario) -> Color {
        if celda.esHoy {
            return .black
        }
        if celda.esSeleccionado {
            return Paleta.texto
        }
        return Paleta.texto.opacity(0.85)
    }

    @ViewBuilder
    private func fondoDeCelda(_ celda: CeldaDeCalendario) -> some View {
        if celda.esHoy {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Paleta.agenda)
        } else if celda.esSeleccionado {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Paleta.agenda.opacity(0.8), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Paleta.superficieAlta)
                )
        } else {
            Color.clear
        }
    }

    private var panelEventos: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(modelo.tituloDelDiaSeleccionado.uppercased())
                        .rotulo(Paleta.agenda)
                    Spacer(minLength: 0)
                    if modelo.llamadaActiva != nil {
                        Button {
                            modelo.colgarLlamadaActiva()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "phone.down.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text(modelo.duracionLlamadaFormateada)
                                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(hex: 0xFF453A), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Colgar llamada activa")
                    } else {
                        Button {
                            Task { await modelo.simularAvisoDeLlamada() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Call UI")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(Color(hex: 0x30D158))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(hex: 0x30D158).opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Mostrar Dynamic Mac Notch Call UI")
                    }
                }
                if modelo.permisoCalendario != .concedido {
                    avisoDePermiso(permiso: .calendario, estado: modelo.permisoCalendario)
                } else if modelo.eventosDelDiaSeleccionado.isEmpty && modelo.pendientesDelDiaSeleccionado.isEmpty {
                    Spacer(minLength: 0)
                    Text("Sin eventos ni pendientes para este día").textoDeApoyo()
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(modelo.eventosDelDiaSeleccionado) { evento in
                                filaDeEvento(evento)
                            }
                            ForEach(modelo.pendientesDelDiaSeleccionado) { pendiente in
                                filaDePendiente(pendiente)
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
                    modelo.aceptarLlamada(evento)
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x30D158))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(hex: 0x30D158).opacity(0.18), in: Capsule())
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

/// Dynamic Mac Notch Call UI (`440 × 94 pt`, inspirado en FaceTime Dynamic Island).
struct VistaDeAvisoDeReunion: View {
    let modelo: ModeloDeAgenda

    var body: some View {
        VStack(spacing: 0) {
            // Orejas superiores estilo Call Dynamic Island: teléfono + duración a la izquierda, onda verde a la derecha
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x30D158))
                    Text(textoDeOrejaIzquierda)
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color(hex: 0x30D158))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: Medidas.notch.width)

                HStack {
                    Spacer(minLength: 0)
                    EspectroDeAudio(
                        niveles: modelo.nivelesOndaLlamada,
                        alto: 13,
                        reproduciendo: true,
                        color: Color(hex: 0x30D158)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, Medidas.margenLateral)
            .frame(height: Medidas.notch.height)

            if let evento = modelo.eventoEnAviso {
                HStack(spacing: 12) {
                    // Avatar circular del contacto o reunión
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: 0xFF9F0A), Color(hex: 0xFF375F)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text(iniciales(de: evento.titulo))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(subtitulo(para: evento))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Paleta.textoDeApoyo)
                            .lineLimit(1)
                        Text(evento.titulo)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Paleta.texto)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    // Botones circulares rojo (rechazar/colgar) y verde (aceptar/unirse)
                    HStack(spacing: 10) {
                        Button {
                            modelo.descartarAvisoDeLlamada()
                        } label: {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Color(hex: 0xFF453A), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Rechazar o cerrar llamada")
                        .accessibilityLabel("Rechazar o cerrar llamada")

                        Button {
                            modelo.aceptarLlamada(evento)
                        } label: {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Color(hex: 0x30D158), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Aceptar o unirse a la llamada")
                        .accessibilityLabel("Aceptar o unirse a la llamada")
                    }
                }
                .padding(.horizontal, Medidas.margenLateral + 4)
                .padding(.top, 2)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var textoDeOrejaIzquierda: String {
        if modelo.llamadaActiva != nil {
            return modelo.duracionLlamadaFormateada
        }
        guard let minutos = modelo.minutosParaAviso else { return "00:01" }
        return minutos <= 0 ? modelo.duracionLlamadaFormateada : "En \(minutos)m"
    }

    private func subtitulo(para evento: EventoDeCalendario) -> String {
        if let plataforma = evento.enlaceDeLlamada?.plataforma.nombreVisible {
            return "\(plataforma) · Llamada"
        }
        return "FaceTime Audio"
    }

    private func iniciales(de titulo: String) -> String {
        let palabras =
            titulo
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if palabras.count >= 2 {
            let primera = palabras[0].prefix(1)
            let segunda = palabras[1].prefix(1)
            return "\(primera)\(segunda)".uppercased()
        }
        return String(titulo.prefix(2)).uppercased()
    }
}
