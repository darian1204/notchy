import AppKit
import Foundation
import NotchyCore
import NotchyDesign
import Observation
import SwiftUI

/// Modelo observable del módulo Selector de Color (Colour Picker + contraste WCAG).
@MainActor
@Observable
public final class ModeloDeColorPicker {
    public private(set) var colorPrimario: ColorMuestreado
    public private(set) var colorFondo: ColorMuestreado
    public var formatoSeleccionado: FormatoDeColor = .hex
    public private(set) var historial: [ColorMuestreado]
    public private(set) var copiadoReciente = false

    @ObservationIgnored private let muestreador: any PuertoMuestreadorDeColor
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let claveHistorial = "notchy.colorPicker.historial"

    public static let muestrasIniciales: [ColorMuestreado] = [
        ColorMuestreado(rojo: 1.00, verde: 0.27, azul: 0.23),
        ColorMuestreado(rojo: 1.00, verde: 0.62, azul: 0.04),
        ColorMuestreado(rojo: 1.00, verde: 0.84, azul: 0.04),
        ColorMuestreado(rojo: 0.19, verde: 0.82, azul: 0.35),
        ColorMuestreado(rojo: 0.39, verde: 0.82, azul: 1.00),
        ColorMuestreado(rojo: 0.04, verde: 0.52, azul: 1.00),
        ColorMuestreado(rojo: 0.75, verde: 0.35, azul: 0.95),
        ColorMuestreado(rojo: 1.00, verde: 1.00, azul: 1.00),
        ColorMuestreado(rojo: 0.08, verde: 0.08, azul: 0.09),
    ]

    public init(
        muestreador: any PuertoMuestreadorDeColor,
        defaults: UserDefaults = .standard
    ) {
        self.muestreador = muestreador
        self.defaults = defaults
        let guardados: [ColorMuestreado]
        if let datos = defaults.data(forKey: Self.claveHistorial),
            let decodificados = try? JSONDecoder().decode([ColorMuestreado].self, from: datos),
            !decodificados.isEmpty
        {
            guardados = decodificados
        } else {
            guardados = Self.muestrasIniciales
        }
        self.historial = guardados
        self.colorPrimario = guardados.first ?? Self.muestrasIniciales[0]
        self.colorFondo = ColorMuestreado(rojo: 0.08, verde: 0.08, azul: 0.09)
    }

    public var razonDeContraste: Double {
        colorPrimario.contrasteWCAG(contra: colorFondo)
    }

    public var textoContraste: String {
        String(format: "%.1f:1", razonDeContraste)
    }

    public var cumpleAA: Bool {
        razonDeContraste >= 4.5
    }

    public var cumpleAAA: Bool {
        razonDeContraste >= 7.0
    }

    public var cumpleLarge: Bool {
        razonDeContraste >= 3.0
    }

    public var valorFormateadoActual: String {
        colorPrimario.texto(en: formatoSeleccionado)
    }

    public func muestrearColorPrimario() async {
        guard let nuevo = await muestreador.muestrearColorEnPantalla() else { return }
        registrarColorPrimario(nuevo)
        copiarValorActual()
    }

    public func muestrearColorFondo() async {
        guard let nuevo = await muestreador.muestrearColorEnPantalla() else { return }
        colorFondo = nuevo
    }

    public func registrarColorPrimario(_ nuevo: ColorMuestreado) {
        colorPrimario = nuevo
        historial.removeAll { $0.hex == nuevo.hex }
        historial.insert(nuevo, at: 0)
        if historial.count > 12 {
            historial = Array(historial.prefix(12))
        }
        guardarHistorial()
    }

    public func intercambiarColores() {
        let temporal = colorPrimario
        colorPrimario = colorFondo
        colorFondo = temporal
    }

    public func seleccionarDeHistorial(_ muestra: ColorMuestreado, comoFondo: Bool = false) {
        if comoFondo {
            colorFondo = muestra
        } else {
            colorPrimario = muestra
        }
    }

    public func limpiarHistorial() {
        historial = [colorPrimario]
        guardarHistorial()
    }

    public func copiarValorActual() {
        let pasta = NSPasteboard.general
        pasta.clearContents()
        pasta.setString(valorFormateadoActual, forType: .string)
        copiadoReciente = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.copiadoReciente = false
        }
    }

    private func guardarHistorial() {
        if let datos = try? JSONEncoder().encode(historial) {
            defaults.set(datos, forKey: Self.claveHistorial)
        }
    }
}

/// Módulo de Selector de Color con cuentagotas de pantalla, formatos HEX/RGB/HSL/Swift y contraste WCAG.
@MainActor
public final class ModuloDeColorPicker: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "colorpicker",
        nombre: "Color",
        icono: "eyedropper",
        color: Paleta.hexColorPicker,
        lado: .derecha
    )
    public let tamanoExpandido = Medidas.colorPicker
    public let modelo: ModeloDeColorPicker

    public init(modelo: ModeloDeColorPicker) {
        self.modelo = modelo
    }

    public var salud: SaludDeModulo { .listo }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeColorPicker(modelo: modelo))
    }

    public func arrancar() {}
    public func detener() {}
}

struct VistaDeColorPicker: View {
    @Bindable var modelo: ModeloDeColorPicker

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            filaSuperior
            filaFormatos
            barraValorCopiable
            filaHistorial
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var filaSuperior: some View {
        HStack(spacing: 8) {
            // Muestra primaria + HEX
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colorSwiftUI(modelo.colorPrimario))
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    )

                Text(modelo.colorPrimario.hex)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Paleta.texto)
            }

            // Intercambiar primario / fondo
            Button {
                modelo.intercambiarColores()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .frame(width: 24, height: 24)
                    .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Intercambiar color primario y fondo")
            .accessibilityLabel("Intercambiar color primario y fondo")

            // Muestra de color de fondo (clic para muestrear fondo)
            Button {
                Task { await modelo.muestrearColorFondo() }
            } label: {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(colorSwiftUI(modelo.colorFondo))
                    .frame(width: 24, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Fondo para contraste WCAG (\(modelo.colorFondo.hex)). Clic para muestrear otro fondo")

            // Botón Pick con cuentagotas
            Button {
                Task { await modelo.muestrearColorPrimario() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Pick")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Paleta.texto)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Paleta.superficieAlta, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Paleta.borde, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Muestrear cualquier píxel de la pantalla")

            Spacer(minLength: 4)

            // Ratio WCAG y etiquetas AA / AAA / Large
            HStack(spacing: 5) {
                Text(modelo.textoContraste)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Paleta.texto)
                    .padding(.trailing, 2)

                insigniaWCAG("AA", cumple: modelo.cumpleAA)
                insigniaWCAG("AAA", cumple: modelo.cumpleAAA)
                insigniaWCAG("Large", cumple: modelo.cumpleLarge)
            }
        }
    }

    private func insigniaWCAG(_ titulo: String, cumple: Bool) -> some View {
        Text(titulo)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(cumple ? Color(hex: 0x30D158) : Paleta.textoDeApoyo.opacity(0.45))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                (cumple ? Color(hex: 0x30D158).opacity(0.16) : Paleta.superficie),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        cumple ? Color(hex: 0x30D158).opacity(0.42) : Paleta.borde,
                        lineWidth: 1
                    )
            )
    }

    private var filaFormatos: some View {
        HStack(spacing: 6) {
            ForEach(FormatoDeColor.allCases, id: \.self) { formato in
                let activo = modelo.formatoSeleccionado == formato
                Button {
                    modelo.formatoSeleccionado = formato
                } label: {
                    Text(formato.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(activo ? Paleta.texto : Paleta.textoDeApoyo)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            activo ? Paleta.superficieAlta : Paleta.superficie.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(activo ? Paleta.borde : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var barraValorCopiable: some View {
        Button {
            modelo.copiarValorActual()
        } label: {
            HStack(spacing: 8) {
                Text(modelo.valorFormateadoActual)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Paleta.texto)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: modelo.copiadoReciente ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                    Text(modelo.copiadoReciente ? "Copiado" : "Copiar")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(modelo.copiadoReciente ? Color(hex: 0x30D158) : Paleta.textoDeApoyo)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Paleta.borde, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Clic para copiar el código de color al portapapeles")
    }

    private var filaHistorial: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(modelo.historial) { muestra in
                        let seleccionado = muestra.hex == modelo.colorPrimario.hex
                        Button {
                            let usarComoFondo = NSEvent.modifierFlags.contains(.option)
                            modelo.seleccionarDeHistorial(muestra, comoFondo: usarComoFondo)
                        } label: {
                            Circle()
                                .fill(colorSwiftUI(muestra))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            seleccionado ? Color.white : Color.white.opacity(0.22),
                                            lineWidth: seleccionado ? 2 : 1
                                        )
                                )
                                .scaleEffect(seleccionado ? 1.08 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .help("\(muestra.hex) · Clic para elegir (Option+Clic para usar como fondo)")
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)

            Button {
                modelo.limpiarHistorial()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .frame(width: 24, height: 24)
                    .background(Paleta.superficie, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Limpiar historial de colores")
            .accessibilityLabel("Limpiar historial de colores")
        }
    }

    private func colorSwiftUI(_ color: ColorMuestreado) -> Color {
        Color(.sRGB, red: color.rojo, green: color.verde, blue: color.azul, opacity: 1.0)
    }
}
