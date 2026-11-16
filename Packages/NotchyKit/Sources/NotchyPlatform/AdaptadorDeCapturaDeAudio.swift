import AVFoundation
import AppKit
import CoreAudio
import Foundation
import NotchyCore
import OSLog

/// Adaptador real de captura de micrófono (`AVCaptureSession`) y audio del sistema
/// (`CATapDescription` + dispositivo agregado de Core Audio), con las correcciones de S3
/// y vigilancia de reposo y cambio de dispositivo (GRB-1, GRB-2, GRB-7).
@MainActor
public final class AdaptadorDeCapturaDeAudio: PuertoDeCapturaDeAudio {
    public private(set) var capturando = false
    private let log = Registro.de(.grabadora)
    private var capturadorMic: CapturadorMicrofonoInterno?
    private var capturadorSistema: CapturadorSistemaInterno?
    private var observadoresEntorno: [NSObjectProtocol] = []
    private var incluirSistemaActivo = false
    private var preferirInternoActivo = true
    private var callbackBloque: (@Sendable (BloqueDeAudioPCM) -> Void)?
    private var callbackEntorno: (@Sendable (EventoDeEntornoDeAudio) -> Void)?

    public init() {}

    public var estadisticas: EstadisticasDeCapturaDeAudio {
        let m = capturadorMic?.contador.foto
        let s = capturadorSistema?.contador.foto
        let desfase: Double?
        if let mh = m?.primerHostMs, let sh = s?.primerHostMs, mh > 0, sh > 0 {
            desfase = mh - sh
        } else {
            desfase = nil
        }
        return EstadisticasDeCapturaDeAudio(
            nombreMicrofono: capturadorMic?.nombreDispositivo ?? "Micrófono",
            usaMicrofonoInterno: capturadorMic?.usaInterno ?? false,
            formatoMicrofono: capturadorMic?.formatoTexto ?? "",
            formatoSistema: capturadorSistema?.formatoTexto ?? "",
            bloquesMicrofono: m?.bloques ?? 0,
            cortesMicrofono: m?.cortes ?? 0,
            bloquesSistema: s?.bloques ?? 0,
            cortesSistema: s?.cortes ?? 0,
            desfaseInicialMs: desfase
        )
    }

    public func estadoDePermisoMicrofono() -> EstadoDePermiso {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: .sinPedir
        case .authorized: .concedido
        case .denied: .denegado
        case .restricted: .restringido
        @unknown default: .denegado
        }
    }

    public func pedirPermisoMicrofono() async -> EstadoDePermiso {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        return estadoDePermisoMicrofono()
    }

    public func iniciarCaptura(
        incluirSistema: Bool,
        preferirMicrofonoInterno: Bool,
        alRecibirBloque: @escaping @Sendable (BloqueDeAudioPCM) -> Void,
        alCambiarEntorno: @escaping @Sendable (EventoDeEntornoDeAudio) -> Void
    ) async throws {
        await detenerCaptura()
        incluirSistemaActivo = incluirSistema
        preferirInternoActivo = preferirMicrofonoInterno
        callbackBloque = alRecibirBloque
        callbackEntorno = alCambiarEntorno

        try await arrancarMotores(
            incluirSistema: incluirSistema,
            preferirMicrofonoInterno: preferirMicrofonoInterno,
            alRecibirBloque: alRecibirBloque,
            alCambiarEntorno: alCambiarEntorno
        )
        instalarObservadoresDeEntorno()
        capturando = true
    }

    public func detenerCaptura() async {
        quitarObservadoresDeEntorno()
        capturadorMic?.detener()
        capturadorSistema?.detener()
        capturadorMic = nil
        capturadorSistema = nil
        capturando = false
    }

    private func arrancarMotores(
        incluirSistema: Bool,
        preferirMicrofonoInterno: Bool,
        alRecibirBloque: @escaping @Sendable (BloqueDeAudioPCM) -> Void,
        alCambiarEntorno: @escaping @Sendable (EventoDeEntornoDeAudio) -> Void
    ) async throws {
        let mic = CapturadorMicrofonoInterno(
            alRecibir: alRecibirBloque,
            alFallar: { detalle in
                alCambiarEntorno(.falloDeFuente(fuente: .microfono, detalle: detalle))
            }
        )
        try mic.iniciar(preferirInterno: preferirMicrofonoInterno)
        capturadorMic = mic

        guard incluirSistema else { return }
        if !mic.usaInterno {
            // S3: si se abrió un micrófono Bluetooth, los audífonos tardan en cambiar a modo llamada (16 kHz).
            try? await Task.sleep(for: .milliseconds(1500))
        }
        let sis = CapturadorSistemaInterno(
            alRecibir: alRecibirBloque,
            alFallar: { detalle in
                alCambiarEntorno(.falloDeFuente(fuente: .sistema, detalle: detalle))
            }
        )
        do {
            try sis.iniciar()
            capturadorSistema = sis
        } catch {
            // En reuniones, si falla el tap del sistema seguimos con el micrófono y avisamos (notchy-modulos.md).
            log.error("No se pudo iniciar el tap del sistema: \(error.localizedDescription, privacy: .public)")
            alCambiarEntorno(.falloDeFuente(fuente: .sistema, detalle: error.localizedDescription))
        }
    }

    private func instalarObservadoresDeEntorno() {
        quitarObservadoresDeEntorno()
        let ws = NSWorkspace.shared.notificationCenter
        let obsDormir = ws.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.capturando else { return }
                self.capturadorMic?.detener()
                self.capturadorSistema?.detener()
                self.callbackEntorno?(.reposoDelMacIniciado)
            }
        }
        let obsDespertar = ws.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.capturando,
                    let cbBloque = self.callbackBloque,
                    let cbEntorno = self.callbackEntorno
                else { return }
                try? await Task.sleep(for: .milliseconds(800))
                try? await self.arrancarMotores(
                    incluirSistema: self.incluirSistemaActivo,
                    preferirMicrofonoInterno: self.preferirInternoActivo,
                    alRecibirBloque: cbBloque,
                    alCambiarEntorno: cbEntorno
                )
                cbEntorno(.despertarDelMac)
            }
        }

        let nc = NotificationCenter.default
        let obsConectado = nc.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let nombre = (notif.object as? AVCaptureDevice)?.localizedName ?? "Dispositivo de audio"
            Task { @MainActor [weak self] in
                await self?.manejarCambioDeDispositivo(nombre: nombre)
            }
        }
        let obsDesconectado = nc.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let nombre = (notif.object as? AVCaptureDevice)?.localizedName ?? "Dispositivo de audio"
            Task { @MainActor [weak self] in
                await self?.manejarCambioDeDispositivo(nombre: nombre)
            }
        }
        observadoresEntorno = [obsDormir, obsDespertar, obsConectado, obsDesconectado]
    }

    private func manejarCambioDeDispositivo(nombre: String) async {
        guard capturando,
            let cbBloque = callbackBloque,
            let cbEntorno = callbackEntorno
        else { return }
        capturadorMic?.detener()
        capturadorSistema?.detener()
        cbEntorno(.cambioDeDispositivo(nombre: nombre))
        try? await Task.sleep(for: .milliseconds(400))
        try? await arrancarMotores(
            incluirSistema: incluirSistemaActivo,
            preferirMicrofonoInterno: preferirInternoActivo,
            alRecibirBloque: cbBloque,
            alCambiarEntorno: cbEntorno
        )
    }

    private func quitarObservadoresDeEntorno() {
        let ws = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default
        for obs in observadoresEntorno {
            ws.removeObserver(obs)
            nc.removeObserver(obs)
        }
        observadoresEntorno.removeAll()
    }
}

// MARK: - Contadores y Capturadores en hilo de audio

nonisolated final class ContadorDeFuenteAudio: @unchecked Sendable {
    private let lock = NSLock()
    private var _bloques = 0
    private var _cortes = 0
    private var _primerHostMs: Double = 0
    private var _siguienteMuestra: Double = -1

    func registrar(muestra: Double, frames: Int, hostMs: Double) {
        lock.lock()
        defer { lock.unlock() }
        if _primerHostMs == 0, hostMs > 0 {
            _primerHostMs = hostMs
        }
        if _siguienteMuestra >= 0, abs(muestra - _siguienteMuestra) > 1 {
            _cortes += 1
        }
        _siguienteMuestra = muestra + Double(frames)
        _bloques += 1
    }

    var foto: (bloques: Int, cortes: Int, primerHostMs: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (_bloques, _cortes, _primerHostMs)
    }

    static func hostTimeAMilisegundos(_ host: UInt64) -> Double {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        guard tb.denom > 0 else { return 0 }
        return Double(host) * Double(tb.numer) / Double(tb.denom) / 1_000_000
    }
}

nonisolated final class CapturadorMicrofonoInterno: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
    @unchecked Sendable
{
    let contador = ContadorDeFuenteAudio()
    private let sesion = AVCaptureSession()
    private let cola = DispatchQueue(label: "dev.darian.notchy.audio.mic", qos: .userInitiated)
    private let lock = NSLock()
    private let alRecibir: @Sendable (BloqueDeAudioPCM) -> Void
    private let alFallar: @Sendable (String) -> Void
    private var _formatoTexto = ""
    private var _usaInterno = false
    private var _nombreDispositivo = "Micrófono"

    init(
        alRecibir: @escaping @Sendable (BloqueDeAudioPCM) -> Void,
        alFallar: @escaping @Sendable (String) -> Void
    ) {
        self.alRecibir = alRecibir
        self.alFallar = alFallar
    }

    var formatoTexto: String {
        lock.lock()
        defer { lock.unlock() }
        return _formatoTexto
    }

    var usaInterno: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _usaInterno
    }

    var nombreDispositivo: String {
        lock.lock()
        defer { lock.unlock() }
        return _nombreDispositivo
    }

    func iniciar(preferirInterno: Bool) throws {
        var dispositivo = AVCaptureDevice.default(for: .audio)
        var esInterno = false
        if preferirInterno {
            let descubrimiento = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            )
            if let interno = descubrimiento.devices.first(where: {
                $0.transportType == Int32(bitPattern: kAudioDeviceTransportTypeBuiltIn)
            }) {
                dispositivo = interno
                esInterno = true
            }
        }
        guard let dispositivo else {
            throw NSError(
                domain: "NotchyAudio",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No se encontró ningún micrófono disponible."]
            )
        }
        lock.withLock {
            _nombreDispositivo = dispositivo.localizedName
            _usaInterno = esInterno
        }

        let entrada = try AVCaptureDeviceInput(device: dispositivo)
        let salida = AVCaptureAudioDataOutput()
        salida.setSampleBufferDelegate(self, queue: cola)
        guard sesion.canAddInput(entrada), sesion.canAddOutput(salida) else {
            throw NSError(
                domain: "NotchyAudio",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "El micrófono está ocupado por otra sesión."]
            )
        }
        sesion.addInput(entrada)
        sesion.addOutput(salida)
        sesion.startRunning()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let desc = sampleBuffer.formatDescription,
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc),
            let formato = AVAudioFormat(streamDescription: asbd)
        else { return }
        let n = AVAudioFrameCount(sampleBuffer.numSamples)
        guard n > 0, let buffer = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: n) else { return }
        buffer.frameLength = n
        guard
            CMSampleBufferCopyPCMDataIntoAudioBufferList(
                sampleBuffer,
                at: 0,
                frameCount: Int32(n),
                into: buffer.mutableAudioBufferList
            ) == noErr
        else {
            alFallar("No se pudo copiar un bloque del micrófono.")
            return
        }

        lock.withLock {
            if _formatoTexto.isEmpty {
                _formatoTexto = "\(Int(formato.sampleRate)) Hz, \(formato.channelCount) ch"
            }
        }

        let pts = sampleBuffer.presentationTimeStamp
        let muestra = (pts.seconds * formato.sampleRate).rounded()
        let hostUnits = CMClockConvertHostTimeToSystemUnits(pts)
        let hostMs = ContadorDeFuenteAudio.hostTimeAMilisegundos(hostUnits)
        contador.registrar(muestra: muestra, frames: Int(n), hostMs: hostMs)

        let muestrasMono = ExtraerMuestrasMono.extraer(de: buffer)
        let bloque = BloqueDeAudioPCM(
            fuente: .microfono,
            muestras: muestrasMono,
            frecuencia: formato.sampleRate,
            canales: 1,
            frames: muestrasMono.count,
            muestraInicial: muestra,
            marcaHostMs: hostMs
        )
        alRecibir(bloque)
    }

    func detener() {
        sesion.stopRunning()
    }
}

nonisolated final class CapturadorSistemaInterno: @unchecked Sendable {
    let contador = ContadorDeFuenteAudio()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var agregadoID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let cola = DispatchQueue(label: "dev.darian.notchy.audio.tap", qos: .userInitiated)
    private let lock = NSLock()
    private var _formatoTexto = ""
    private let alRecibir: @Sendable (BloqueDeAudioPCM) -> Void
    private let alFallar: @Sendable (String) -> Void

    init(
        alRecibir: @escaping @Sendable (BloqueDeAudioPCM) -> Void,
        alFallar: @escaping @Sendable (String) -> Void
    ) {
        self.alRecibir = alRecibir
        self.alFallar = alFallar
    }

    var formatoTexto: String {
        lock.lock()
        defer { lock.unlock() }
        return _formatoTexto
    }

    func iniciar() throws {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        try verificar(AudioHardwareCreateProcessTap(desc, &tapID), "crear tap del sistema")

        var asbd = AudioStreamBasicDescription()
        var tam = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var dir = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try verificar(
            AudioObjectGetPropertyData(tapID, &dir, 0, nil, &tam, &asbd),
            "leer formato del tap"
        )

        let salida = try uidSalidaPorDefecto()
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NotchySystemTap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: salida,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: salida]],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: desc.uuid.uuidString,
                ]
            ],
        ]
        try verificar(
            AudioHardwareCreateAggregateDevice(config as CFDictionary, &agregadoID),
            "crear dispositivo agregado"
        )

        // S3: usar la frecuencia real del dispositivo agregado (con Bluetooth puede ser 16 kHz).
        var real: Float64 = 0
        tam = UInt32(MemoryLayout<Float64>.size)
        dir.mSelector = kAudioDevicePropertyNominalSampleRate
        if AudioObjectGetPropertyData(agregadoID, &dir, 0, nil, &tam, &real) == noErr,
            real > 0, real != asbd.mSampleRate
        {
            asbd.mSampleRate = real
        }
        guard let formato = AVAudioFormat(streamDescription: &asbd) else {
            throw NSError(
                domain: "NotchyAudio",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Formato de tap del sistema inválido."]
            )
        }
        lock.withLock {
            _formatoTexto = "\(Int(formato.sampleRate)) Hz, \(formato.channelCount) ch"
        }

        let contador = self.contador
        let alRecibir = self.alRecibir
        try verificar(
            AudioDeviceCreateIOProcIDWithBlock(&procID, agregadoID, cola) { _, entrada, tiempoEntrada, _, _ in
                guard
                    let buffer = AVAudioPCMBuffer(
                        pcmFormat: formato,
                        bufferListNoCopy: entrada,
                        deallocator: nil
                    )
                else { return }
                let t = tiempoEntrada.pointee
                let hostMs = ContadorDeFuenteAudio.hostTimeAMilisegundos(t.mHostTime)
                contador.registrar(muestra: t.mSampleTime, frames: Int(buffer.frameLength), hostMs: hostMs)
                let muestrasMono = ExtraerMuestrasMono.extraer(de: buffer)
                guard !muestrasMono.isEmpty else { return }
                let bloque = BloqueDeAudioPCM(
                    fuente: .sistema,
                    muestras: muestrasMono,
                    frecuencia: formato.sampleRate,
                    canales: 1,
                    frames: muestrasMono.count,
                    muestraInicial: t.mSampleTime,
                    marcaHostMs: hostMs
                )
                alRecibir(bloque)
            },
            "crear IOProc del sistema"
        )
        try verificar(AudioDeviceStart(agregadoID, procID), "iniciar captura del sistema")
    }

    func detener() {
        if let procID {
            AudioDeviceStop(agregadoID, procID)
            AudioDeviceDestroyIOProcID(agregadoID, procID)
        }
        procID = nil
        if agregadoID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(agregadoID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        agregadoID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func uidSalidaPorDefecto() throws -> String {
        var dispositivo = AudioObjectID(kAudioObjectUnknown)
        var tam = UInt32(MemoryLayout<AudioObjectID>.size)
        var dir = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try verificar(
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &dir,
                0,
                nil,
                &tam,
                &dispositivo
            ),
            "obtener salida de audio por defecto"
        )
        var uid: Unmanaged<CFString>?
        tam = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        dir.mSelector = kAudioDevicePropertyDeviceUID
        try verificar(
            AudioObjectGetPropertyData(dispositivo, &dir, 0, nil, &tam, &uid),
            "obtener UID de salida"
        )
        guard let cf = uid?.takeRetainedValue() else {
            throw NSError(domain: "NotchyAudio", code: 4)
        }
        return cf as String
    }

    private func verificar(_ estado: OSStatus, _ accion: String) throws {
        guard estado == noErr else {
            throw NSError(
                domain: "NotchyCoreAudio",
                code: Int(estado),
                userInfo: [NSLocalizedDescriptionKey: "Error al \(accion) (\(estado))."]
            )
        }
    }
}

enum ExtraerMuestrasMono {
    nonisolated static func extraer(de buffer: AVAudioPCMBuffer) -> [Float] {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }
        let canales = Int(buffer.format.channelCount)
        if let canalesFloat = buffer.floatChannelData {
            if buffer.format.isInterleaved {
                let ptr = canalesFloat[0]
                var salida = [Float](repeating: 0, count: frames)
                for i in 0..<frames {
                    var suma: Float = 0
                    for c in 0..<canales {
                        suma += ptr[i * canales + c]
                    }
                    salida[i] = suma / Float(canales)
                }
                return salida
            } else {
                var salida = [Float](repeating: 0, count: frames)
                for c in 0..<canales {
                    let ptr = canalesFloat[c]
                    for i in 0..<frames {
                        salida[i] += ptr[i]
                    }
                }
                if canales > 1 {
                    let inv = 1.0 / Float(canales)
                    for i in 0..<frames {
                        salida[i] *= inv
                    }
                }
                return salida
            }
        }
        // Si llega en otro formato, convertir a Float32 mono.
        guard
            let destino = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: buffer.format.sampleRate,
                channels: 1,
                interleaved: false
            ),
            let conversor = AVAudioConverter(from: buffer.format, to: destino),
            let convertido = AVAudioPCMBuffer(pcmFormat: destino, frameCapacity: buffer.frameLength)
        else { return [] }
        var entregado = false
        var err: NSError?
        _ = conversor.convert(to: convertido, error: &err) { _, estado in
            if entregado {
                estado.pointee = .noDataNow
                return nil
            }
            entregado = true
            estado.pointee = .haveData
            return buffer
        }
        guard convertido.frameLength > 0, let ptr = convertido.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: ptr, count: Int(convertido.frameLength)))
    }

    nonisolated static func reconstruirBuffer(de bloque: BloqueDeAudioPCM) -> AVAudioPCMBuffer? {
        guard !bloque.muestras.isEmpty,
            let formato = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: bloque.frecuencia,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: formato,
                frameCapacity: AVAudioFrameCount(bloque.muestras.count)
            ),
            let canal = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(bloque.muestras.count)
        bloque.muestras.withUnsafeBufferPointer { origen in
            guard let base = origen.baseAddress else { return }
            canal.update(from: base, count: bloque.muestras.count)
        }
        return buffer
    }
}
