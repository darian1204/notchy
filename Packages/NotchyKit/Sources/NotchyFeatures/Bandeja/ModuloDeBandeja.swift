import NotchyCore
import NotchyDesign
import SwiftUI
import UniformTypeIdentifiers

/// Módulo de Bandeja de archivos en la isla (BND-1 a BND-3): soltar archivos para guardarlos y arrastrarlos hacia otra app.
@MainActor
public final class ModuloDeBandeja: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "bandeja",
        nombre: "Bandeja",
        icono: "tray.and.arrow.down.fill",
        color: Paleta.hexBandeja,
        lado: .derecha
    )
    public let tamanoExpandido = Medidas.bandeja
    public let modelo: ModeloDeBandeja

    public init(modelo: ModeloDeBandeja) {
        self.modelo = modelo
    }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeBandeja(modelo: modelo))
    }
}

struct VistaDeBandeja: View {
    let modelo: ModeloDeBandeja
    @State private var arrastrandoEncima = false

    var body: some View {
        VStack(spacing: 8) {
            if modelo.elementos.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 20))
                        .foregroundStyle(Paleta.bandeja)
                    Text("Suelta archivos aquí para tenerlos a mano")
                        .textoDeCuerpo()
                    Text("Arrástralos hacia cualquier app cuando los necesites")
                        .textoDeApoyo()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(modelo.elementos) { elemento in
                            fichaDeArchivo(elemento)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    Text("\(modelo.elementos.count) archivo(s) · suelta aquí o arrastra hacia afuera")
                        .textoDeApoyo()
                    Spacer()
                    Button("Vaciar") {
                        modelo.vaciar()
                    }
                    .buttonStyle(EstiloDePildora())
                    .accessibilityLabel("Vaciar bandeja")
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Medidas.radioDeTarjeta)
                .strokeBorder(
                    arrastrandoEncima ? Paleta.bandeja : Color.white.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $arrastrandoEncima) { proveedores in
            recibirProveedores(proveedores)
        }
    }

    private func fichaDeArchivo(_ elemento: ElementoDeBandeja) -> some View {
        let tamano = ByteCountFormatter.string(fromByteCount: Int64(elemento.bytes), countStyle: .file)
        return HStack(spacing: 6) {
            Image(systemName: elemento.archivoDisponible ? "doc.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(elemento.archivoDisponible ? Paleta.bandeja : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(elemento.nombre)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Paleta.texto)
                    .lineLimit(1)
                Text(elemento.archivoDisponible ? tamano : "Faltante")
                    .textoDeApoyo()
            }
            Button {
                modelo.quitar(elemento.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Quitar de la bandeja")
            .accessibilityLabel("Quitar \(elemento.nombre) de la bandeja")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 10))
        .onDrag {
            NSItemProvider(object: elemento.urlParaArrastrar as NSURL)
        }
    }

    private func recibirProveedores(_ proveedores: [NSItemProvider]) -> Bool {
        guard !proveedores.isEmpty else { return false }
        for proveedor in proveedores {
            _ = proveedor.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    _ = modelo.agregarArchivos([url])
                }
            }
        }
        return true
    }
}
