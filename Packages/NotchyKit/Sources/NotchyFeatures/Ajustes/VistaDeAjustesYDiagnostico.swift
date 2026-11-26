import AppKit
import NotchyCore
import NotchyDesign
import SwiftUI
import UniformTypeIdentifiers

/// Ventana de Ajustes y panel de Permisos y Diagnóstico (ISL-8, SIS-1, SIS-2, SIS-3, SIS-4).
public struct VistaDeAjustesYDiagnostico: View {
    private let modelo: ModeloDeAjustesYDiagnostico
    private let alAbrirEnlace: (@MainActor (URL) -> Void)?
    private let alBorrarHistorialPortapapeles: (@MainActor () -> Void)?
    private let alBorrarTodosLosDatos: (@MainActor () -> Void)?
    private let alExportarDiagnostico: (@MainActor (String) -> Void)?
    private let alSalir: (@MainActor () -> Void)?
    @State private var confirmarBorradoGlobal = false

    public init(
        modelo: ModeloDeAjustesYDiagnostico,
        alAbrirEnlace: (@MainActor (URL) -> Void)? = nil,
        alBorrarHistorialPortapapeles: (@MainActor () -> Void)? = nil,
        alBorrarTodosLosDatos: (@MainActor () -> Void)? = nil,
        alExportarDiagnostico: (@MainActor (String) -> Void)? = nil,
        alSalir: (@MainActor () -> Void)? = nil
    ) {
        self.modelo = modelo
        self.alAbrirEnlace = alAbrirEnlace
        self.alBorrarHistorialPortapapeles = alBorrarHistorialPortapapeles
        self.alBorrarTodosLosDatos = alBorrarTodosLosDatos
        self.alExportarDiagnostico = alExportarDiagnostico
        self.alSalir = alSalir
    }

    public var body: some View {
        @Bindable var ajustes = modelo.ajustes
        TabView {
            Tab("Temas", systemImage: "paintpalette") {
                pestanaTemas(ajustes: $ajustes)
            }
            Tab("General", systemImage: "slider.horizontal.3") {
                pestanaGeneral(ajustes: $ajustes)
            }
            Tab("Módulos", systemImage: "square.grid.2x2") {
                pestanaModulos()
            }
            Tab("Permisos y diagnóstico", systemImage: "checkmark.shield") {
                pestanaDiagnostico()
            }
        }
        .frame(width: 560, height: 500)
        .onAppear {
            modelo.refrescar()
        }
    }

    private func accesoRapido(_ indice: Int) -> Binding<String> {
        Binding(
            get: {
                modelo.ajustes.accesosRapidos.indices.contains(indice) ? modelo.ajustes.accesosRapidos[indice] : ""
            },
            set: { modelo.ajustes.cambiarAcceso(en: indice, por: $0) }
        )
    }

    private func pestanaTemas(ajustes: Bindable<Ajustes>) -> some View {
        let columnasPanel = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        let columnasBarra = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

        return Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Estilo de la isla")
                        .font(.headline)
                    Picker("Estilo", selection: ajustes.estiloDeIsla) {
                        ForEach(EstiloDeIsla.allCases) { estilo in
                            Text(estilo.nombre).tag(estilo)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(modelo.ajustes.estiloDeIsla.descripcion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if modelo.ajustes.estiloDeIsla == .tarjetas {
                        Text("ACCESOS RÁPIDOS DEL INICIO")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(0..<Ajustes.cantidadDeAccesos, id: \.self) { indice in
                            Picker("Acceso \(indice + 1)", selection: accesoRapido(indice)) {
                                ForEach(
                                    modulosParaAccesos(modelo.modulosOrdenados).filter {
                                        modelo.estaModuloActivo($0.id)
                                    }
                                ) { modulo in
                                    Label(modulo.nombre, systemImage: modulo.icono).tag(modulo.id)
                                }
                            }
                        }
                        Text("También desde la isla: pasa el cursor por un acceso y toca el lápiz.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Liquid glass")
                        .font(.headline)
                    Picker("Liquid glass", selection: ajustes.vidrio) {
                        ForEach(EstiloDeVidrio.allCases) { estilo in
                            Text(estilo.nombre).tag(estilo)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(modelo.ajustes.vidrio.descripcion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Con \"Reducir transparencia\" en Accesibilidad se usan superficies sólidas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Siete temas para el panel y nueve para la barra")
                        .font(.headline)
                    Text(
                        "La barra puede usar un tema distinto al del panel, incluido uno que toma su color de la carátula que está sonando."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text("TEMA DEL PANEL (7)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    LazyVGrid(columns: columnasPanel, spacing: 10) {
                        ForEach(TemaDePanel.allCases) { tema in
                            let seleccionado = modelo.ajustes.temaPanel == tema
                            Button {
                                modelo.ajustes.temaPanel = tema
                            } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.black,
                                                    Color(hex: tema.hexBase),
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(height: 36)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(
                                                    seleccionado
                                                        ? Color.accentColor
                                                        : Color.white.opacity(0.22),
                                                    lineWidth: seleccionado ? 2 : 1
                                                )
                                        )
                                    Text(tema.nombre)
                                        .font(.caption.weight(seleccionado ? .bold : .medium))
                                        .lineLimit(1)
                                }
                                .padding(6)
                                .background(
                                    seleccionado
                                        ? Color.accentColor.opacity(0.12)
                                        : Color.primary.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("TEMA DE LA BARRA DE MÓDULOS (9)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    LazyVGrid(columns: columnasBarra, spacing: 10) {
                        ForEach(TemaDeBarra.allCases) { tema in
                            let seleccionado = modelo.ajustes.temaBarra == tema
                            Button {
                                modelo.ajustes.temaBarra = tema
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(colorMuestraBarra(tema))
                                        .frame(width: 16, height: 16)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                                        )
                                    Text(tema.nombre)
                                        .font(.caption.weight(seleccionado ? .bold : .medium))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    if seleccionado {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    seleccionado
                                        ? Color.accentColor.opacity(0.14)
                                        : Color.primary.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Mini-menú HUD del sistema") {
                Toggle(
                    "Mostrar Volumen, Brillo y Batería en las orejas del notch",
                    isOn: ajustes.hudSistemaActivo
                )
            }
        }
        .formStyle(.grouped)
    }

    private func colorMuestraBarra(_ tema: TemaDeBarra) -> Color {
        Color(hex: tema.hexAcento ?? 0x5AA9FF)
    }

    private func pestanaGeneral(ajustes: Bindable<Ajustes>) -> some View {
        Form {
            Section("Isla y pantalla") {
                Picker("Pantalla de la isla", selection: ajustes.pantalla) {
                    Text("Pantalla con notch (o principal si no hay)").tag(PantallaPreferida.conNotch)
                    Text("Siempre en la pantalla principal").tag(PantallaPreferida.principal)
                }
                .accessibilityLabel("Pantalla de la isla")

                Picker("Atajo global para abrir o cerrar", selection: ajustes.atajo) {
                    ForEach(AtajoDeIsla.allCases, id: \.self) { atajo in
                        Text(atajo.etiqueta).tag(atajo)
                    }
                }
                .accessibilityLabel("Atajo global para abrir o cerrar")
            }

            Section("Portapapeles") {
                Picker("Borrar copias después de", selection: ajustes.horasRetencionPortapapeles) {
                    Text("1 hora").tag(1)
                    Text("24 horas").tag(24)
                    Text("7 días").tag(168)
                    Text("30 días").tag(720)
                }
                .accessibilityLabel("Retención por antigüedad del portapapeles")

                Picker("Límite de elementos", selection: ajustes.limiteElementosPortapapeles) {
                    Text("500 elementos").tag(500)
                    Text("2000 elementos").tag(2000)
                    Text("5000 elementos").tag(5000)
                }
                .accessibilityLabel("Límite de elementos del portapapeles")

                if let alBorrarHistorialPortapapeles {
                    HStack {
                        Text("Los elementos fijados no se borran por retención.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Borrar todo el portapapeles", role: .destructive, action: alBorrarHistorialPortapapeles)
                            .controlSize(.small)
                            .accessibilityLabel("Borrar todo el portapapeles")
                    }
                }
            }

            Section("Reuniones") {
                Toggle("Separar voces del micrófono en reuniones", isOn: ajustes.separarVocesEnReuniones)
                    .accessibilityLabel("Separar voces del micrófono en reuniones")
                Text(
                    "Distingue entre varios hablantes en reuniones en persona (Persona 1, Persona 2…) en tu Mac. La primera vez descarga los modelos."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle("Resumir cada reunión en el inbox de Obsidian", isOn: ajustes.resumirReunionesEnInbox)
                    .accessibilityLabel("Resumir cada reunión en el inbox de Obsidian")
                Text(
                    "Al detener una reunión, Apple Intelligence la resume en tu Mac y agrega el resumen a 00-inbox/inbox.md."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Inicio y barra de menús") {
                Toggle("Iniciar Notchy al abrir sesión", isOn: ajustes.iniciarAlAbrirSesion)
                    .accessibilityLabel("Iniciar Notchy al abrir sesión")

                if modelo.estadoDeInicioAlAbrirSesion.requiereAprobacionEnSistema {
                    HStack(alignment: .center, spacing: 8) {
                        Text("macOS requiere aprobar a Notchy en Ítems de inicio para arrancar al abrir sesión.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Abrir Ítems de inicio…") {
                            modelo.abrirAjustesDeItemsDeInicio()
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Abrir Ítems de inicio en Ajustes del Sistema")
                    }
                }

                Toggle("Mostrar ícono en la barra de menús", isOn: ajustes.iconoEnBarraDeMenus)
                    .accessibilityLabel("Mostrar ícono en la barra de menús")
                Text("Ofrece acceso rápido al estado de la isla, a esta ventana y a Salir de Notchy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if alBorrarTodosLosDatos != nil || alSalir != nil {
                Section("Zona peligrosa") {
                    if let alBorrarTodosLosDatos {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Restablecer datos locales")
                                    .font(.body.weight(.medium))
                                Text(
                                    "Borra portapapeles, bandeja, reuniones, audios, historial del agente y ajustes. No toca tu vault de Obsidian."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Borrar todos los datos de Notchy…", role: .destructive) {
                                confirmarBorradoGlobal = true
                            }
                            .accessibilityLabel("Borrar todos los datos de Notchy")
                            .confirmationDialog(
                                "¿Borrar todos los datos de Notchy?",
                                isPresented: $confirmarBorradoGlobal,
                                titleVisibility: .visible
                            ) {
                                Button("Borrar todos los datos", role: .destructive) {
                                    alBorrarTodosLosDatos()
                                }
                                Button("Cancelar", role: .cancel) {}
                            } message: {
                                Text(
                                    "Se eliminarán el historial del portapapeles, los archivos en la bandeja, las reuniones, grabaciones y notas de voz, el historial del agente y tus preferencias. Tu vault de Obsidian no se modificará."
                                )
                            }
                        }
                    }
                    if let alSalir {
                        HStack {
                            Spacer()
                            Button("Salir de Notchy", role: .destructive, action: alSalir)
                                .accessibilityLabel("Salir de Notchy")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func pestanaModulos() -> some View {
        let modulos = modelo.modulosOrdenados
        return Form {
            Section("Módulos activos y su orden") {
                ForEach(Array(modulos.enumerated()), id: \.element.id) { indice, modulo in
                    HStack(spacing: 10) {
                        Image(systemName: modulo.icono)
                            .foregroundStyle(Color(hex: modulo.color))
                            .frame(width: 20)
                        Text(modulo.nombre)
                        Spacer()
                        Button {
                            modelo.moverModuloArriba(modulo.id)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(indice == 0)
                        .help("Subir \(modulo.nombre)")
                        .accessibilityLabel("Subir \(modulo.nombre)")

                        Button {
                            modelo.moverModuloAbajo(modulo.id)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(indice + 1 >= modulos.count)
                        .help("Bajar \(modulo.nombre)")
                        .accessibilityLabel("Bajar \(modulo.nombre)")

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { modelo.estaModuloActivo(modulo.id) },
                                set: { modelo.cambiarModuloActivo(modulo.id, $0) }
                            )
                        )
                        .labelsHidden()
                        .disabled(modulo.id == ModulosBase.inicio && modulos.count == 1)
                        .accessibilityLabel("Activar \(modulo.nombre)")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func pestanaDiagnostico() -> some View {
        Form {
            Section("Permisos del sistema") {
                ForEach(PermisoDelSistema.allCases) { permiso in
                    filaPermiso(permiso)
                }
            }

            Section("Estado del sistema") {
                LabeledContent("Base de datos") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label(
                            modelo.diagnosticoDeBase.estaBien ? "Lista" : "Atención",
                            systemImage: modelo.diagnosticoDeBase.estaBien
                                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(modelo.diagnosticoDeBase.estaBien ? .green : .orange)
                        Text(modelo.diagnosticoDeBase.detalle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let arreglo = modelo.diagnosticoDeBase.comoArreglarlo {
                            Text(arreglo)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                LabeledContent("Motor del agente (OpenCode)") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label(
                            modelo.estadoDeOpenCode.estaListo ? "Instalado" : "Falta instalar",
                            systemImage: modelo.estadoDeOpenCode.estaListo
                                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(modelo.estadoDeOpenCode.estaListo ? .green : .orange)
                        Text(modelo.estadoDeOpenCode.detalle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(modelo.diagnosticoDeModulos) { modulo in
                    LabeledContent("Módulo: \(modulo.nombre)") {
                        etiquetaSalud(modulo)
                    }
                }
            }

            Section {
                HStack {
                    Button("Actualizar diagnóstico") {
                        modelo.refrescar()
                    }
                    .accessibilityLabel("Actualizar diagnóstico")
                    Spacer()
                    Button("Exportar diagnóstico…") {
                        exportarDiagnostico()
                    }
                    .accessibilityLabel("Exportar diagnóstico sin datos personales")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func exportarDiagnostico() {
        let contenido = modelo.construirReporteDeDiagnostico()
        if let alExportarDiagnostico {
            alExportarDiagnostico(contenido)
            return
        }
        let panel = NSSavePanel()
        panel.title = "Exportar diagnóstico de Notchy"
        panel.nameFieldStringValue = "notchy-diagnostico.json"
        panel.allowedContentTypes = [.json, .plainText]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? contenido.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func filaPermiso(_ permiso: PermisoDelSistema) -> some View {
        let estado = modelo.estado(de: permiso)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(permiso.nombre).font(.body.weight(.medium))
                    Text(permiso.paraQueSirve)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(estado.etiqueta)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(de: estado))

                switch estado {
                case .sinPedir:
                    Button("Pedir permiso") {
                        Task { await modelo.pedirPermiso(permiso) }
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Pedir permiso de \(permiso.nombre)")
                case .denegado, .restringido:
                    if let url = permiso.enlaceDeAjustesDelSistema, let alAbrirEnlace {
                        Button("Abrir Ajustes") {
                            alAbrirEnlace(url)
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Abrir Ajustes del Sistema para \(permiso.nombre)")
                    }
                case .concedido:
                    EmptyView()
                }
            }
            if estado == .denegado || estado == .restringido {
                Text("Cómo activarlo: \(permiso.comoConcederlo)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func etiquetaSalud(_ modulo: DiagnosticoDeModulo) -> some View {
        Group {
            if !modulo.activo {
                Text("Apagado").font(.caption).foregroundStyle(.secondary)
            } else {
                switch modulo.salud {
                case .listo:
                    Label("Listo", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .faltaPermiso(let cual):
                    Label("Falta permiso: \(cual)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                case .error(let detalle):
                    Label(detalle, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func color(de estado: EstadoDePermiso) -> Color {
        switch estado {
        case .concedido: .green
        case .sinPedir: .secondary
        case .denegado, .restringido: .orange
        }
    }
}
