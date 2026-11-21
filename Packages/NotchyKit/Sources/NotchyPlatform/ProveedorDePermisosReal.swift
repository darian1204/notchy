import AVFoundation
import EventKit
import NotchyCore
import ServiceManagement

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

/// Registra o desregistra Notchy como ítem de inicio de sesión usando `SMAppService.mainApp` (SIS-3).
public struct AdaptadorDeInicioAlAbrirSesion: ServicioDeInicioAlAbrirSesion {
    public init() {}

    public func estado() -> EstadoDeInicioAlAbrirSesion {
        traducir(SMAppService.mainApp.status)
    }

    @discardableResult
    public func aplicar(activo: Bool) -> EstadoDeInicioAlAbrirSesion {
        do {
            if activo {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Si falla (ej. requiere aprobación o sin firmar fuera de bundle), devolvemos el estado real actual.
        }
        return estado()
    }

    public func abrirAjustesDeItemsDeInicio() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func traducir(_ status: SMAppService.Status) -> EstadoDeInicioAlAbrirSesion {
        switch status {
        case .enabled: .activo
        case .notRegistered: .inactivo
        case .requiresApproval: .requiereAprobacion
        case .notFound: .noDisponible
        @unknown default: .noDisponible
        }
    }
}
