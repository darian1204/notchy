import Testing

@testable import NotchyCore

@Suite struct NotchyInfoTests {
    @Test func laDepuracionUsaSuPropiaCarpeta() {
        #expect(NotchyInfo.carpetaDeDatos(.depuracion) == "Notchy-Dev")
        #expect(NotchyInfo.carpetaDeDatos(.publicacion) == "Notchy")
    }

    @Test func elIdentificadorEsElDeLaApp() {
        #expect(NotchyInfo.identificador == "dev.darian.notchy")
    }
}
