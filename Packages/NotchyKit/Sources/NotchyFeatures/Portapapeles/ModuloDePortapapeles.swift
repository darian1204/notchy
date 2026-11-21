import AppKit
import NotchyCore
import NotchyDesign
import SwiftUI

/// Módulo de Portapapeles en la isla (CLP-1 a CLP-7): diseño de tarjetas estilo "Clipboard" con "Clear All"
/// en rojo, imágenes como tarjeta visual pura sin etiqueta y botón circular de cierre.
@MainActor
public final class ModuloDePortapapeles: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "portapapeles",
        nombre: "Portapapeles",
        icono: "doc.on.clipboard",
        color: Paleta.hexPortapapeles,
        lado: .derecha
    )
    public let tamanoExpandido = Medidas.portapapeles
    public let modelo: ModeloDePortapapeles

    public init(modelo: ModeloDePortapapeles) {
        self.modelo = modelo
    }

    public var vistaExpandida: AnyView {
        AnyView(VistaDePortapapeles(modelo: modelo))
    }

    public func arrancar() {
        modelo.iniciarVigilancia()
    }

    public func detener() {
        modelo.detenerVigilancia()
    }
}

struct VistaDePortapapeles: View {
    @Bindable var modelo: ModeloDePortapapeles

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            encabezado
            listaDeElementos
        }
    }

    private var encabezado: some View {
        HStack(spacing: 10) {
            Text("Clipboard")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Paleta.texto)

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Paleta.textoDeApoyo)
                TextField("Buscar…", text: $modelo.busqueda)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Paleta.texto)
                    .onSubmit {
                        modelo.copiarSeleccionado()
                    }
                if !modelo.busqueda.isEmpty {
                    Button {
                        modelo.busqueda = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Paleta.textoDeApoyo)
                    }
                    .buttonStyle(.plain)
                    .help("Limpiar búsqueda")
                    .accessibilityLabel("Limpiar búsqueda")
                }
            }
            .padding(.horizontal, 8)
            .frame(width: 150, height: 22)
            .background(Paleta.superficie, in: Capsule())

            HStack(spacing: 4) {
                chipFiltro(titulo: "All", tipo: nil)
                ForEach(TipoDePortapapeles.allCases, id: \.self) { tipo in
                    chipFiltro(titulo: tipo.etiqueta, tipo: tipo)
                }
            }

            Spacer(minLength: 0)

            if modelo.totalGuardados > 0 {
                Button {
                    modelo.borrarTodo()
                } label: {
                    Text("Clear All")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFF6B6B))
                }
                .buttonStyle(.plain)
                .help("Borrar todo el portapapeles")
                .accessibilityLabel("Borrar todo el historial")
            }
        }
    }

    private func chipFiltro(titulo: String, tipo: TipoDePortapapeles?) -> some View {
        let activo = modelo.filtroTipo == tipo
        return Button {
            modelo.filtroTipo = tipo
        } label: {
            Text(titulo)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(activo ? Paleta.fondo : Paleta.textoDeApoyo)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(activo ? Paleta.texto : Paleta.superficie, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var listaDeElementos: some View {
        if modelo.elementos.isEmpty {
            VStack {
                Spacer()
                Text(modelo.busqueda.isEmpty ? "Aún no hay elementos copiados" : "Sin resultados")
                    .textoDeApoyo()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(modelo.elementos) { elemento in
                        filaTarjeta(elemento)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func filaTarjeta(_ elemento: ElementoDePortapapeles) -> some View {
        let seleccionado = modelo.idSeleccionado == elemento.id
        if elemento.tipo == .imagen, let ruta = elemento.rutaArchivo,
            let nsImage = NSImage(contentsOfFile: ruta)
        {
            // Tarjeta de imagen pura sin texto de descripción ("Imagen (12 KB)"), igual a la captura de referencia
            HStack(spacing: 10) {
                Button {
                    modelo.copiarAlSistema(elemento)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            .background(
                                Color.black.opacity(0.25),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(.vertical, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                botonesAccion(para: elemento)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                seleccionado ? Paleta.superficieAlta : Paleta.superficie,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .onDrag {
                proveedorDeArrastre(para: elemento)
            }
        } else {
            HStack(spacing: 10) {
                Button {
                    modelo.copiarAlSistema(elemento)
                } label: {
                    HStack(spacing: 8) {
                        if elemento.tipo == .archivo, let ruta = elemento.rutaArchivo {
                            MiniaturaDeArchivo(url: URL(fileURLWithPath: ruta), tamano: 20)
                        } else if let colorMuestra = ColorMuestreado(hex: elemento.texto) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(hex: colorMuestra.hexEntero))
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: elemento.tipo.icono)
                                .font(.system(size: 12))
                                .foregroundStyle(color(de: elemento.tipo))
                                .frame(width: 16)
                        }

                        Text(elemento.texto.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Paleta.texto)
                            .lineLimit(1)

                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                botonesAccion(para: elemento)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                seleccionado ? Paleta.superficieAlta : Paleta.superficie,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .onDrag {
                proveedorDeArrastre(para: elemento)
            }
        }
    }

    private func botonesAccion(para elemento: ElementoDePortapapeles) -> some View {
        HStack(spacing: 6) {
            if puedeAbrirse(elemento) {
                Button {
                    modelo.abrir(elemento)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Paleta.textoDeApoyo)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Abrir en su aplicación predeterminada")
                .accessibilityLabel("Abrir \(elemento.texto)")
            }

            Button {
                modelo.alternarFijado(elemento.id)
            } label: {
                Image(systemName: elemento.fijado ? "pin.fill" : "pin")
                    .font(.system(size: 10))
                    .foregroundStyle(elemento.fijado ? Paleta.portapapeles : Paleta.textoDeApoyo)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(elemento.fijado ? "Desfijar" : "Fijar")
            .accessibilityLabel(elemento.fijado ? "Desfijar elemento" : "Fijar elemento")

            Button {
                modelo.borrar(elemento)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Borrar elemento")
            .accessibilityLabel("Borrar elemento")
        }
    }

    private func puedeAbrirse(_ elemento: ElementoDePortapapeles) -> Bool {
        if let ruta = elemento.rutaArchivo {
            return FileManager.default.fileExists(atPath: ruta)
        }
        return elemento.tipo == .enlace
    }

    private func proveedorDeArrastre(para elemento: ElementoDePortapapeles) -> NSItemProvider {
        if let ruta = elemento.rutaArchivo {
            return NSItemProvider(object: URL(fileURLWithPath: ruta) as NSURL)
        }
        if elemento.tipo == .enlace, let url = URL(string: elemento.texto) {
            return NSItemProvider(object: url as NSURL)
        }
        return NSItemProvider(object: elemento.texto as NSString)
    }

    private func color(de tipo: TipoDePortapapeles) -> Color {
        switch tipo {
        case .texto: Paleta.portapapeles
        case .enlace: Paleta.agenda
        case .imagen: Paleta.bandeja
        case .archivo: Paleta.musica
        }
    }
}
