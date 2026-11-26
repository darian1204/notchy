import Foundation
import NotchyCore
import NotchyStorage
import OSLog

/// Al terminar una reunión (o a pedido desde el historial), resume la transcripción con el modelo local,
/// guarda la nota estructurada en la base de datos y la manda al inbox de Obsidian si el ajuste está activo.
@MainActor
public final class ResumidorDeReuniones {
    /// Menos texto que esto no vale la pena resumir en automático (una reunión de prueba o vacía).
    static let minimoDeCaracteres = 200

    private let bus: BusDeEventos
    private let modelo: any PuertoDeResumenDeTexto
    private let ajustes: Ajustes
    private let repositorio: RepositorioDeGrabadoraYReuniones?
    private let segmentosDe: @MainActor (String) -> [SegmentoDeTranscripcion]
    private let nombresDeHablantesDe: @MainActor (String) -> [String: String]
    private let escribirEnInbox: @MainActor (String) async -> Bool
    private let alGuardarNota: (@MainActor (NotaDeReunion) -> Void)?
    private let log = Registro.de(.grabadora)
    private var tarea: Task<Void, Never>?

    public init(
        bus: BusDeEventos,
        modelo: any PuertoDeResumenDeTexto,
        ajustes: Ajustes,
        repositorio: RepositorioDeGrabadoraYReuniones? = nil,
        segmentosDe: @escaping @MainActor (String) -> [SegmentoDeTranscripcion],
        nombresDeHablantesDe: (@MainActor (String) -> [String: String])? = nil,
        escribirEnInbox: @escaping @MainActor (String) async -> Bool,
        alGuardarNota: (@MainActor (NotaDeReunion) -> Void)? = nil
    ) {
        self.bus = bus
        self.modelo = modelo
        self.ajustes = ajustes
        self.repositorio = repositorio
        self.segmentosDe = segmentosDe
        self.nombresDeHablantesDe =
            nombresDeHablantesDe
            ?? { [repositorio] id in
                (try? repositorio?.listarNombresDeHablantes(reunionID: id)) ?? [:]
            }
        self.escribirEnInbox = escribirEnInbox
        self.alGuardarNota = alGuardarNota
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

    /// Resume la reunión, guarda siempre la nota en la base y devuelve el texto resumido (o la nota de inbox si el ajuste está activo).
    @discardableResult
    func procesar(_ reunion: ReunionGrabada) async -> String? {
        let nombres = nombresDeHablantesDe(reunion.id)
        let texto = ModeloDeGrabadora.textoDeTranscripcion(
            segmentosDe(reunion.id),
            nombresHablantes: nombres
        )
        guard texto.count >= Self.minimoDeCaracteres else { return nil }
        guard await modelo.disponible() else {
            log.info("Apple Intelligence no está disponible; no se resume la reunión.")
            return nil
        }
        do {
            let resumen = try await RedaccionDeResumen.resumirPorPartes(texto, con: modelo)
            guard !resumen.isEmpty else { return nil }
            let notaReunion = NotaDeReunion(
                reunionID: reunion.id,
                markdown: resumen,
                generadaEn: .now,
                editadaEn: nil
            )
            try? repositorio?.guardarNotaDeReunion(notaReunion)
            alGuardarNota?(notaReunion)

            guard ajustes.resumirReunionesEnInbox else { return resumen }
            let fin = reunion.fin ?? .now
            let minutos = Int((fin.timeIntervalSince(reunion.inicio) / 60).rounded())
            let nota = RedaccionDeResumen.notaDeInbox(
                titulo: reunion.titulo,
                inicio: reunion.inicio,
                duracionMinutos: minutos,
                resumen: resumen
            )
            return await escribirEnInbox(nota) ? nota : resumen
        } catch {
            log.error("No se pudo resumir la reunión: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
