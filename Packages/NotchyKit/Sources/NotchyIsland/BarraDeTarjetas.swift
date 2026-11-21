import NotchyCore
import NotchyDesign
import SwiftUI

/// Pestaña del estilo tarjetas: un módulo o el buscador.
enum PestanaDeTarjetas: CaseIterable {
    case inicio, flujo, agente

    var modulo: String {
        switch self {
        case .inicio: ModulosBase.inicio
        case .flujo: ModulosBase.flujo
        case .agente: ModulosBase.agente
        }
    }

    var nombre: String {
        switch self {
        case .inicio: "Inicio"
        case .flujo: "Flujo"
        case .agente: "Agente"
        }
    }

    var simbolo: String {
        switch self {
        case .inicio: "house"
        case .flujo: "square.stack.3d.up"
        case .agente: "sparkles"
        }
    }

    /// Pestaña de un módulo abierto, si tiene una.
    static func de(modulo id: String?) -> PestanaDeTarjetas? {
        allCases.first { $0.modulo == id }
    }
}

/// Barra del estilo tarjetas, simétrica respecto al notch: Inicio y Flujo a la izquierda,
/// Agente y Buscar a la derecha, en dos píldoras del mismo ancho.
struct BarraDeTarjetas: View {
    let coordinador: CoordinadorDeIsla
    let paletaAbierta: Bool
    let alBuscar: @MainActor () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reducirTransparencia

    var body: some View {
        HStack(spacing: 0) {
            pildora {
                pestana(.inicio)
                pestana(.flujo)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: coordinador.geometria.pantalla.notch?.width ?? Medidas.notch.width)

            pildora {
                pestana(.agente)
                buscar
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Medidas.margenLateral)
        .contextMenu {
            if let abrirAjustes = coordinador.alAbrirAjustes {
                Button("Ajustes…", action: abrirAjustes)
                Divider()
            }
            Button("Salir de Notchy") { coordinador.alSalir?() }
        }
    }

    private func pildora<Contenido: View>(@ViewBuilder _ contenido: () -> Contenido) -> some View {
        HStack(spacing: 2) { contenido() }
            .padding(2)
            .frame(width: Medidas.anchoDePestanas)
            .background(
                reducirTransparencia ? Paleta.superficieSolida : Paleta.superficie,
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Paleta.bordeSuave))
    }

    private func pestana(_ pestana: PestanaDeTarjetas) -> some View {
        let modulo = coordinador.registro.activos.first { $0.identidad.id == pestana.modulo }
        let activa = !paletaAbierta && coordinador.moduloAbierto?.identidad.id == pestana.modulo
        return Button {
            coordinador.recibir(.elegirModulo(pestana.modulo))
        } label: {
            HStack(spacing: 5) {
                Image(systemName: pestana.simbolo)
                    .font(.system(size: 10, weight: .semibold))
                Text(pestana.nombre)
                    .font(.system(size: 11, weight: .medium))
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    if let insignia = modulo?.insignia {
                        Text("\(insignia)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(Paleta.fondo)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(Paleta.portapapeles, in: Capsule())
                    }
                }
            }
            .foregroundStyle(activa ? Paleta.texto : Paleta.textoDeApoyo)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(
                activa ? (reducirTransparencia ? Paleta.superficieAltaSolida : Paleta.superficieAlta) : Color.clear,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(modulo == nil)
        .opacity(modulo == nil ? 0.4 : 1)
        .help(modulo == nil ? "\(pestana.nombre) está apagado en Ajustes" : pestana.nombre)
        .accessibilityLabel(pestana.nombre)
        .accessibilityAddTraits(activa ? .isSelected : [])
    }

    private var buscar: some View {
        Button(action: alBuscar) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                Text("Buscar")
                    .font(.system(size: 11, weight: .medium))
                Text("⌘K")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Paleta.texto)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Paleta.superficieAlta, in: RoundedRectangle(cornerRadius: 4))
            }
            .foregroundStyle(paletaAbierta ? Paleta.texto : Paleta.textoDeApoyo)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(paletaAbierta ? Paleta.superficieAlta : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("k", modifiers: .command)
        .help("Buscar módulo (⌘K)")
        .accessibilityLabel("Buscar módulo")
    }
}

/// Tres puntos bajo el notch que dicen en qué pestaña estás. Nunca dentro de la cámara.
struct PuntosDePagina: View {
    let activa: PestanaDeTarjetas?

    var body: some View {
        HStack(spacing: 5) {
            ForEach(PestanaDeTarjetas.allCases, id: \.self) { pestana in
                Capsule()
                    .fill(pestana == activa ? Paleta.texto : Paleta.decorativo)
                    .frame(width: pestana == activa ? 14 : 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Paleta ⌘K: busca entre los módulos activos y abre el elegido. ↵ abre el primero, Esc cierra.
struct PaletaDeModulos: View {
    let coordinador: CoordinadorDeIsla
    let alCerrar: @MainActor () -> Void

    @State private var consulta = ""
    @FocusState private var enfocado: Bool

    private var resultados: [IdentidadDeModulo] {
        let todos = coordinador.registro.activos.map(\.identidad)
        let texto = consulta.trimmingCharacters(in: .whitespaces)
        guard !texto.isEmpty else { return todos }
        return todos.filter {
            $0.nombre.localizedStandardContains(texto) || $0.id.localizedStandardContains(texto)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                TextField("Buscar módulo", text: $consulta)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Paleta.texto)
                    .focused($enfocado)
                    .onSubmit { if let primero = resultados.first { abrir(primero.id) } }
                Text("esc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Paleta.superficieAlta, in: RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 8))

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                    ForEach(Array(resultados.enumerated()), id: \.element.id) { indice, modulo in
                        celda(modulo, seleccionada: indice == 0 && !consulta.isEmpty)
                    }
                    if consulta.isEmpty || "ajustes".localizedStandardContains(consulta),
                        let abrirAjustes = coordinador.alAbrirAjustes
                    {
                        celdaDeAjustes(abrirAjustes)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna))
        .overlay(RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna).strokeBorder(Paleta.bordeSuave))
        .onAppear { enfocado = true }
        .onExitCommand(perform: alCerrar)
    }

    private func abrir(_ id: String) {
        alCerrar()
        coordinador.recibir(.elegirModulo(id))
    }

    private func celda(_ modulo: IdentidadDeModulo, seleccionada: Bool) -> some View {
        Button {
            abrir(modulo.id)
        } label: {
            contenidoDeCelda(simbolo: modulo.icono, color: Color(hex: modulo.color), nombre: modulo.nombre)
                .background(
                    seleccionada ? Paleta.superficie : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir \(modulo.nombre)")
    }

    private func celdaDeAjustes(_ abrirAjustes: @escaping @MainActor () -> Void) -> some View {
        Button {
            alCerrar()
            abrirAjustes()
        } label: {
            contenidoDeCelda(simbolo: "gearshape.fill", color: Paleta.textoDeApoyo, nombre: "Ajustes")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir Ajustes")
    }

    private func contenidoDeCelda(simbolo: String, color: Color, nombre: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: simbolo)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            Text(nombre)
                .font(.system(size: 10))
                .foregroundStyle(Paleta.textoDeApoyo)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}
