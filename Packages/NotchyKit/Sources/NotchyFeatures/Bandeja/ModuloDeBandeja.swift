import AppKit
import NotchyCore
import NotchyDesign
import SwiftUI
import UniformTypeIdentifiers

/// Módulo de Drop Actions y Shelf de archivos en la isla (BND-1 a BND-3), inspirado en el menú de acciones de archivos.
@MainActor
public final class ModuloDeBandeja: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "bandeja",
        nombre: "Archivos",
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
    @Bindable var modelo: ModeloDeBandeja
    @State private var accionConHover: String?
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            filaDropActionsPrincipales
            if modelo.mostrarSegundaFila {
                filaDropActionsSecundarias
            }
            tiraShelfArchivos
        }
        .padding(.horizontal, 4)
    }

    private var filaDropActionsPrincipales: some View {
        HStack(spacing: 0) {
            casillaDropAction(
                id: "icloud",
                icono: "icloud.and.arrow.up",
                titulo: "iCloud",
                subtitulo: "Save to Drive"
            ) { urls in
                modelo.guardarEnICloud(urls)
            }
            divisorVertical
            casillaDropAction(
                id: "convert",
                icono: "camera.viewfinder",
                titulo: "Convert",
                subtitulo: "\(modelo.formatoConversion) · Images"
            ) { urls in
                if urls.isEmpty && modelo.elementos.isEmpty {
                    modelo.formatoConversion = (modelo.formatoConversion == "PNG") ? "JPG" : "PNG"
                } else {
                    modelo.convertirImagenes(urls)
                }
            }
            divisorVertical
            casillaDropAction(
                id: "shelf",
                icono: "tray.and.arrow.down",
                titulo: "Shelf",
                subtitulo: "Hold files (\(modelo.elementos.count))"
            ) { urls in
                if !urls.isEmpty {
                    modelo.agregarEnSegundoPlano(urls)
                }
            }
            divisorVertical
            casillaDropAction(
                id: "expand",
                icono: modelo.mostrarSegundaFila
                    ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                titulo: "Expand",
                subtitulo: modelo.mostrarSegundaFila ? "Hide extra" : "Zip & Trash"
            ) { urls in
                if !urls.isEmpty {
                    modelo.comprimirEnZip(urls)
                } else {
                    withAnimation(Movimiento.cambioDeEstado(reducir: reducirMovimiento)) {
                        modelo.mostrarSegundaFila.toggle()
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .superficieDeIsla(.tarjeta, en: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Paleta.borde.opacity(0.75), lineWidth: 1)
        )
    }

    private var filaDropActionsSecundarias: some View {
        HStack(spacing: 8) {
            botonRapidoSecundario(icono: "doc.zipper", titulo: "Zip Shelf") {
                modelo.comprimirEnZip([])
            }
            botonRapidoSecundario(
                icono: "photo.badge.arrow.down",
                titulo: "Formato: \(modelo.formatoConversion)"
            ) {
                modelo.formatoConversion = (modelo.formatoConversion == "PNG") ? "JPG" : "PNG"
            }
            botonRapidoSecundario(icono: "trash", titulo: "Vaciar Shelf") {
                modelo.moverAPapelera([])
            }
            Spacer(minLength: 0)
            if let estado = modelo.mensajeEstado {
                Text(estado)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x30D158))
            }
        }
    }

    private func botonRapidoSecundario(
        icono: String,
        titulo: String,
        accion: @escaping () -> Void
    ) -> some View {
        Button(action: accion) {
            HStack(spacing: 5) {
                Image(systemName: icono)
                    .font(.system(size: 10, weight: .semibold))
                Text(titulo)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Paleta.texto)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Paleta.superficieAlta, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var divisorVertical: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 48)
    }

    private func casillaDropAction(
        id: String,
        icono: String,
        titulo: String,
        subtitulo: String,
        alEjecutar: @escaping @MainActor ([URL]) -> Void
    ) -> some View {
        let activo = accionConHover == id
        return Button {
            alEjecutar([])
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icono)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(activo ? Paleta.bandeja : Paleta.texto)
                    .frame(height: 24)
                Text(titulo)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Paleta.texto)
                    .lineLimit(1)
                Text(subtitulo)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                activo ? Paleta.superficieAlta : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima in
            accionConHover = encima ? id : (accionConHover == id ? nil : accionConHover)
        }
        .onDrop(
            of: [.fileURL],
            isTargeted: Binding(
                get: { accionConHover == id },
                set: { encima in accionConHover = encima ? id : nil }
            )
        ) { proveedores in
            recibirProveedores(proveedores, accion: alEjecutar)
        }
    }

    private var tiraShelfArchivos: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SHELF · SE VACÍA A LOS 10 MIN (\(modelo.elementos.count))")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Paleta.textoDeApoyo)
                Spacer(minLength: 0)
                if modelo.trabajando {
                    ProgressView()
                        .controlSize(.mini)
                }
                if let aviso = modelo.mensajeEstado, !modelo.mostrarSegundaFila {
                    Text(aviso)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x30D158))
                }
                if !modelo.elementos.isEmpty {
                    Button("Clear") {
                        modelo.vaciar()
                    }
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFF453A))
                    .buttonStyle(.plain)
                }
            }

            if modelo.elementos.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Paleta.textoDeApoyo)
                    Text(
                        "Arrastra archivos sobre cualquier acción de arriba o suéltalos aquí para retenerlos en Shelf."
                    )
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onDrop(of: [.fileURL], isTargeted: nil) { proveedores in
                    recibirProveedores(proveedores) { urls in
                        modelo.agregarEnSegundoPlano(urls)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(modelo.elementos) { elemento in
                            fichaCompactaShelf(elemento)
                        }
                    }
                }
            }
        }
    }

    private func fichaCompactaShelf(_ elemento: ElementoDeBandeja) -> some View {
        let url = elemento.urlParaArrastrar
        return HStack(spacing: 7) {
            Group {
                if let img = modelo.miniaturas[elemento.id] {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 14))
                        .foregroundStyle(Paleta.textoDeApoyo)
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(elemento.nombre)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Paleta.texto)
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)

            Button {
                modelo.quitar(elemento.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Paleta.textoDeApoyo)
            }
            .buttonStyle(.plain)
            .help("Quitar \(elemento.nombre) de la bandeja")
            .accessibilityLabel("Quitar \(elemento.nombre) de la bandeja")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .superficieDeIsla(.tarjeta, en: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture {
            NSWorkspace.shared.open(url)
        }
        .onDrag {
            NSItemProvider(object: url as NSURL)
        }
    }

    /// Junta todas las URLs soltadas y ejecuta la acción una sola vez (no una por archivo).
    private func recibirProveedores(
        _ proveedores: [NSItemProvider],
        accion: @escaping @MainActor ([URL]) -> Void
    ) -> Bool {
        guard !proveedores.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for proveedor in proveedores {
                if let url = await Self.cargarURL(de: proveedor) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                accion(urls)
            }
        }
        return true
    }

    private static func cargarURL(de proveedor: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuacion in
            _ = proveedor.loadObject(ofClass: URL.self) { url, _ in
                continuacion.resume(returning: url)
            }
        }
    }
}
