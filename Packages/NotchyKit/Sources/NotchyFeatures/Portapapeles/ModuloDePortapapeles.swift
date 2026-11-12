import AppKit
import NotchyCore
import NotchyDesign
import SwiftUI

/// Módulo de Portapapeles en la isla (CLP-1 a CLP-7): búsqueda sin acentos, filtros por tipo,
/// copiar con clic o ↵, abrir archivo/imagen/enlace, arrastrar como en Finder, fijar y borrar.
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
        VStack(alignment: .leading, spacing: 6) {
            barraBusquedaYFiltros
            listaDeElementos
        }
    }

    private var barraBusquedaYFiltros: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Paleta.textoDeApoyo)
                TextField("Buscar en \(modelo.totalGuardados) elementos", text: $modelo.busqueda)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Paleta.texto)
                    .onSubmit {
                        modelo.copiarSeleccionado()
                    }
                if !modelo.busqueda.isEmpty {
                    Button {
                        modelo.busqueda = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Paleta.textoDeApoyo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Limpiar búsqueda")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Paleta.superficie, in: Capsule())

            chipFiltro(titulo: "Todo", tipo: nil)
            ForEach(TipoDePortapapeles.allCases, id: \.self) { tipo in
                chipFiltro(titulo: tipo.etiqueta, tipo: tipo)
            }

            if modelo.totalGuardados > 0 {
                Button {
                    modelo.borrarTodo()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Paleta.textoDeApoyo)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Borrar todo el historial")
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(activo ? Paleta.fondo : Paleta.textoDeApoyo)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(activo ? Paleta.texto : Paleta.superficie, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filtrar por \(titulo)")
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
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(modelo.elementos) { elemento in
                        fila(elemento)
                    }
                }
            }
        }
    }

    private func fila(_ elemento: ElementoDePortapapeles) -> some View {
        let seleccionado = modelo.idSeleccionado == elemento.id
        return HStack(spacing: 8) {
            Button {
                modelo.copiarAlSistema(elemento)
            } label: {
                HStack(spacing: 8) {
                    iconoOVistaPrevia(de: elemento)
                    Text(elemento.texto.replacingOccurrences(of: "\n", with: " "))
                        .textoDeCuerpo()
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let app = elemento.appOrigen {
                        Text(app).textoDeApoyo().lineLimit(1)
                    }
                    if seleccionado {
                        Text("↵ copiar").textoDeApoyo()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
                .help("Abrir archivo o enlace")
                .accessibilityLabel("Abrir \(elemento.texto)")
            }

            Button {
                modelo.alternarFijado(elemento.id)
            } label: {
                Image(systemName: elemento.fijado ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(elemento.fijado ? Paleta.portapapeles : Paleta.textoDeApoyo)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(elemento.fijado ? "Desfijar" : "Fijar")
            .accessibilityLabel(elemento.fijado ? "Desfijar elemento" : "Fijar elemento")

            Button {
                modelo.borrar(elemento)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Borrar elemento")
            .accessibilityLabel("Borrar elemento")
        }
        .padding(.horizontal, 8)
        .frame(height: Medidas.altoDeFila)
        .background(
            seleccionado ? Paleta.superficieAlta : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .onDrag {
            proveedorDeArrastre(para: elemento)
        }
    }

    @ViewBuilder
    private func iconoOVistaPrevia(de elemento: ElementoDePortapapeles) -> some View {
        if let ruta = elemento.rutaArchivo {
            MiniaturaDeArchivo(url: URL(fileURLWithPath: ruta), tamano: 18)
        } else {
            Image(systemName: elemento.tipo.icono)
                .font(.system(size: 12))
                .foregroundStyle(color(de: elemento.tipo))
                .frame(width: 18)
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
