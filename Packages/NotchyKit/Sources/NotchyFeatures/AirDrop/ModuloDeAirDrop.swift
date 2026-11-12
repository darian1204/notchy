import AppKit
import NotchyCore
import NotchyDesign
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Módulo de AirDrop (`580 × 212 pt`): recibidos con vista previa y arrastre a la izquierda; envío a la derecha (AIR-1, AIR-2).
@MainActor
public final class ModuloDeAirDrop: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "airdrop",
        nombre: "AirDrop",
        icono: "dot.radiowaves.left.and.right",
        color: Paleta.hexAirdrop,
        lado: .derecha
    )
    public let tamanoExpandido = Medidas.airdrop
    public let modelo: ModeloDeAirDrop

    public init(modelo: ModeloDeAirDrop) {
        self.modelo = modelo
    }

    public var salud: SaludDeModulo {
        modelo.salud
    }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeAirDrop(modelo: modelo))
    }

    public func arrancar() {
        modelo.iniciar()
    }

    public func detener() {
        modelo.detener()
    }
}

struct VistaDeAirDrop: View {
    let modelo: ModeloDeAirDrop
    @State private var arrastrandoSobreEnvio = false

    var body: some View {
        HStack(spacing: Medidas.separacion) {
            tarjetaRecibidos
            zonaEnvio
        }
    }

    private var tarjetaRecibidos: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Recibidos en Descargas", systemImage: "arrow.down.circle")
                        .rotulo(Paleta.airdrop)
                    Spacer(minLength: 0)
                    Button {
                        modelo.abrirCarpetaDescargas()
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Paleta.textoDeApoyo)
                    }
                    .buttonStyle(.plain)
                    .help("Abrir carpeta Descargas")
                }

                if modelo.recibidos.isEmpty {
                    Spacer(minLength: 0)
                    Text("Sin archivos recibidos por AirDrop")
                        .textoDeApoyo()
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(modelo.recibidos.prefix(12)) { archivo in
                                filaDeRecibido(archivo)
                            }
                        }
                    }
                }
            }
        }
    }

    private func filaDeRecibido(_ archivo: ArchivoRecibidoAirDrop) -> some View {
        HStack(spacing: 8) {
            MiniaturaDeArchivo(url: archivo.url, tamano: 28)

            Button {
                modelo.abrirRecibido(archivo)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(archivo.nombre)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Paleta.texto)
                        .lineLimit(1)
                    Text(tiempoRelativo(archivo.fechaRecibido))
                        .font(.system(size: 10))
                        .foregroundStyle(Paleta.textoDeApoyo)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Abrir \(archivo.nombre) en la app predeterminada")
            .accessibilityLabel("Abrir \(archivo.nombre)")

            Button {
                modelo.revelarRecibido(archivo)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Mostrar en Finder")
            .accessibilityLabel("Mostrar \(archivo.nombre) en Finder")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Paleta.superficieAlta.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .onDrag {
            NSItemProvider(object: archivo.url as NSURL)
        }
    }

    private var zonaEnvio: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Paleta.airdrop)

            Text("Suelta para enviar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Paleta.texto)

            Button {
                elegirArchivosYEnviar()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("Enviar con AirDrop")
                }
            }
            .buttonStyle(EstiloDePildora(destacado: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    arrastrandoSobreEnvio ? Paleta.airdrop : Paleta.texto.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $arrastrandoSobreEnvio) { proveedores in
            recibirProveedores(proveedores)
            return true
        }
    }

    private func elegirArchivosYEnviar() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Enviar por AirDrop"
        if panel.runModal() == .OK {
            modelo.enviar(archivos: panel.urls)
        }
    }

    private func recibirProveedores(_ proveedores: [NSItemProvider]) {
        for proveedor in proveedores {
            _ = proveedor.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    modelo.enviar(archivos: [url])
                }
            }
        }
    }

    private func tiempoRelativo(_ fecha: Date) -> String {
        let formateador = RelativeDateTimeFormatter()
        formateador.locale = Locale(identifier: "es_MX")
        formateador.unitsStyle = .abbreviated
        return formateador.localizedString(for: fecha, relativeTo: .now)
    }
}

/// Miniatura QuickLook o ícono del archivo en el sistema.
struct MiniaturaDeArchivo: View {
    let url: URL
    let tamano: CGFloat
    @State private var miniatura: NSImage?

    var body: some View {
        Group {
            if let miniatura {
                Image(nsImage: miniatura)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: tamano, height: tamano)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            let solicitud = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: tamano * 2, height: tamano * 2),
                scale: 2.0,
                representationTypes: .thumbnail
            )
            if let representacion = try? await QLThumbnailGenerator.shared.generateBestRepresentation(
                for: solicitud)
            {
                miniatura = representacion.nsImage
            }
        }
    }
}
