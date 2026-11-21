import AppKit
import NotchyCore
import NotchyDesign
import SwiftUI
import UniformTypeIdentifiers

/// Datos que el Inicio en estilo tarjetas lee de otros módulos. Todo es opcional: sin un modelo,
/// su parte se muestra vacía en vez de romper.
@MainActor
struct FuentesDeInicioTarjetas {
    var agenda: ModeloDeAgenda?
    var ahoraSuena: ModeloDeAhoraSuena?
    var portapapeles: ModeloDePortapapeles?
    var bandeja: ModeloDeBandeja?
    var airdrop: ModeloDeAirDrop?
    var inbox: GestorDeInboxObsidian?
    var clima: ModeloDeClima?
    var screenTime: ModeloDeScreenTime?
    var monitor: ModeloDeMonitorSistema?
    var grabadora: ModeloDeGrabadora?
    var ajustes: Ajustes?
    var modulosDisponibles: (@MainActor () -> [IdentidadDeModulo])?
    var alAbrirModulo: (@MainActor (String) -> Void)?
}

/// Inicio del estilo tarjetas: música con franja de estado, inbox con chips, bandeja y 3 accesos rápidos.
struct VistaDeInicioTarjetas: View {
    let fuentes: FuentesDeInicioTarjetas
    /// Acceso rápido que se está cambiando. Mientras no es `nil`, el selector tapa las tarjetas.
    @State private var ranuraEditando: Int?

    var body: some View {
        HStack(spacing: Medidas.separacion) {
            ZStack {
                tarjetas
                    .opacity(ranuraEditando == nil ? 1 : 0)
                if ranuraEditando != nil {
                    SelectorDeAcceso(fuentes: fuentes, ranura: $ranuraEditando)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: ranuraEditando)

            ColumnaDeAccesosRapidos(fuentes: fuentes, ranuraEditando: $ranuraEditando)
                .frame(width: 38)
        }
    }

    private var tarjetas: some View {
        HStack(spacing: Medidas.separacion) {
            TarjetaConBorde {
                VStack(spacing: 0) {
                    ColumnaMusicaInicio(
                        ahoraSuena: fuentes.ahoraSuena,
                        alAbrirMusica: { fuentes.alAbrirModulo?("musica") },
                        caratula: 46
                    )
                    Spacer(minLength: 0)
                    FranjaDeEstado(fuentes: fuentes)
                }
            }
            .frame(width: 262)

            TarjetaConBorde {
                TarjetaInbox(fuentes: fuentes)
            }

            TarjetaConBorde(relleno: 8) {
                TarjetaBandejaReciente(fuentes: fuentes)
            }
            .frame(width: 124)
        }
    }
}

/// Clima, siguiente evento, tiempo de pantalla y batería, en una línea bajo la música.
private struct FranjaDeEstado: View {
    let fuentes: FuentesDeInicioTarjetas

    var body: some View {
        VStack(spacing: 6) {
            Rectangle().fill(Paleta.bordeSuave).frame(height: 1)
            HStack(spacing: 0) {
                if let clima = fuentes.clima {
                    dato(
                        EstadoDelClima.iconoWMO(codigo: clima.estado.codigoWMO, esDeDia: clima.estado.esDeDia),
                        Color(hex: 0xFFD54A),
                        clima.formatearTemp(clima.estado.temperaturaC),
                        "Clima"
                    ) { fuentes.alAbrirModulo?("clima") }
                }
                Spacer(minLength: 4)
                dato("calendar", Paleta.agenda, siguienteEvento, "Siguiente evento") {
                    fuentes.alAbrirModulo?("agenda")
                }
                Spacer(minLength: 4)
                dato("hourglass", Paleta.textoDeApoyo, tiempoDePantalla, "Tiempo de pantalla hoy") {
                    fuentes.alAbrirModulo?("screentime")
                }
                Spacer(minLength: 4)
                if let metricas = fuentes.monitor?.metricas {
                    dato(
                        metricas.bateriaCargando ? "battery.100.bolt" : "battery.75",
                        Paleta.monitorSistema,
                        "\(metricas.bateriaPorcentaje)%",
                        "Batería"
                    ) { fuentes.alAbrirModulo?("monitor") }
                }
            }
        }
    }

    private var siguienteEvento: String {
        let ahora = Date.now
        let proximo = fuentes.agenda?.eventosDelMes
            .filter { !$0.todoElDia && $0.fin > ahora && Calendar.current.isDateInToday($0.inicio) }
            .min { $0.inicio < $1.inicio }
        guard let proximo else { return "Libre" }
        return proximo.inicio.formatted(date: .omitted, time: .shortened)
    }

    private var tiempoDePantalla: String {
        let minutos = Int((fuentes.screenTime?.totalSegundosHoy ?? 0) / 60)
        return minutos >= 60 ? "\(minutos / 60) h \(minutos % 60)" : "\(minutos) min"
    }

    private func dato(
        _ simbolo: String, _ color: Color, _ texto: String, _ etiqueta: String,
        accion: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: accion) {
            HStack(spacing: 4) {
                Image(systemName: simbolo)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(texto)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Paleta.texto)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(etiqueta)
        .accessibilityLabel("\(etiqueta): \(texto)")
    }
}

/// Nota rápida al inbox de Obsidian y dos chips: el siguiente pendiente y lo último copiado.
private struct TarjetaInbox: View {
    let fuentes: FuentesDeInicioTarjetas
    @FocusState private var campoEnfocado: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label("Inbox", systemImage: "note.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Paleta.texto)
                    .labelStyle(IconoDeColor(color: Paleta.portapapeles))
                Spacer(minLength: 0)
                Button {
                    fuentes.inbox?.abrirEnObsidian()
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Paleta.textoDeApoyo)
                }
                .buttonStyle(.plain)
                .help("Abrir 00-inbox/inbox.md en Obsidian")
            }

            campo

            if let pendiente {
                FichaDePendiente(pendiente: pendiente, fecha: fechaCorta(pendiente.vencimiento), fuentes: fuentes)
            }
            if let copiado = fuentes.portapapeles?.elementos.first {
                chip {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Paleta.portapapeles)
                    Text(copiado.resumenCorto).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("copiado").textoDeApoyo()
                } accion: {
                    fuentes.portapapeles?.copiarAlSistema(copiado)
                }
                .help("Volver a copiar")
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var campo: some View {
        if let inbox = fuentes.inbox {
            @Bindable var gestor = inbox
            HStack(spacing: 5) {
                TextField("Nota rápida a Obsidian…", text: $gestor.borrador)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Paleta.texto)
                    .focused($campoEnfocado)
                    .onSubmit { _ = inbox.guardarBorrador() }
                Button {
                    _ = inbox.guardarBorrador()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Paleta.texto)
                        .frame(width: 18, height: 18)
                        .background(Paleta.superficieAlta, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Enviar al inbox")
            }
            .padding(.leading, 9)
            .padding(.trailing, 4)
            .frame(height: 28)
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Paleta.bordeSuave))
        }
    }

    private var pendiente: PendienteDeRecordatorios? {
        fuentes.agenda?.pendientes.first { !$0.completado }
    }

    private func fechaCorta(_ fecha: Date?) -> String {
        guard let fecha else { return "" }
        if Calendar.current.isDateInToday(fecha) { return "hoy" }
        if Calendar.current.isDateInTomorrow(fecha) { return "mañana" }
        return fecha.formatted(.dateTime.day().month(.abbreviated))
    }

    private func chip<Contenido: View>(
        @ViewBuilder _ contenido: () -> Contenido, accion: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: accion) {
            HStack(spacing: 7) { contenido() }
                .font(.system(size: 12))
                .foregroundStyle(Paleta.texto)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Módulos que pueden ir en un acceso rápido: todos menos Inicio y Flujo, que ya son pestañas.
@MainActor
func modulosParaAccesos(_ todos: [IdentidadDeModulo]) -> [IdentidadDeModulo] {
    todos.filter { $0.id != ModulosBase.inicio && $0.id != ModulosBase.flujo }
}

/// Tres botones cuadrados. Con el cursor encima aparece un lápiz en cada uno para cambiarlo.
private struct ColumnaDeAccesosRapidos: View {
    let fuentes: FuentesDeInicioTarjetas
    @Binding var ranuraEditando: Int?
    @State private var cursorEncima = false

    var body: some View {
        let ids = fuentes.ajustes?.accesosRapidos ?? Ajustes.accesosPorDefecto
        let disponibles = fuentes.modulosDisponibles?() ?? []
        VStack(spacing: 6) {
            ForEach(Array(ids.enumerated()), id: \.offset) { indice, id in
                boton(indice: indice, modulo: disponibles.first { $0.id == id })
            }
        }
        .onHover { cursorEncima = $0 }
    }

    private func boton(indice: Int, modulo: IdentidadDeModulo?) -> some View {
        let grabando = modulo?.id == "grabadora" && fuentes.grabadora?.grabando == true
        let editando = ranuraEditando == indice
        let color = modulo.map { Color(hex: $0.color) } ?? Paleta.textoDeApoyo
        let borde: Color = editando ? Paleta.texto : (grabando ? Paleta.grabadora.opacity(0.5) : Paleta.bordeSuave)
        return Button {
            if ranuraEditando != nil {
                ranuraEditando = indice
            } else if let modulo {
                fuentes.alAbrirModulo?(modulo.id)
            } else {
                ranuraEditando = indice
            }
        } label: {
            Image(systemName: modulo?.icono ?? "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    grabando ? Paleta.grabadora.opacity(0.18) : Paleta.superficie,
                    in: RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna)
                        .strokeBorder(borde, lineWidth: editando ? 1.5 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if cursorEncima && ranuraEditando == nil {
                Button {
                    ranuraEditando = indice
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Paleta.fondo)
                        .frame(width: 14, height: 14)
                        .background(Paleta.texto, in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .help("Cambiar este acceso")
                .accessibilityLabel("Cambiar acceso \(indice + 1)")
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: cursorEncima)
        .help(modulo?.nombre ?? "Acceso vacío")
        .accessibilityLabel(modulo?.nombre ?? "Acceso vacío")
    }
}

/// Selector dentro de la isla para elegir qué módulo va en un acceso. Un clic lo cambia y se cierra.
private struct SelectorDeAcceso: View {
    let fuentes: FuentesDeInicioTarjetas
    @Binding var ranura: Int?

    var body: some View {
        let indice = ranura ?? 0
        let actual = fuentes.ajustes?.accesosRapidos[safe: indice]
        let opciones = modulosParaAccesos(fuentes.modulosDisponibles?() ?? [])
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Acceso \(indice + 1)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Paleta.texto)
                Text("Elige qué abre este botón").textoDeApoyo()
                Spacer(minLength: 0)
                Button("Listo") { ranura = nil }
                    .buttonStyle(EstiloDePildora())
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(opciones) { modulo in
                        celda(modulo, elegido: modulo.id == actual)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna))
        .overlay(RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna).strokeBorder(Paleta.bordeSuave))
    }

    private func celda(_ modulo: IdentidadDeModulo, elegido: Bool) -> some View {
        let color = Color(hex: modulo.color)
        return Button {
            if let ranura { fuentes.ajustes?.cambiarAcceso(en: ranura, por: modulo.id) }
            ranura = nil
        } label: {
            VStack(spacing: 4) {
                Image(systemName: modulo.icono)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                Text(modulo.nombre)
                    .font(.system(size: 10))
                    .foregroundStyle(elegido ? Paleta.texto : Paleta.textoDeApoyo)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(elegido ? Paleta.superficieAlta : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(modulo.nombre)
        .accessibilityAddTraits(elegido ? .isSelected : [])
    }
}

extension Array {
    fileprivate subscript(safe indice: Int) -> Element? {
        indices.contains(indice) ? self[indice] : nil
    }
}

/// Siguiente pendiente. Tocar la ficha abre la Agenda; completar pide dos toques en la casilla
/// (el primero arma, el segundo confirma en menos de 3 s), para que un clic suelto no cierre nada.
private struct FichaDePendiente: View {
    let pendiente: PendienteDeRecordatorios
    let fecha: String
    let fuentes: FuentesDeInicioTarjetas
    @State private var armado = false
    @State private var tareaDesarmar: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 7) {
            Button(action: tocarCasilla) {
                Image(systemName: armado ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Paleta.portapapeles)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(armado ? "Toca otra vez para marcarlo como hecho" : "Marcar como hecho (dos toques)")
            .accessibilityLabel(armado ? "Confirmar: marcar como hecho" : "Marcar como hecho")

            Button {
                fuentes.alAbrirModulo?("agenda")
            } label: {
                HStack(spacing: 6) {
                    Text(armado ? "¿Hecho? Toca la casilla" : pendiente.titulo)
                        .foregroundStyle(armado ? Paleta.portapapeles : Paleta.texto)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !armado { Text(fecha).textoDeApoyo() }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(pendiente.titulo) · abrir en la Agenda")
        }
        .font(.system(size: 12))
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: 26)
        .background(
            armado ? Paleta.portapapeles.opacity(0.12) : Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .animation(.easeOut(duration: 0.15), value: armado)
        .onChange(of: pendiente.id) { desarmar() }
        .onDisappear { desarmar() }
    }

    private func tocarCasilla() {
        if armado {
            desarmar()
            let agenda = fuentes.agenda
            let id = pendiente.id
            Task { await agenda?.completarPendiente(id) }
        } else {
            armado = true
            tareaDesarmar?.cancel()
            tareaDesarmar = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled { armado = false }
            }
        }
    }

    private func desarmar() {
        tareaDesarmar?.cancel()
        tareaDesarmar = nil
        armado = false
    }
}

/// Los 2 archivos más recientes. Cada uno es una ficha completa: clic la abre y arrastrarla
/// suelta el archivo donde caiga. Sin `Button` encima, para que el arrastre no compita con el clic.
private struct TarjetaBandejaReciente: View {
    let fuentes: FuentesDeInicioTarjetas
    @State private var arrastrandoSobreArchivos = false

    var body: some View {
        let urls = ColumnaArchivosInicio.urlsRecientes(
            portapapeles: fuentes.portapapeles, bandeja: fuentes.bandeja, airdrop: fuentes.airdrop, limite: 2)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                fuentes.alAbrirModulo?("bandeja")
            } label: {
                HStack(spacing: 6) {
                    Label("Bandeja", systemImage: "tray.fill")
                        .labelStyle(IconoDeColor(color: Paleta.bandeja))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Paleta.textoDeApoyo)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Paleta.texto)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Abrir la Bandeja")

            if urls.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 18))
                        .foregroundStyle(Paleta.decorativo)
                    Text("Suelta aquí").textoDeApoyo()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(urls, id: \.path) { url in
                    FichaDeArchivo(url: url)
                }
                Spacer(minLength: 0)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    arrastrandoSobreArchivos ? Paleta.agenda : Color.clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $arrastrandoSobreArchivos) { proveedores in
            let bandeja = fuentes.bandeja
            Task { @MainActor in
                var urlsSoltadas: [URL] = []
                for proveedor in proveedores {
                    let url: URL? = await withCheckedContinuation { continuacion in
                        _ = proveedor.loadObject(ofClass: URL.self) { url, _ in
                            continuacion.resume(returning: url)
                        }
                    }
                    if let url { urlsSoltadas.append(url) }
                }
                bandeja?.agregarEnSegundoPlano(urlsSoltadas)
            }
            return true
        }
    }
}

private struct FichaDeArchivo: View {
    let url: URL
    @State private var cursorEncima = false

    var body: some View {
        HStack(spacing: 7) {
            MiniaturaDeArchivo(url: url, tamano: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Paleta.texto)
                    .lineLimit(2)
                Text(url.pathExtension.uppercased())
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 48)
        .background(
            cursorEncima ? Paleta.superficieAlta : Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onHover { cursorEncima = $0 }
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .help("\(url.lastPathComponent) · clic para abrir, arrastra para soltarlo en otro lado")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { NSWorkspace.shared.open(url) }
    }
}

/// Ícono en el color del módulo y texto en blanco.
struct IconoDeColor: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(color)
            configuration.title
        }
    }
}
