import Foundation
import IOKit.pwr_mgt

/// Lo que las apps le piden a macOS sobre la energía.
public enum AsercionesDeEnergia {
    /// `true` si alguna app pide que la pantalla no se apague por inactividad. Es lo que hacen los
    /// reproductores mientras corre un video (Safari, QuickTime, IINA…), así que sirve para seguir
    /// contando tiempo de uso aunque no se toque el teclado ni el ratón.
    public static func pantallaRetenidaPorUnaApp() -> Bool {
        var estado: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&estado) == kIOReturnSuccess,
            let diccionario = estado?.takeRetainedValue() as? [String: Any]
        else { return false }
        let cuenta = diccionario[kIOPMAssertPreventUserIdleDisplaySleep as String] as? Int ?? 0
        return cuenta > 0
    }
}
