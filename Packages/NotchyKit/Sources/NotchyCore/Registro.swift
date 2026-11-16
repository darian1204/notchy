import OSLog

/// Registro unificado del sistema, una categoría por módulo.
/// Regla: los logs dicen qué pasó, nunca el texto copiado, transcrito o dictado.
public enum Registro {
    public enum Categoria: String, Sendable, CaseIterable {
        case arranque, isla, ajustes, datos, modulos, permisos, agenda, musica, espejo, airdrop, colorpicker,
            screentime, hud, clima, notificaciones, agente, traductor, windowsnap, monitor, grabadora, reuniones
    }

    public static func de(_ categoria: Categoria) -> Logger {
        Logger(subsystem: NotchyInfo.identificador, category: categoria.rawValue)
    }
}
