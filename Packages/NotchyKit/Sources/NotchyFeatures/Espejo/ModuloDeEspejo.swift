import AppKit
import NotchyCore
import NotchyDesign
import SwiftUI

/// Módulo de Espejo (`560 × 232 pt`): vista previa espejada que conserva todas las orejas del notch y permite tomar fotos (ESP-1).
@MainActor
public final class ModuloDeEspejo: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "espejo",
        nombre: "Espejo",
        icono: "camera.fill",
        color: Paleta.hexEspejo,
        lado: .izquierda
    )
    public let tamanoExpandido = Medidas.espejo
    public let modelo: ModeloDeEspejo

    public init(modelo: ModeloDeEspejo) {
        self.modelo = modelo
    }

    public var salud: SaludDeModulo {
        modelo.salud
    }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeEspejo(modelo: modelo))
    }

    public func arrancar() {
        modelo.iniciar()
    }

    public func detener() {
        modelo.detener()
    }
}

struct VistaDeEspejo: View {
    let modelo: ModeloDeEspejo

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Paleta.superficie)

                if modelo.permiso != .concedido {
                    vistaFaltaPermiso
                } else if let error = modelo.mensajeDeError {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Paleta.espejo)
                        Text(error)
                            .textoDeApoyo()
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                } else {
                    modelo.vistaPrevia
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(modelo.encendida ? Paleta.musica : Paleta.textoDeApoyo)
                        .frame(width: 6, height: 6)
                    Text("Espejado · 2s")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Paleta.texto)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Paleta.superficieAlta, in: Capsule())

                Text(modelo.nombreDispositivo)
                    .textoDeApoyo()
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    Task { await modelo.tomarFoto() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.shutter.button.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Tomar foto")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(EstiloDePildora(destacado: true))
                .disabled(!modelo.encendida)
                .accessibilityLabel("Tomar foto en Espejo")

                HStack(spacing: 6) {
                    Button {
                        elegirCarpetaDestino()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                            Text(modelo.nombreCarpetaFotos)
                                .lineLimit(1)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Paleta.textoDeApoyo)
                    }
                    .buttonStyle(.plain)
                    .help("Elegir carpeta donde guardar las fotos")

                    Spacer(minLength: 0)

                    if let foto = modelo.ultimaFotoGuardada {
                        Button {
                            modelo.abrirUltimaFoto()
                        } label: {
                            Text("Abrir foto")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Paleta.espejo)
                        }
                        .buttonStyle(.plain)
                        .onDrag {
                            NSItemProvider(object: foto as NSURL)
                        }
                        .help("Abrir o arrastrar la última foto tomada")
                    }
                }
            }
            .frame(width: 170)
        }
        .task {
            await modelo.abrirEspejo()
        }
        .onDisappear {
            Task { await modelo.cerrarEspejo() }
        }
    }

    private func elegirCarpetaDestino() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: modelo.carpetaFotos)
        panel.prompt = "Guardar aquí"
        if panel.runModal() == .OK, let url = panel.url {
            modelo.carpetaFotos = url.path
        }
    }

    private var vistaFaltaPermiso: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.fill")
                .font(.system(size: 20))
                .foregroundStyle(Paleta.espejo)
            Text(
                modelo.permiso == .sinPedir
                    ? "Permite el acceso a la cámara para usar el espejo."
                    : "El permiso de Cámara está denegado."
            )
            .textoDeApoyo()
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)

            if modelo.permiso == .sinPedir {
                Button("Permitir Cámara") {
                    Task { await modelo.abrirEspejo() }
                }
                .buttonStyle(EstiloDePildora(destacado: true))
            } else {
                Button("Abrir Ajustes…") {
                    modelo.abrirAjustesDePermiso()
                }
                .buttonStyle(EstiloDePildora())
            }
        }
    }
}
