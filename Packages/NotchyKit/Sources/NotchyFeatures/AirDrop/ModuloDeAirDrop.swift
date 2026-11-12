import AppKit
import NotchyCore
import NotchyDesign
import SwiftUI
import UniformTypeIdentifiers

/// Módulo de AirDrop (`560 × 196 pt`): lista los archivos recibidos a la izquierda y envía archivos a la derecha (AIR-1, AIR-2).
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
        HStack(spacing: 8) {
            panelRecibidos
            zonaEnvio
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panelRecibidos: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 5) {
                Text("RECIBIDOS")
                    .rotulo(Paleta.airdrop)

                if let error = modelo.mensajeDeError {
                    Spacer(minLength: 0)
                    Text(error)
                        .textoDeApoyo()
                        .lineLimit(2)
                    Spacer(minLength: 0)
                } else if modelo.recibidos.isEmpty {
                    Spacer(minLength: 0)
                    Text("Sin archivos recibidos por AirDrop en Descargas")
                        .textoDeApoyo()
                        .lineLimit(2)
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(modelo.recibidos.prefix(8)) { archivo in
                                filaDeRecibido(archivo)
                            }
                        }
                    }
                }

                Button {
                    modelo.abrirCarpetaDescargas()
                } label: {
                    Text("Abrir carpeta Descargas")
                        .font(.system(size: 11))
                        .foregroundStyle(Paleta.textoDeApoyo)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func filaDeRecibido(_ archivo: ArchivoRecibidoAirDrop) -> some View {
        Button {
            modelo.abrirRecibido(archivo)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconoParaArchivo(archivo.nombre))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Paleta.airdrop)
                    .frame(width: 16)
                Text(archivo.nombre)
                    .textoDeCuerpo()
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(tiempoRelativo(archivo.fechaRecibido))
                    .textoDeApoyo()
                    .lineLimit(1)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir \(archivo.nombre)")
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

    private func iconoParaArchivo(_ nombre: String) -> String {
        let ext = (nombre as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "heic", "webp", "gif":
            return "photo"
        case "pdf", "doc", "docx", "txt", "md":
            return "doc.text"
        case "zip", "tar", "gz", "dmg":
            return "doc.zipper"
        default:
            return "doc"
        }
    }

    private func tiempoRelativo(_ fecha: Date) -> String {
        let formateador = RelativeDateTimeFormatter()
        formateador.locale = Locale(identifier: "es_MX")
        formateador.unitsStyle = .abbreviated
        return formateador.localizedString(for: fecha, relativeTo: .now)
    }
}
