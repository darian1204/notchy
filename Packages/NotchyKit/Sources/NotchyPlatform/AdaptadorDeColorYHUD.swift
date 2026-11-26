import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import IOKit.ps
import NotchyCore
import OSLog

/// Adaptador real de NSColorSampler y NSPasteboard para el módulo de Color Picker.
@MainActor
public final class AdaptadorMuestreadorDeColor: PuertoMuestreadorDeColor {
    public init() {}

    public func muestrearColorEnPantalla() async -> ColorMuestreado? {
        let muestreador = NSColorSampler()
        guard let nsColor = await muestreador.sample(),
            let srgb = nsColor.usingColorSpace(.sRGB)
        else {
            return nil
        }
        return ColorMuestreado(
            rojo: Double(srgb.redComponent),
            verde: Double(srgb.greenComponent),
            azul: Double(srgb.blueComponent)
        )
    }

    public func copiarAlPortapapeles(_ texto: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(texto, forType: .string)
    }
}

/// Vigila volumen, brillo (teclas multimedia NX_KEYTYPE) y batería para disparar el System HUD en el notch.
@MainActor
public final class VigilanteDeHUDSistema {
    private var monitorGlobal: Any?
    private var monitorLocal: Any?
    /// Aviso del sistema cuando cambia la fuente de energía o la carga. Sustituye el sondeo cada 15 s.
    private var fuenteDeAvisosDeEnergia: CFRunLoopSource?
    private var ultimoNivelBateria: Int?
    private var ultimaFuenteEnergia: String?
    private let alDisparar: @MainActor (EstadoDeHUDSistema) -> Void

    public init(alDisparar: @escaping @MainActor (EstadoDeHUDSistema) -> Void) {
        self.alDisparar = alDisparar
    }

    public func iniciar() {
        detener()
        let mascara = NSEvent.EventTypeMask(rawValue: 1 << 14)  // NSEvent.EventType.systemDefined
        monitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: mascara) { [weak self] evento in
            MainActor.assumeIsolated { self?.procesarEventoDeSistema(evento) }
        }
        monitorLocal = NSEvent.addLocalMonitorForEvents(matching: mascara) { [weak self] evento in
            MainActor.assumeIsolated { self?.procesarEventoDeSistema(evento) }
            return evento
        }
        iniciarVigilanciaDeBateria()
    }

    public func detener() {
        if let monitorGlobal { NSEvent.removeMonitor(monitorGlobal) }
        if let monitorLocal { NSEvent.removeMonitor(monitorLocal) }
        monitorGlobal = nil
        monitorLocal = nil
        if let fuenteDeAvisosDeEnergia {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), fuenteDeAvisosDeEnergia, .defaultMode)
        }
        fuenteDeAvisosDeEnergia = nil
    }

    private func procesarEventoDeSistema(_ evento: NSEvent) {
        guard evento.subtype.rawValue == 8 else { return }
        let data1 = evento.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0x0000_FFFF
        let presionada = ((keyFlags & 0xFF00) >> 8) == 0x0A
        guard presionada else { return }

        switch keyCode {
        case 0, 1, 7:
            // NX_KEYTYPE_SOUND_UP (0), SOUND_DOWN (1), MUTE (7)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(45))
                guard let self else { return }
                let (volumen, silenciado) = Self.leerVolumenDeSalida()
                let hud = EstadoDeHUDSistema(
                    tipo: silenciado || volumen <= 0.001 ? .silencio : .volumen,
                    nivel: silenciado ? 0 : volumen
                )
                self.alDisparar(hud)
            }
        case 2, 3:
            // NX_KEYTYPE_BRIGHTNESS_UP (2), BRIGHTNESS_DOWN (3)
            // Se lee el brillo real después de que macOS aplica el cambio; solo se estima si no hay lectura.
            let delta = keyCode == 2 ? 0.0625 : -0.0625
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(60))
                guard let self else { return }
                let nivel = Self.leerBrilloDePantalla() ?? Self.estimarBrillo(delta: delta)
                self.alDisparar(EstadoDeHUDSistema(tipo: .brillo, nivel: nivel))
            }
        default:
            break
        }
    }

    private static var brilloEstimado: Double = 0.5

    private static func estimarBrillo(delta: Double) -> Double {
        brilloEstimado = min(max(brilloEstimado + delta, 0.0), 1.0)
        return brilloEstimado
    }

    private typealias FuncionLeerBrillo = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32

    /// `DisplayServicesGetBrightness` (framework privado) devuelve el brillo real de la pantalla integrada (0…1).
    private static let funcionLeerBrillo: FuncionLeerBrillo? = {
        let ruta = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(ruta, RTLD_LAZY),
            let simbolo = dlsym(handle, "DisplayServicesGetBrightness")
        else {
            return nil
        }
        return unsafeBitCast(simbolo, to: FuncionLeerBrillo.self)
    }()

    /// Brillo real de la pantalla integrada (o la principal si no hay integrada).
    public static func leerBrilloDePantalla() -> Double? {
        guard let leer = funcionLeerBrillo else { return nil }
        var pantallas = [CGDirectDisplayID](repeating: 0, count: 8)
        var cantidad: UInt32 = 0
        CGGetOnlineDisplayList(UInt32(pantallas.count), &pantallas, &cantidad)
        let candidatas = pantallas.prefix(Int(cantidad))
        let pantalla = candidatas.first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? CGMainDisplayID()
        var brillo: Float = 0
        guard leer(pantalla, &brillo) == 0 else { return nil }
        let nivel = Double(min(max(brillo, 0), 1))
        brilloEstimado = nivel
        return nivel
    }

    public static func leerVolumenDeSalida() -> (volumen: Double, silenciado: Bool) {
        var dispositivo = AudioObjectID(kAudioObjectUnknown)
        var tamano = UInt32(MemoryLayout<AudioObjectID>.size)
        var direccionDispositivo = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let estadoDispositivo = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &direccionDispositivo,
            0,
            nil,
            &tamano,
            &dispositivo
        )
        guard estadoDispositivo == noErr, dispositivo != kAudioObjectUnknown else {
            return (0.5, false)
        }

        var mute: UInt32 = 0
        var tamanoMute = UInt32(MemoryLayout<UInt32>.size)
        var direccionMute = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectGetPropertyData(dispositivo, &direccionMute, 0, nil, &tamanoMute, &mute)

        var volumen: Float32 = 0.5
        var tamanoVol = UInt32(MemoryLayout<Float32>.size)
        var direccionVol = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(dispositivo, &direccionVol, 0, nil, &tamanoVol, &volumen) != noErr {
            var canal1 = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 1
            )
            _ = AudioObjectGetPropertyData(dispositivo, &canal1, 0, nil, &tamanoVol, &volumen)
        }
        return (Double(min(max(volumen, 0), 1)), mute != 0)
    }

    private func iniciarVigilanciaDeBateria() {
        if let inicial = Self.leerEstadoDeBateria() {
            ultimoNivelBateria = inicial.porcentaje
            ultimaFuenteEnergia = inicial.fuente
        }
        // La función de C no captura nada: recibe `self` como contexto. El aviso llega en el run loop
        // principal, así que ya está en el hilo principal.
        let contexto = Unmanaged.passUnretained(self).toOpaque()
        let aviso: IOPowerSourceCallbackType = { contexto in
            guard let contexto else { return }
            let vigilante = Unmanaged<VigilanteDeHUDSistema>.fromOpaque(contexto).takeUnretainedValue()
            MainActor.assumeIsolated { vigilante.revisarBateria() }
        }
        guard let fuente = IOPSNotificationCreateRunLoopSource(aviso, contexto)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), fuente, .defaultMode)
        fuenteDeAvisosDeEnergia = fuente
    }

    private func revisarBateria() {
        guard let actual = Self.leerEstadoDeBateria() else { return }
        let cambioFuente = ultimaFuenteEnergia != nil && actual.fuente != ultimaFuenteEnergia
        let enBateria = actual.fuente != (kIOPSACPowerValue as String)
        // Solo al bajar: cargando de 9 % a 10 % no es un aviso.
        let bajoAlLimite =
            enBateria && (actual.porcentaje == 20 || actual.porcentaje == 10)
            && (ultimoNivelBateria.map { $0 > actual.porcentaje } ?? false)
        ultimoNivelBateria = actual.porcentaje
        ultimaFuenteEnergia = actual.fuente
        guard cambioFuente || bajoAlLimite else { return }
        alDisparar(
            EstadoDeHUDSistema(
                tipo: Self.tipoDeAvisoDeBateria(cambioDeFuente: cambioFuente, fuente: actual.fuente),
                nivel: Double(actual.porcentaje) / 100.0,
                etiqueta: "\(actual.porcentaje)%"
            ))
    }

    /// Conectar o desconectar gana sobre el aviso de batería baja.
    static func tipoDeAvisoDeBateria(cambioDeFuente: Bool, fuente: String) -> TipoDeHUD {
        guard cambioDeFuente else { return .bateriaBaja }
        return fuente == (kIOPSACPowerValue as String) ? .cargando : .desconectado
    }

    public static func leerEstadoDeBateria() -> (porcentaje: Int, fuente: String)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let lista = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
            let primera = lista.first,
            let desc = IOPSGetPowerSourceDescription(blob, primera)?.takeUnretainedValue() as? [String: Any],
            let capacidad = desc[kIOPSCurrentCapacityKey as String] as? Int
        else {
            return nil
        }
        let fuente = (desc[kIOPSPowerSourceStateKey as String] as? String) ?? "Battery"
        return (capacidad, fuente)
    }
}
