import NotchyCore
import NotchyDesign
import SwiftUI

/// Módulo de Espejo (`300 × 232 pt`): vista previa espejada de la cámara que se apaga al cerrar (ESP-1).
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
        VStack(spacing: 6) {
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

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(modelo.encendida ? Paleta.musica : Paleta.textoDeApoyo)
                        .frame(width: 6, height: 6)
                    Text("Espejado")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Paleta.texto)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Paleta.superficieAlta, in: Capsule())

                Spacer(minLength: 0)

                Text(modelo.nombreDispositivo)
                    .textoDeApoyo()
                    .lineLimit(1)
            }
        }
        .task {
            await modelo.abrirEspejo()
        }
        .onDisappear {
            Task { await modelo.cerrarEspejo() }
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
