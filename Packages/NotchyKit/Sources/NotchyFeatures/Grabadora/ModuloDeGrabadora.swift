import AppKit
import NotchyCore
import NotchyDesign
import SwiftUI

/// Módulo de Grabadora y Reuniones (`620 × 238 pt`): transcripción en vivo ("Tú" y "Otros"),
/// notas de voz `.m4a`, historial con búsqueda sin acentos, retranscripción y glosario (GRB-1 a GRB-8).
@MainActor
public final class ModuloDeGrabadora: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "grabadora",
        nombre: "Grabadora",
        icono: "mic.fill",
        color: Paleta.hexGrabadora,
        lado: .izquierda
    )
    public let tamanoExpandido = Medidas.grabadora
    public let modelo: ModeloDeGrabadora

    public init(modelo: ModeloDeGrabadora) {
        self.modelo = modelo
    }

    public var salud: SaludDeModulo {
        modelo.salud
    }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeGrabadora(modelo: modelo))
    }

    public var orejaIzquierdaCompacta: AnyView? {
        AnyView(OrejaIzquierdaGrabando(modelo: modelo))
    }

    public var orejaDerechaCompacta: AnyView? {
        AnyView(OrejaDerechaGrabando(modelo: modelo))
    }

    public func arrancar() {
        modelo.iniciar()
    }

    public func detener() {
        modelo.detener()
    }
}

struct OrejaIzquierdaGrabando: View {
    let modelo: ModeloDeGrabadora

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(modelo.pausada ? Paleta.portapapeles : Paleta.grabadora)
                .frame(width: 7, height: 7)
            Text(modelo.cronometroFormateado)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(Paleta.texto)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            modelo.pausada
                ? "Grabación en pausa, \(modelo.cronometroFormateado)"
                : "Grabando, \(modelo.cronometroFormateado)"
        )
    }
}

struct OrejaDerechaGrabando: View {
    let modelo: ModeloDeGrabadora

    var body: some View {
        EspectroDeAudio(
            niveles: modelo.nivelesOnda,
            alto: 13,
            reproduciendo: !modelo.pausada,
            color: Paleta.grabadora
        )
        .frame(width: 18, height: 13)
        .accessibilityHidden(true)
    }
}

struct VistaDeGrabadora: View {
    @Bindable var modelo: ModeloDeGrabadora
    @State private var nuevoMalReconocido = ""
    @State private var nuevoCorrecto = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            barraSuperior
            if modelo.permisoMicrofono == .denegado || modelo.permisoMicrofono == .restringido {
                vistaPermisoDenegado
            } else {
                switch modelo.pestanaSeleccionada {
                case .reunion:
                    vistaReunion
                case .notasDeVoz:
                    vistaNotasDeVoz
                case .historial:
                    vistaHistorial
                case .glosario:
                    vistaGlosario
                }
            }
        }
    }

    // MARK: - Barra superior con indicador siempre visible (GRB-6)

    private var barraSuperior: some View {
        HStack(spacing: 6) {
            ForEach(PestanaDeGrabadora.allCases, id: \.self) { pestana in
                let activa = modelo.pestanaSeleccionada == pestana
                Button {
                    modelo.pestanaSeleccionada = pestana
                } label: {
                    Text(pestana.rawValue)
                        .font(.system(size: 11, weight: activa ? .semibold : .medium))
                        .foregroundStyle(activa ? Paleta.texto : Paleta.textoDeApoyo)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            activa ? Paleta.superficieAlta : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if modelo.grabando {
                HStack(spacing: 5) {
                    Circle()
                        .fill(modelo.pausada ? Paleta.portapapeles : Paleta.grabadora)
                        .frame(width: 6, height: 6)
                    Text(
                        "\(modelo.pausada ? "Pausa" : "Grabando") · \(modelo.cronometroFormateado)"
                    )
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Paleta.texto)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Paleta.superficieAlta, in: Capsule())
            }

            Button {
                let siguiente = modelo.idiomaSeleccionado.siguiente
                Task { await modelo.cambiarIdioma(siguiente) }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "globe")
                        .font(.system(size: 10, weight: .semibold))
                    Text(modelo.idiomaSeleccionado.etiquetaCorta)
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Paleta.texto)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Paleta.superficieAlta, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Cambiar idioma de transcripción (\(modelo.idiomaSeleccionado.etiqueta))")
            .accessibilityLabel("Idioma de transcripción \(modelo.idiomaSeleccionado.etiqueta)")
        }
    }

    // MARK: - Pestaña Reunión en vivo (GRB-2, GRB-3, GRB-6, GRB-7, GRB-8)

    @ViewBuilder
    private var vistaReunion: some View {
        if modelo.modoActivo == .reunion {
            VStack(alignment: .leading, spacing: 6) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            if modelo.segmentosEnVivo.isEmpty {
                                Text(
                                    "Escuchando micrófono (\"Tú\") y audio del sistema (\"Otros\") en \(modelo.idiomaSeleccionado.etiqueta)…"
                                )
                                .textoDeApoyo()
                                .padding(.vertical, 14)
                            } else {
                                ForEach(modelo.segmentosEnVivo) { seg in
                                    filaSegmento(seg)
                                        .id(seg.id)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .background(
                        Paleta.superficie,
                        in: RoundedRectangle(cornerRadius: Medidas.radioDeTarjeta)
                    )
                    .onChange(of: modelo.segmentosEnVivo.count) { _, _ in
                        if let ultimo = modelo.segmentosEnVivo.last?.id {
                            proxy.scrollTo(ultimo, anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                if let aviso = modelo.avisoDeFuente {
                    Text(aviso)
                        .font(.system(size: 10))
                        .foregroundStyle(Paleta.portapapeles)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    medidorFuente(etiqueta: "Tú", nivel: modelo.nivelMicrofono, color: Paleta.grabadora)
                    medidorFuente(etiqueta: "Otros", nivel: modelo.nivelSistema, color: Paleta.agenda)
                    if let desfase = modelo.estadisticasCaptura.desfaseInicialMs {
                        Text(String(format: "Δ %.0f ms", abs(desfase)))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(Paleta.textoDeApoyo)
                    }
                    Spacer(minLength: 0)

                    botonCopiarTranscripcion(
                        modelo.segmentosEnVivo,
                        titulo: modelo.reunionActual?.titulo
                    )

                    Button {
                        _ = modelo.agregarMarcaEnReunion()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 10))
                            Text("Marca")
                        }
                    }
                    .buttonStyle(EstiloDePildora())
                    .accessibilityLabel("Agregar marca de tiempo en la reunión")

                    Button {
                        modelo.alternarPausa()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: modelo.pausada ? "play.fill" : "pause.fill")
                                .font(.system(size: 10))
                            Text(modelo.pausada ? "Reanudar" : "Pausar")
                        }
                    }
                    .buttonStyle(EstiloDePildora())

                    Button {
                        Task { await modelo.detenerGrabacion() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                            Text("Detener y guardar")
                        }
                    }
                    .buttonStyle(EstiloDePildora(destacado: true))
                }
            }
        } else {
            HStack(spacing: 10) {
                Tarjeta {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nueva reunión")
                            .rotulo(Paleta.grabadora)
                        TextField("Título opcional (ej. Sync de producto)", text: $modelo.tituloReunion)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Paleta.texto)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Paleta.superficieAlta, in: RoundedRectangle(cornerRadius: 8))

                        Text("Graba micrófono (\"Tú\") y audio del sistema (\"Otros\") por trozos cada minuto.")
                            .textoDeApoyo()
                            .lineLimit(2)

                        Spacer(minLength: 0)

                        HStack(spacing: 8) {
                            Button {
                                Task { await modelo.iniciarReunion() }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "record.circle.fill")
                                    Text("Iniciar reunión")
                                }
                            }
                            .buttonStyle(EstiloDePildora(destacado: true))

                            if let error = modelo.mensajeDeError ?? modelo.avisoDeFuente {
                                Text(error)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Paleta.portapapeles)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                Tarjeta {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Últimas reuniones")
                            .rotulo(Paleta.agenda)
                        if modelo.reunionesGuardadas.isEmpty {
                            Text("Aún no hay reuniones guardadas.")
                                .textoDeApoyo()
                            Spacer(minLength: 0)
                        } else {
                            ForEach(modelo.reunionesGuardadas.prefix(3)) { reunion in
                                Button {
                                    modelo.reunionSeleccionadaID = reunion.id
                                    modelo.pestanaSeleccionada = .historial
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(reunion.titulo)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(Paleta.texto)
                                                .lineLimit(1)
                                            Text("\(reunion.estado.etiqueta) · \(reunion.idioma.etiquetaCorta)")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Paleta.textoDeApoyo)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Paleta.textoDeApoyo)
                                    }
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(width: 220)
            }
        }
    }

    private func botonCopiarTranscripcion(_ segmentos: [SegmentoDeTranscripcion], titulo: String?) -> some View {
        Button {
            modelo.copiarTranscripcion(segmentos, titulo: titulo)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: modelo.transcripcionCopiada ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                Text(modelo.transcripcionCopiada ? "Copiada" : "Copiar")
            }
        }
        .buttonStyle(EstiloDePildora())
        .disabled(segmentos.isEmpty)
        .help("Copiar la transcripción completa")
        .accessibilityLabel("Copiar transcripción de la reunión")
    }

    private func filaSegmento(_ seg: SegmentoDeTranscripcion) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(seg.fuente.etiqueta)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(colorParaFuente(seg.fuente))
                .frame(width: 38, alignment: .leading)
            Text(seg.marcaDeTiempoFormateada)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Paleta.textoDeApoyo)
            Text(seg.texto)
                .font(.system(size: 12, weight: seg.esFinal ? .regular : .light))
                .italic(!seg.esFinal)
                .foregroundStyle(seg.esFinal ? Paleta.texto : Paleta.textoDeApoyo)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func colorParaFuente(_ fuente: FuenteDeAudio) -> Color {
        switch fuente {
        case .microfono: Paleta.grabadora
        case .sistema: Paleta.agenda
        case .marca: Paleta.portapapeles
        }
    }

    private func medidorFuente(etiqueta: String, nivel: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(etiqueta)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Paleta.textoDeApoyo)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Paleta.superficieAlta)
                    .frame(width: 36, height: 5)
                Capsule()
                    .fill(color)
                    .frame(width: max(4, 36 * CGFloat(min(max(nivel, 0), 1))), height: 5)
            }
        }
    }

    // MARK: - Pestaña Notas de voz (GRB-1)

    private var vistaNotasDeVoz: some View {
        HStack(spacing: 10) {
            Tarjeta {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nota de voz (.m4a)")
                        .rotulo(Paleta.grabadora)

                    if modelo.modoActivo == .notaDeVoz {
                        HStack(spacing: 8) {
                            Text(modelo.cronometroFormateado)
                                .font(.system(size: 20, weight: .bold).monospacedDigit())
                                .foregroundStyle(Paleta.texto)
                            EspectroDeAudio(
                                niveles: modelo.nivelesOnda,
                                alto: 18,
                                reproduciendo: !modelo.pausada,
                                color: Paleta.grabadora
                            )
                            .frame(width: 34, height: 18)
                        }

                        Text(
                            modelo.textoNotaEnVivo.isEmpty
                                ? "Grabando micrófono…"
                                : modelo.textoNotaEnVivo
                        )
                        .textoDeApoyo()
                        .lineLimit(2)

                        Spacer(minLength: 0)

                        HStack(spacing: 6) {
                            Button(modelo.pausada ? "Reanudar" : "Pausar") {
                                modelo.alternarPausa()
                            }
                            .buttonStyle(EstiloDePildora())

                            Button("Guardar nota") {
                                Task { await modelo.detenerGrabacion() }
                            }
                            .buttonStyle(EstiloDePildora(destacado: true))
                        }
                    } else {
                        Text("Graba un archivo .m4a con cronómetro y transcripción rápida en tu Mac.")
                            .textoDeApoyo()
                        Spacer(minLength: 0)
                        Button {
                            Task { await modelo.iniciarNotaDeVoz() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "mic.fill")
                                Text("Grabar nota de voz")
                            }
                        }
                        .buttonStyle(EstiloDePildora(destacado: true))
                    }
                }
            }
            .frame(width: 230)

            Tarjeta {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notas guardadas (\(modelo.notasDeVoz.count))")
                        .rotulo(Paleta.texto)
                    if modelo.notasDeVoz.isEmpty {
                        Text("No hay notas de voz todavía.")
                            .textoDeApoyo()
                        Spacer(minLength: 0)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 5) {
                                ForEach(modelo.notasDeVoz) { nota in
                                    HStack(spacing: 6) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(nota.titulo)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(Paleta.texto)
                                                .lineLimit(1)
                                            Text(
                                                nota.transcripcion
                                                    ?? String(
                                                        format: "%.0f s · %@", nota.duracionSegundos,
                                                        nota.idioma.etiquetaCorta)
                                            )
                                            .font(.system(size: 10))
                                            .foregroundStyle(Paleta.textoDeApoyo)
                                            .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                        Button {
                                            modelo.abrirArchivo(nota.rutaArchivo)
                                        } label: {
                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(Paleta.grabadora)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Reproducir nota de voz")

                                        Button {
                                            modelo.borrarNotaDeVoz(nota)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Paleta.textoDeApoyo)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Borrar nota de voz")
                                    }
                                    .onDrag {
                                        NSItemProvider(object: nota.urlArchivo as NSURL)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pestaña Historial y Retranscripción (GRB-4)

    private var vistaHistorial: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Buscar sin acentos…", text: $modelo.consultaBusqueda)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Paleta.texto)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Paleta.superficieAlta, in: RoundedRectangle(cornerRadius: 8))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(modelo.reunionesGuardadas) { reunion in
                            let seleccionada = modelo.reunionSeleccionadaID == reunion.id
                            HStack(spacing: 4) {
                                Button {
                                    modelo.reunionSeleccionadaID = reunion.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(reunion.titulo)
                                            .font(.system(size: 11, weight: seleccionada ? .bold : .medium))
                                            .foregroundStyle(Paleta.texto)
                                            .lineLimit(1)
                                        Text("\(reunion.estado.etiqueta) · \(reunion.idioma.etiquetaCorta)")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Paleta.textoDeApoyo)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    modelo.borrarReunion(reunion)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Paleta.textoDeApoyo)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                seleccionada ? Paleta.superficieAlta : Paleta.superficie,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                    }
                }
            }
            .frame(width: 185)

            Tarjeta {
                VStack(alignment: .leading, spacing: 6) {
                    let mostrandoBusqueda = !modelo.consultaBusqueda.trimmingCharacters(in: .whitespaces).isEmpty
                    let lista =
                        mostrandoBusqueda
                        ? modelo.resultadosBusqueda
                        : modelo.segmentosDeReunionSeleccionada

                    HStack {
                        Text(
                            mostrandoBusqueda
                                ? "Resultados (\(lista.count))"
                                : "Transcripción (\(lista.count))"
                        )
                        .rotulo(Paleta.agenda)
                        Spacer(minLength: 0)
                        if !mostrandoBusqueda, !lista.isEmpty {
                            let titulo = modelo.reunionesGuardadas.first(where: {
                                $0.id == modelo.reunionSeleccionadaID
                            })?.titulo
                            Button {
                                modelo.copiarTranscripcion(lista, titulo: titulo)
                            } label: {
                                Label(
                                    modelo.transcripcionCopiada ? "Copiada" : "Copiar",
                                    systemImage: modelo.transcripcionCopiada ? "checkmark" : "doc.on.doc"
                                )
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Paleta.agenda)
                            .help("Copiar la transcripción completa")
                            .accessibilityLabel("Copiar transcripción de la reunión")
                        }
                        if let id = modelo.reunionSeleccionadaID,
                            let reunion = modelo.reunionesGuardadas.first(where: { $0.id == id }),
                            !reunion.rutasAudioMicrofono.isEmpty || !reunion.rutasAudioSistema.isEmpty
                        {
                            Button(modelo.retranscribiendo ? "Retranscribiendo…" : "Retranscribir") {
                                Task { await modelo.retranscribirReunion(reunion) }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Paleta.grabadora)
                            .disabled(modelo.retranscribiendo)
                        }
                    }

                    if lista.isEmpty {
                        Text("Sin segmentos para mostrar.")
                            .textoDeApoyo()
                        Spacer(minLength: 0)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(lista) { seg in
                                    filaSegmento(seg)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pestaña Glosario (GRB-5)

    private var vistaGlosario: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Mal reconocido (ej. supavase)", text: $nuevoMalReconocido)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Paleta.texto)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Paleta.superficieAlta, in: RoundedRectangle(cornerRadius: 8))

                TextField("Correcto (ej. Supabase)", text: $nuevoCorrecto)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Paleta.texto)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Paleta.superficieAlta, in: RoundedRectangle(cornerRadius: 8))

                Button("Agregar") {
                    modelo.agregarEntradaGlosario(
                        malReconocido: nuevoMalReconocido,
                        correcto: nuevoCorrecto
                    )
                    nuevoMalReconocido = ""
                    nuevoCorrecto = ""
                }
                .buttonStyle(EstiloDePildora(destacado: true))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(modelo.glosario) { entrada in
                        HStack {
                            Text(entrada.malReconocido)
                                .font(.system(size: 11))
                                .foregroundStyle(Paleta.textoDeApoyo)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundStyle(Paleta.textoDeApoyo)
                            Text(entrada.correcto)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Paleta.texto)
                            Spacer(minLength: 0)
                            Button {
                                modelo.borrarEntradaGlosario(entrada.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Paleta.textoDeApoyo)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var vistaPermisoDenegado: some View {
        Tarjeta {
            VStack(spacing: 8) {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Paleta.grabadora)
                Text("El permiso de Micrófono está denegado. Actívalo en Ajustes del Sistema para grabar.")
                    .textoDeApoyo()
                    .multilineTextAlignment(.center)
                Button("Abrir Ajustes del Sistema…") {
                    modelo.abrirAjustesPermisoMicrofono()
                }
                .buttonStyle(EstiloDePildora(destacado: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
