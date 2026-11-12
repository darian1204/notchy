import AVFoundation
import AppKit
import CoreImage
import NotchyCore
import SwiftUI

nonisolated private final class CajaDeSesion: @unchecked Sendable {
    let sesion = AVCaptureSession()
    let salidaVideo = AVCaptureVideoDataOutput()
}

nonisolated private final class CapturadorDeCuadro: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable
{
    private let candado = NSLock()
    private var ultimaImagen: CIImage?

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        candado.lock()
        ultimaImagen = ciImage
        candado.unlock()
    }

    func renderizarUltimaFotoEspejadaPNG() -> Data? {
        candado.lock()
        let copia = ultimaImagen
        candado.unlock()
        guard let original = copia else { return nil }

        let extensionRect = original.extent
        let espejada =
            original
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            .transformed(by: CGAffineTransform(translationX: extensionRect.width, y: 0))

        let contexto = CIContext(options: nil)
        guard let cgImage = contexto.createCGImage(espejada, from: espejada.extent) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}

/// Adaptador real de la cámara del Mac para el módulo de Espejo (ESP-1, S11).
@MainActor
public final class AdaptadorDeCamara: PuertoDeCamara {
    private let caja = CajaDeSesion()
    private let capturador = CapturadorDeCuadro()
    private let cola = DispatchQueue(label: "dev.darian.notchy.camara")
    private let colaCuadros = DispatchQueue(label: "dev.darian.notchy.camara.cuadros")
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
        let salidaVideo = caja.salidaVideo
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
            salidaVideo.alwaysDiscardsLateVideoFrames = true
            salidaVideo.setSampleBufferDelegate(capturador, queue: colaCuadros)

            sesion.beginConfiguration()
            sesion.sessionPreset = .high
            sesion.addInput(entrada)
            if sesion.canAddOutput(salidaVideo) {
                sesion.addOutput(salidaVideo)
            }
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

    public func capturarFotoPNG() async throws -> Data {
        guard encendida else {
            throw NotchyError.noDisponible("La cámara no está encendida")
        }
        let capturadorLocal = capturador
        let datos: Data? = await withCheckedContinuation { continuacion in
            colaCuadros.async {
                continuacion.resume(returning: capturadorLocal.renderizarUltimaFotoEspejadaPNG())
            }
        }
        guard let datos else {
            throw NotchyError.noDisponible("Aún no hay cuadro listo para capturar")
        }
        return datos
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
