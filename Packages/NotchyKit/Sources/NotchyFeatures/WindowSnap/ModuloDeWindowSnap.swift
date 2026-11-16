import AppKit
import Foundation
import NotchyCore
import NotchyDesign
import Observation
import SwiftUI

/// Modelo observable del módulo Window Snap para reordenar el tamaño de la ventana activa.
@MainActor
@Observable
public final class ModeloDeWindowSnap {
    public private(set) var ultimaDisposicion: DisposicionDeVentana?
    public private(set) var estadoMensaje: String?

    @ObservationIgnored public let puerto: any PuertoWindowSnap

    public static let filaPrincipal: [DisposicionDeVentana] = [
        .cuartoSupIzq,
        .cuartoInfIzq,
        .cuartoSupDer,
        .cuartoInfDer,
        .mitadIzquierda,
        .maximizar,
        .mitadDerecha,
        .tercioIzquierdo,
        .tercioCentral,
        .tercioDerecho,
    ]

    public static let filaSecundaria: [DisposicionDeVentana] = [
        .mitadSuperior,
        .mitadInferior,
        .centrar,
    ]

    public private(set) var tienePermiso: Bool

    @ObservationIgnored private var tareaEsperaPermiso: Task<Void, Never>?
    @ObservationIgnored private var observadorAccesibilidad: NSObjectProtocol?

    public init(puerto: any PuertoWindowSnap) {
        self.puerto = puerto
        self.tienePermiso = puerto.tienePermisoAccesibilidad
        // macOS avisa por este canal cuando cambia la lista de apps con Accesibilidad.
        observadorAccesibilidad = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.refrescarPermiso()
            }
        }
    }

    /// Relee el permiso de Accesibilidad; la vista se actualiza sola al cambiar.
    public func refrescarPermiso() {
        let actual = puerto.tienePermisoAccesibilidad
        if actual != tienePermiso { tienePermiso = actual }
        if actual {
            tareaEsperaPermiso?.cancel()
            tareaEsperaPermiso = nil
            if estadoMensaje?.hasPrefix("Concede permiso") == true { estadoMensaje = nil }
        }
    }

    public var nombreApp: String {
        puerto.nombreAppObjetivo
    }

    public var bundleIdApp: String? {
        puerto.bundleIdObjetivo
    }

    public func pedirPermiso() {
        puerto.pedirPermisoAccesibilidad()
        // El aviso del sistema solo sale una vez; abrir Ajustes directo cubre el resto.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        esperarPermiso()
    }

    /// Revisa cada segundo (hasta 2 min) si ya se concedió, por si no llega la notificación del sistema.
    private func esperarPermiso() {
        tareaEsperaPermiso?.cancel()
        tareaEsperaPermiso = Task { [weak self] in
            for _ in 0..<120 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.refrescarPermiso()
                if self.tienePermiso { return }
            }
        }
    }

    public func aplicar(_ disposicion: DisposicionDeVentana) {
        ultimaDisposicion = disposicion
        let exito = puerto.aplicar(disposicion)
        if exito {
            estadoMensaje = "\(disposicion.titulo) aplicado a \(nombreApp)"
        } else if !puerto.tienePermisoAccesibilidad {
            refrescarPermiso()
            pedirPermiso()
            estadoMensaje = "Concede permiso de Accesibilidad para redimensionar \(nombreApp)"
        } else {
            estadoMensaje = "No se encontró ventana redimensionable en \(nombreApp)"
        }
    }
}

/// Módulo Window Snap en el notch (`macwindow.split.2x1`).
@MainActor
public final class ModuloDeWindowSnap: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "windowsnap",
        nombre: "Snap",
        icono: "macwindow.split.2x1",
        color: Paleta.hexWindowSnap,
        lado: .derecha
    )
    public let tamanoExpandido = Medidas.windowSnap
    public let modelo: ModeloDeWindowSnap

    public init(modelo: ModeloDeWindowSnap) {
        self.modelo = modelo
    }

    public var salud: SaludDeModulo {
        modelo.puerto.tienePermisoAccesibilidad ? .listo : .faltaPermiso("Accesibilidad")
    }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeWindowSnap(modelo: modelo))
    }

    public func arrancar() {}
    public func detener() {}
}

struct VistaDeWindowSnap: View {
    let modelo: ModeloDeWindowSnap
    @State private var disposicionHover: DisposicionDeVentana?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            encabezado
            tiraDiezZonas
            filaExtraYEstado
        }
        .padding(.horizontal, 4)
        .onAppear { modelo.refrescarPermiso() }
    }

    private var encabezado: some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow.split.2x1")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Paleta.windowSnap)

            Text("Window Snap")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Paleta.texto)

            HStack(spacing: 5) {
                iconoApp(bundleId: modelo.bundleIdApp)
                    .frame(width: 14, height: 14)
                Text(modelo.nombreApp)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Paleta.texto)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Paleta.superficieAlta, in: Capsule())

            Spacer(minLength: 0)

            if let hover = disposicionHover {
                Text(hover.titulo)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Paleta.windowSnap)
            } else if let estado = modelo.estadoMensaje {
                Text(estado)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .lineLimit(1)
            }

            if !modelo.tienePermiso {
                Button("Permitir Accesibilidad") {
                    modelo.pedirPermiso()
                }
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Paleta.windowSnap, in: Capsule())
                .buttonStyle(.plain)
            }
        }
    }

    private var tiraDiezZonas: some View {
        HStack(spacing: 6) {
            ForEach(ModeloDeWindowSnap.filaPrincipal) { disp in
                casillaDiagrama(disp)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Paleta.borde.opacity(0.75), lineWidth: 1)
        )
    }

    private func casillaDiagrama(_ disp: DisposicionDeVentana) -> some View {
        let esHover = disposicionHover == disp
        let esActiva = modelo.ultimaDisposicion == disp

        return Button {
            modelo.aplicar(disp)
        } label: {
            VStack(spacing: 5) {
                DiagramaDeVentana(
                    disposicion: disp,
                    resaltado: esHover || esActiva
                )
                .frame(width: 42, height: 30)

                Text(etiquetaCorta(disp))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(esHover || esActiva ? Paleta.texto : Paleta.textoDeApoyo)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                (esHover || esActiva) ? Paleta.superficieAlta : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima in
            disposicionHover = encima ? disp : (disposicionHover == disp ? nil : disposicionHover)
        }
        .help("\(disp.titulo) para \(modelo.nombreApp)")
    }

    private var filaExtraYEstado: some View {
        HStack(spacing: 8) {
            ForEach(ModeloDeWindowSnap.filaSecundaria) { disp in
                Button {
                    modelo.aplicar(disp)
                } label: {
                    HStack(spacing: 6) {
                        DiagramaDeVentana(
                            disposicion: disp,
                            resaltado: modelo.ultimaDisposicion == disp
                        )
                        .frame(width: 22, height: 15)

                        Text(disp.titulo)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Paleta.texto)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Paleta.superficie, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Paleta.borde.opacity(0.6), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Text("Haz clic en cualquier mosaico para redimensionar \(modelo.nombreApp)")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Paleta.textoDeApoyo)
                .lineLimit(1)
        }
    }

    private func etiquetaCorta(_ disp: DisposicionDeVentana) -> String {
        switch disp {
        case .cuartoSupIzq: "Top L"
        case .cuartoInfIzq: "Bot L"
        case .cuartoSupDer: "Top R"
        case .cuartoInfDer: "Bot R"
        case .mitadIzquierda: "Left ½"
        case .maximizar: "Full"
        case .mitadDerecha: "Right ½"
        case .tercioIzquierdo: "Left ⅓"
        case .tercioCentral: "Mid ⅓"
        case .tercioDerecho: "Right ⅓"
        case .mitadSuperior: "Top ½"
        case .mitadInferior: "Bot ½"
        case .centrar: "Center"
        }
    }

    @ViewBuilder
    private func iconoApp(bundleId: String?) -> some View {
        if let bundleId,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "macwindow")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Paleta.windowSnap)
        }
    }
}

/// Dibuja la miniatura del layout de ventana igual que en la referencia de Window Snap.
struct DiagramaDeVentana: View {
    let disposicion: DisposicionDeVentana
    let resaltado: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r = disposicion.rectanguloNormalizado
            let pad: CGFloat = 3
            let inW = max(4, w - pad * 2)
            let inH = max(4, h - pad * 2)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        resaltado ? Color.white.opacity(0.85) : Color.white.opacity(0.42),
                        lineWidth: 1.4
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )

                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(resaltado ? Paleta.windowSnap : Color.white.opacity(0.68))
                    .frame(
                        width: max(4, inW * r.ancho),
                        height: max(4, inH * r.alto)
                    )
                    .offset(
                        x: pad + inW * r.x,
                        y: pad + inH * r.y
                    )
            }
        }
    }
}
