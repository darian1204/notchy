import AVFoundation
import AppKit
import NotchyCore
import SwiftUI

nonisolated private final class CajaDeSesion: @unchecked Sendable {
    let sesion = AVCaptureSession()
}

/// Adaptador real de la cámara del Mac para el módulo de Espejo (ESP-1, S11).
@MainActor
public final class AdaptadorDeCamara: PuertoDeCamara {
    private let caja = CajaDeSesion()
    private let cola = DispatchQueue(label: "dev.darian.notchy.camara")
    public private(set) var encendida = false
    public private(set) var nombreDispositivo = "MacBook Air Camera"
    private var configurada = false

    public init() {}

    public var vistaPrevia: AnyView {
        AnyView(RepresentablePreviaDeCamara(sesion: caja.sesion))
    }

    public func estadoDePermiso() -> EstadoDePermiso {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .sinPedir
        case .authorized: .concedido
        case .denied: .denegado
        case .restricted: .restringido
        @unknown default: .denegado
        }
    }

    public func pedirPermiso() async -> EstadoDePermiso {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return estadoDePermiso()
    }

    public func encender() async throws {
        guard estadoDePermiso() == .concedido else {
            throw NotchyError.noDisponible("Falta permiso de Cámara")
        }
        let sesion = caja.sesion
        if !configurada {
            guard let camara = AVCaptureDevice.default(for: .video) else {
                throw NotchyError.noDisponible("No se encontró cámara en el Mac")
            }
            guard !camara.isInUseByAnotherApplication else {
                throw NotchyError.noDisponible("La cámara está ocupada por otra app")
            }
            let entrada: AVCaptureDeviceInput
            do {
                entrada = try AVCaptureDeviceInput(device: camara)
            } catch {
                throw NotchyError.noDisponible("No se pudo abrir la cámara")
            }
            guard sesion.canAddInput(entrada) else {
                throw NotchyError.noDisponible("La cámara está ocupada")
            }
            sesion.beginConfiguration()
            sesion.sessionPreset = .medium
            sesion.addInput(entrada)
            sesion.commitConfiguration()
            configurada = true
            nombreDispositivo = camara.localizedName
        }

        let cajaCapturada = caja
        let corriendo: Bool = await withCheckedContinuation { continuacion in
            cola.async {
                if !cajaCapturada.sesion.isRunning {
                    cajaCapturada.sesion.startRunning()
                }
                continuacion.resume(returning: cajaCapturada.sesion.isRunning)
            }
        }
        encendida = corriendo
        if !corriendo {
            throw NotchyError.noDisponible("La cámara no pudo iniciar")
        }
    }

    public func apagar() async {
        let cajaCapturada = caja
        await withCheckedContinuation { (continuacion: CheckedContinuation<Void, Never>) in
            cola.async {
                if cajaCapturada.sesion.isRunning {
                    cajaCapturada.sesion.stopRunning()
                }
                continuacion.resume()
            }
        }
        encendida = false
    }
}

private struct RepresentablePreviaDeCamara: NSViewRepresentable {
    let sesion: AVCaptureSession

    func makeNSView(context: Context) -> VistaCapaPreviaDeCamara {
        let vista = VistaCapaPreviaDeCamara(sesion: sesion)
        vista.aplicarEspejado()
        return vista
    }

    func updateNSView(_ nsView: VistaCapaPreviaDeCamara, context: Context) {
        nsView.aplicarEspejado()
    }
}

final class VistaCapaPreviaDeCamara: NSView {
    private let capaPrevia: AVCaptureVideoPreviewLayer

    init(sesion: AVCaptureSession) {
        self.capaPrevia = AVCaptureVideoPreviewLayer(session: sesion)
        super.init(frame: .zero)
        wantsLayer = true
        capaPrevia.videoGravity = .resizeAspectFill
        layer = capaPrevia
        aplicarEspejado()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("No soportado")
    }

    override func layout() {
        super.layout()
        aplicarEspejado()
    }

    func aplicarEspejado() {
        if let conexion = capaPrevia.connection {
            if conexion.isVideoMirroringSupported {
                conexion.automaticallyAdjustsVideoMirroring = false
                conexion.isVideoMirrored = true
            }
        }
    }
}
