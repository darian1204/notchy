import Carbon.HIToolbox
import NotchyCore
import OSLog

/// Registra el atajo global de la isla y la tecla Escape usando `RegisterEventHotKey` de Carbon (D-19).
/// No requiere permiso de Accesibilidad.
@MainActor
public final class RegistradorDeAtajosCarbon: RegistradorDeAtajos {
    public var alPulsarAtajo: (@MainActor () -> Void)?
    public var alPulsarEscape: (@MainActor () -> Void)?

    private static let firma: OSType = 0x4E54_4348  // 'NTCH'
    private static let idAtajo: UInt32 = 1
    private static let idEscape: UInt32 = 2

    private let log = Registro.de(.isla)
    private var manejador: EventHandlerRef?
    private var refAtajo: EventHotKeyRef?
    private var refEscape: EventHotKeyRef?

    public init() {}

    @discardableResult
    public func registrar(_ atajo: AtajoDeIsla) -> Bool {
        desregistrarAtajo()
        guard let combinacion = Self.combinacion(para: atajo) else { return true }
        instalarManejadorSiHaceFalta()

        let id = EventHotKeyID(signature: Self.firma, id: Self.idAtajo)
        var ref: EventHotKeyRef?
        let estado = RegisterEventHotKey(
            combinacion.codigo, combinacion.modificadores, id, GetApplicationEventTarget(), 0, &ref)
        guard estado == noErr, let ref else {
            log.error("No se pudo registrar el atajo \(atajo.etiqueta, privacy: .public) (código \(estado))")
            return false
        }
        refAtajo = ref
        return true
    }

    public func activarEscape(_ activo: Bool) {
        if activo {
            guard refEscape == nil else { return }
            instalarManejadorSiHaceFalta()
            let id = EventHotKeyID(signature: Self.firma, id: Self.idEscape)
            var ref: EventHotKeyRef?
            let estado = RegisterEventHotKey(
                UInt32(kVK_Escape), 0, id, GetApplicationEventTarget(), 0, &ref)
            if estado == noErr {
                refEscape = ref
            }
        } else {
            if let ref = refEscape {
                UnregisterEventHotKey(ref)
                refEscape = nil
            }
        }
    }

    public func detener() {
        desregistrarAtajo()
        activarEscape(false)
        if let manejador {
            RemoveEventHandler(manejador)
            self.manejador = nil
        }
    }

    static func combinacion(para atajo: AtajoDeIsla) -> (codigo: UInt32, modificadores: UInt32)? {
        switch atajo {
        case .ninguno:
            nil
        case .controlOpcionEspacio:
            (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .controlOpcionN:
            (UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey))
        case .opcionComandoN:
            (UInt32(kVK_ANSI_N), UInt32(optionKey | cmdKey))
        }
    }

    private func desregistrarAtajo() {
        if let ref = refAtajo {
            UnregisterEventHotKey(ref)
            refAtajo = nil
        }
    }

    private func instalarManejadorSiHaceFalta() {
        guard manejador == nil else { return }
        var especificacion = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let puntero = Unmanaged.passUnretained(self).toOpaque()
        var ref: EventHandlerRef?
        let estado = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, evento, datos -> OSStatus in
                guard let evento, let datos else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let resultado = GetEventParameter(
                    evento, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard resultado == noErr, id.signature == RegistradorDeAtajosCarbon.firma else {
                    return OSStatus(eventNotHandledErr)
                }
                let instancia = Unmanaged<RegistradorDeAtajosCarbon>.fromOpaque(datos).takeUnretainedValue()
                let codigo = id.id
                MainActor.assumeIsolated {
                    instancia.despachar(codigo)
                }
                return noErr
            },
            1, &especificacion, puntero, &ref)
        if estado == noErr {
            manejador = ref
        }
    }

    private func despachar(_ id: UInt32) {
        switch id {
        case Self.idAtajo: alPulsarAtajo?()
        case Self.idEscape: alPulsarEscape?()
        default: break
        }
    }
}
