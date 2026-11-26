import AppKit
import NotchyCore
import NotchyDesign
import SwiftUI

/// Lista de temas del panel o de la barra: elegir, editar, borrar, agregar y restaurar los originales.
/// Los cambios se aplican al momento; con Ajustes abiertos la isla se queda abierta para verlos.
struct SeccionDeTemas: View {
    let ajustes: Ajustes
    let lista: ListaDeTemas

    @State private var edicion: EdicionDeTema?
    @State private var porBorrar: TemaDeColor?

    private let columnas = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        let temas = ajustes.temas(lista)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(titulo + " (\(temas.count))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if ajustes.originalesModificados(lista) {
                    Button("Restaurar temas originales") { ajustes.restaurarTemasOriginales(lista) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            LazyVGrid(columns: columnas, spacing: 10) {
                ForEach(temas) { tema in
                    FichaDeTema(
                        tema: tema,
                        lista: lista,
                        elegido: ajustes.temaActual(lista).id == tema.id,
                        puedeBorrar: ajustes.puedeEliminarTema(de: lista),
                        alElegir: { ajustes.elegirTema(tema.id, en: lista) },
                        alEditar: { editar(tema) },
                        alBorrar: { porBorrar = tema }
                    )
                }
                Button(action: agregar) {
                    Label("Agregar tema", systemImage: "plus")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $edicion) { edicion in
            EditorDeTema(ajustes: ajustes, lista: lista, edicion: edicion) { self.edicion = nil }
        }
        .confirmationDialog(
            "¿Borrar el tema \(porBorrar?.nombre ?? "")?",
            isPresented: Binding(get: { porBorrar != nil }, set: { if !$0 { porBorrar = nil } }),
            presenting: porBorrar
        ) { tema in
            Button("Borrar", role: .destructive) { ajustes.eliminarTema(tema.id, de: lista) }
        } message: { tema in
            Text(
                lista.originales.contains { $0.id == tema.id }
                    ? "Puedes recuperarlo con \"Restaurar temas originales\"."
                    : "Es un tema tuyo: no se puede recuperar."
            )
        }
    }

    private var titulo: String {
        switch lista {
        case .panel: "TEMA DEL PANEL"
        case .barra: "TEMA DE LA BARRA DE MÓDULOS"
        }
    }

    /// Editar elige el tema para verlo en la isla mientras se cambia.
    private func editar(_ tema: TemaDeColor) {
        let anterior = ajustes.idElegido(lista)
        ajustes.elegirTema(tema.id, en: lista)
        edicion = EdicionDeTema(id: tema.id, original: tema, eleccionAnterior: anterior)
    }

    private func agregar() {
        let anterior = ajustes.idElegido(lista)
        let base = ajustes.temaActual(lista)
        let id = ajustes.agregarTema(en: lista, nombre: "Mi tema", hex: base.hex)
        edicion = EdicionDeTema(id: id, original: nil, eleccionAnterior: anterior)
    }
}

/// Un tema en edición. `original` es `nil` si se acaba de crear: cancelar lo borra.
struct EdicionDeTema: Identifiable {
    let id: String
    let original: TemaDeColor?
    let eleccionAnterior: String
}

private struct FichaDeTema: View {
    let tema: TemaDeColor
    let lista: ListaDeTemas
    let elegido: Bool
    let puedeBorrar: Bool
    let alElegir: () -> Void
    let alEditar: () -> Void
    let alBorrar: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: alElegir) {
            HStack(spacing: 8) {
                MuestraDeTema(tema: tema, lista: lista)
                Text(tema.nombre)
                    .font(.caption.weight(elegido ? .bold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if encima {
                    Button(action: alEditar) { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .help("Editar")
                    if puedeBorrar {
                        Button(action: alBorrar) { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help("Borrar")
                    }
                } else if elegido {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .background(
                elegido ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .contextMenu {
            Button("Editar…", action: alEditar)
            if puedeBorrar {
                Button("Borrar…", role: .destructive, action: alBorrar)
            }
        }
        .accessibilityLabel(tema.nombre)
        .accessibilityAddTraits(elegido ? .isSelected : [])
    }
}

/// Muestra del color: el panel se degrada desde el negro del notch; la barra es un círculo.
private struct MuestraDeTema: View {
    let tema: TemaDeColor
    let lista: ListaDeTemas

    var body: some View {
        Group {
            switch (lista, tema.fuente) {
            case (_, .porModulo):
                Circle().fill(
                    AngularGradient(colors: [.blue, .purple, .pink, .orange, .green, .blue], center: .center))
            case (.panel, _):
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: [.black, Color(hex: tema.hex)], startPoint: .top, endPoint: .bottom))
            case (.barra, _):
                Circle().fill(Color(hex: tema.hex))
            }
        }
        .frame(width: 16, height: 16)
        .overlay {
            if tema.fuente == .caratula {
                Image(systemName: "music.note").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
            }
        }
        .overlay(Circle().strokeBorder(Color.white.opacity(lista == .barra ? 0.28 : 0), lineWidth: 1))
    }
}

/// Hoja para nombrar un tema y elegir su color exacto con el selector de macOS o en hex.
private struct EditorDeTema: View {
    let ajustes: Ajustes
    let lista: ListaDeTemas
    let edicion: EdicionDeTema
    let alTerminar: () -> Void

    @State private var nombre = ""
    @State private var hex: UInt32 = 0
    @State private var textoHex = ""

    private var tema: TemaDeColor? { ajustes.temas(lista).first { $0.id == edicion.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(edicion.original == nil ? "Nuevo tema" : "Editar tema")
                .font(.headline)
            Form {
                TextField("Nombre", text: $nombre)
                    .onChange(of: nombre) { aplicar() }
                if tema?.colorEditable ?? true {
                    ColorPicker("Color", selection: colorElegido, supportsOpacity: false)
                    TextField("Hex", text: $textoHex, prompt: Text("#RRGGBB"))
                        .font(.body.monospaced())
                        .onSubmit(leerHex)
                        .onChange(of: textoHex) { leerHex() }
                    if TemaDeColor.hex(desde: textoHex) == nil {
                        Text("Escribe un color como #D97D98.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text(explicacionSinColor)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Text("Los cambios se ven en la isla mientras editas.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancelar", role: .cancel, action: cancelar)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Listo", action: alTerminar)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            guard let tema else { return }
            nombre = tema.nombre
            hex = tema.hex
            textoHex = tema.textoHex
        }
    }

    private var explicacionSinColor: String {
        tema?.fuente == .caratula
            ? "Este tema toma su color de la carátula que está sonando."
            : "Con este tema cada módulo usa su propio color."
    }

    private var colorElegido: Binding<Color> {
        Binding(
            get: { Color(hex: hex) },
            set: { nuevo in
                hex = Self.hex(de: nuevo)
                textoHex = TemaDeColor.texto(de: hex)
                aplicar()
            }
        )
    }

    private func leerHex() {
        guard let leido = TemaDeColor.hex(desde: textoHex), leido != hex else { return }
        hex = leido
        aplicar()
    }

    private func aplicar() {
        guard var tema else { return }
        tema.nombre = nombre
        tema.hex = hex
        ajustes.actualizarTema(tema, en: lista)
    }

    /// Deshace: devuelve el tema como estaba (o lo borra si era nuevo) y la elección anterior.
    private func cancelar() {
        if let original = edicion.original {
            ajustes.actualizarTema(original, en: lista)
        } else {
            ajustes.eliminarTema(edicion.id, de: lista)
        }
        ajustes.elegirTema(edicion.eleccionAnterior, en: lista)
        alTerminar()
    }

    static func hex(de color: Color) -> UInt32 {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
        func canal(_ valor: CGFloat) -> UInt32 { UInt32((min(max(valor, 0), 1) * 255).rounded()) }
        return (canal(srgb.redComponent) << 16) | (canal(srgb.greenComponent) << 8) | canal(srgb.blueComponent)
    }
}
