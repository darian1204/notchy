import Testing

@testable import IslaCore

@Suite struct IslaInfoTests {
    @Test func laDepuracionUsaSuPropiaCarpeta() {
        #expect(IslaInfo.carpetaDeDatos(.depuracion) == "Isla-Dev")
        #expect(IslaInfo.carpetaDeDatos(.publicacion) == "Isla")
    }

    @Test func elIdentificadorEsElDeLaApp() {
        #expect(IslaInfo.identificador == "dev.darian.isla")
    }
}
