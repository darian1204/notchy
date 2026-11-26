import Foundation
import NotchyCore
import NotchyFeatures
import Testing

/// Reloj y contador de inactividad que la prueba mueve a mano.
@MainActor
private final class Mundo {
    var ahora: Date
    var sinUsar: TimeInterval = 0
    init(_ ahora: Date) { self.ahora = ahora }
}

@MainActor
struct ScreenTimeTests {
    private func modelo(_ mundo: Mundo, _ defaults: UserDefaults) -> ModeloDeScreenTime {
        ModeloDeScreenTime(defaults: defaults, ahora: { mundo.ahora }, segundosSinUsar: { mundo.sinUsar })
    }

    private func defaultsDePrueba() -> (UserDefaults, String) {
        let nombre = "notchy.screentime.test.\(UUID().uuidString)"
        return (UserDefaults(suiteName: nombre)!, nombre)
    }

    private func fecha(_ dia: Int, _ hora: Int, _ minuto: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: dia, hour: hora, minute: minuto))!
    }

    @Test func noInventaDatosAlEmpezarElDia() {
        let (defaults, nombre) = defaultsDePrueba()
        defer { defaults.removePersistentDomain(forName: nombre) }
        let modelo = modelo(Mundo(fecha(26, 9)), defaults)
        #expect(modelo.usosPorApp.isEmpty)
    }

    @Test func alCambiarDeDiaEmpiezaDeCero() {
        let (defaults, nombre) = defaultsDePrueba()
        defer { defaults.removePersistentDomain(forName: nombre) }
        let mundo = Mundo(fecha(25, 23, 50))
        let modelo = modelo(mundo, defaults)
        modelo.registrarTiempoManual(bundleID: "com.apple.Safari", nombre: "Safari", segundos: 3600)
        mundo.ahora = fecha(26, 0, 5)
        modelo.tic()
        #expect(modelo.usosPorApp.isEmpty)
    }

    @Test func soloCuentaConLaMacEnUsoYSinDormir() {
        let (defaults, nombre) = defaultsDePrueba()
        defer { defaults.removePersistentDomain(forName: nombre) }
        let mundo = Mundo(fecha(26, 10))
        let modelo = modelo(mundo, defaults)
        modelo.tic()
        mundo.ahora += 10
        modelo.tic()
        let contado = modelo.usosPorApp.reduce(0) { $0 + $1.segundos }
        #expect(contado == 10)

        mundo.sinUsar = 600
        mundo.ahora += 10
        modelo.tic()
        #expect(modelo.usosPorApp.reduce(0) { $0 + $1.segundos } == contado)

        mundo.sinUsar = 0
        mundo.ahora += 3600
        modelo.tic()
        #expect(modelo.usosPorApp.reduce(0) { $0 + $1.segundos } == contado)
    }

    @Test func descartaRegistrosImposiblesDeHoy() throws {
        let (defaults, nombre) = defaultsDePrueba()
        defer { defaults.removePersistentDomain(forName: nombre) }
        let mundo = Mundo(fecha(26, 16))
        let primero = modelo(mundo, defaults)
        primero.registrarTiempoManual(bundleID: "com.apple.Safari", nombre: "Safari", segundos: 59 * 3600)
        let segundo = modelo(mundo, defaults)
        #expect(segundo.usosPorApp.isEmpty)
    }

    @Test func laPantallaDeBloqueoNoEsUnaApp() {
        let (defaults, nombre) = defaultsDePrueba()
        defer { defaults.removePersistentDomain(forName: nombre) }
        let mundo = Mundo(fecha(26, 16))
        let primero = modelo(mundo, defaults)
        primero.registrarTiempoManual(bundleID: "com.apple.loginwindow", nombre: "loginwindow", segundos: 600)
        primero.registrarTiempoManual(bundleID: "com.apple.Safari", nombre: "Safari", segundos: 600)
        let segundo = modelo(mundo, defaults)
        #expect(segundo.usosPorApp.map(\.bundleId) == ["com.apple.Safari"])
    }
}
