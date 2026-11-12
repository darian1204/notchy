import AVFoundation
import EventKit
import NotchyCore

/// Consulta y solicita permisos reales de macOS (AVFoundation y EventKit).
public struct ProveedorDePermisosReal: ProveedorDePermisos {
    public init() {}

    public func estado(de permiso: PermisoDelSistema) -> EstadoDePermiso {
        switch permiso {
        case .microfono:
            traducir(AVCaptureDevice.authorizationStatus(for: .audio))
        case .camara:
            traducir(AVCaptureDevice.authorizationStatus(for: .video))
        case .calendario:
            traducir(EKEventStore.authorizationStatus(for: .event))
        case .recordatorios:
            traducir(EKEventStore.authorizationStatus(for: .reminder))
        }
    }

    public func pedir(_ permiso: PermisoDelSistema) async -> EstadoDePermiso {
        switch permiso {
        case .microfono:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .camara:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .calendario:
            _ = try? await EKEventStore().requestFullAccessToEvents()
        case .recordatorios:
            _ = try? await EKEventStore().requestFullAccessToReminders()
        }
        return estado(de: permiso)
    }

    private func traducir(_ estado: AVAuthorizationStatus) -> EstadoDePermiso {
        switch estado {
        case .notDetermined: .sinPedir
        case .authorized: .concedido
        case .denied: .denegado
        case .restricted: .restringido
        @unknown default: .denegado
        }
    }

    private func traducir(_ estado: EKAuthorizationStatus) -> EstadoDePermiso {
        switch estado {
        case .notDetermined: .sinPedir
        case .fullAccess, .authorized: .concedido
        case .writeOnly, .denied: .denegado
        case .restricted: .restringido
        @unknown default: .denegado
        }
    }
}
