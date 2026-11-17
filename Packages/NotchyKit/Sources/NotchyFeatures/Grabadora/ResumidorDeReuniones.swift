import Foundation
import NotchyCore
import OSLog

/// Al terminar una reunión, resume la transcripción con el modelo local y la deja en el inbox de Obsidian.
@MainActor
public final class ResumidorDeReuniones {
    /// Menos texto que esto no vale la pena resumir (una reunión de prueba o vacía).
    static let minimoDeCaracteres = 200

    private let bus: BusDeEventos
    private let modelo: any PuertoDeResumenDeTexto
    private let ajustes: Ajustes
    private let segmentosDe: @MainActor (String) -> [SegmentoDeTranscripcion]
    private let escribirEnInbox: @MainActor (String) -> Bool
    private let log = Registro.de(.grabadora)
    private var tarea: Task<Void, Never>?

    public init(
        bus: BusDeEventos,
        modelo: any PuertoDeResumenDeTexto,
        ajustes: Ajustes,
        segmentosDe: @escaping @MainActor (String) -> [SegmentoDeTranscripcion],
        escribirEnInbox: @escaping @MainActor (String) -> Bool
    ) {
        self.bus = bus
        self.modelo = modelo
        self.ajustes = ajustes
        self.segmentosDe = segmentosDe
        self.escribirEnInbox = escribirEnInbox
    }

    public func arrancar() {
        guard tarea == nil else { return }
        let bus = self.bus
        tarea = Task { [weak self] in
            let flujo = await bus.suscribir(a: ReunionTerminada.self)
            for await evento in flujo {
                await self?.procesar(evento.reunion)
            }
        }
    }

    public func detener() {
        tarea?.cancel()
        tarea = nil
    }

    /// Devuelve la nota escrita, o `nil` si no se resumió.
    @discardableResult
    func procesar(_ reunion: ReunionGrabada) async -> String? {
        guard ajustes.resumirReunionesEnInbox else { return nil }
        let texto = ModeloDeGrabadora.textoDeTranscripcion(segmentosDe(reunion.id))
        guard texto.count >= Self.minimoDeCaracteres else { return nil }
        guard await modelo.disponible() else {
            log.info("Apple Intelligence no está disponible; no se resume la reunión.")
            return nil
        }
        do {
            let resumen = try await RedaccionDeResumen.resumirPorPartes(texto, con: modelo)
            guard !resumen.isEmpty else { return nil }
            let fin = reunion.fin ?? .now
            let minutos = Int((fin.timeIntervalSince(reunion.inicio) / 60).rounded())
            let nota = RedaccionDeResumen.notaDeInbox(
                titulo: reunion.titulo,
                inicio: reunion.inicio,
                duracionMinutos: minutos,
                resumen: resumen
            )
            return escribirEnInbox(nota) ? nota : nil
        } catch {
            log.error("No se pudo resumir la reunión: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
