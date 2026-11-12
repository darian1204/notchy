import AppKit
import Foundation
import NotchyCore
import NotchyDesign
import Observation
import SwiftUI

/// Modelo observable del módulo de Traducción (Translate) con soporte instantáneo y LLM vía OpenCode.
@MainActor
@Observable
public final class ModeloDeTraductor {
    public var idiomaOrigen: IdiomaDeTraduccion = .ingles
    public var idiomaDestino: IdiomaDeTraduccion = .espanol
    public var textoOrigen: String = "I find it quite useful!"
    public private(set) var textoTraducido: String = "¡Lo encuentro bastante útil!"
    public private(set) var traduciendo = false
    public var usarOpenCodeLLM = false
    public private(set) var copiadoReciente = false

    @ObservationIgnored private let agente: (any PuertoAgenteOpenCode)?
    @ObservationIgnored private var tareaTraduccion: Task<Void, Never>?

    public init(agente: (any PuertoAgenteOpenCode)? = nil) {
        self.agente = agente
    }

    public func traducir() {
        let limpio = textoOrigen.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else {
            textoTraducido = ""
            return
        }
        tareaTraduccion?.cancel()
        traduciendo = true
        let origen = idiomaOrigen
        let destino = idiomaDestino
        let usarLLM = usarOpenCodeLLM

        tareaTraduccion = Task { [weak self] in
            guard let self else { return }
            if usarLLM, let agente = self.agente, agente.estaDisponible() {
                let prompt =
                    "Translate the following text from \(origen.nombreCompleto) to \(destino.nombreCompleto). Reply ONLY with the translated text, without quotes or explanations:\n\n\(limpio)"
                if let res = try? await agente.enviarMensaje(
                    prompt: prompt,
                    modelo: "openai/gpt-5.4-fast",
                    sesionID: nil,
                    directorio: nil,
                    alRecibirFragmento: { parcial, _ in
                        self.textoTraducido = parcial
                    }
                ) {
                    self.textoTraducido = res.textoFinal
                    self.traduciendo = false
                    return
                }
            }

            if let instantanea = await Self.traducirInstantaneo(
                texto: limpio,
                origen: origen.rawValue,
                destino: destino.rawValue
            ) {
                self.textoTraducido = instantanea
            }
            self.traduciendo = false
        }
    }

    public func intercambiarIdiomas() {
        let tempIdioma = idiomaOrigen
        idiomaOrigen = idiomaDestino
        idiomaDestino = tempIdioma

        if !textoTraducido.isEmpty {
            let tempTexto = textoOrigen
            textoOrigen = textoTraducido
            textoTraducido = tempTexto
        }
        traducir()
    }

    public func limpiar() {
        textoOrigen = ""
        textoTraducido = ""
    }

    public func pegarDesdePortapapeles() {
        if let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
            textoOrigen = str
            traducir()
        }
    }

    public func copiarTraduccion() {
        guard !textoTraducido.isEmpty else { return }
        let pasta = NSPasteboard.general
        pasta.clearContents()
        pasta.setString(textoTraducido, forType: .string)
        copiadoReciente = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.copiadoReciente = false
        }
    }

    public static func traducirInstantaneo(
        texto: String,
        origen: String,
        destino: String
    ) async -> String? {
        guard let q = texto.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(
                string:
                    "https://translate.googleapis.com/translate_a/single?client=gtx&sl=\(origen)&tl=\(destino)&dt=t&q=\(q)"
            )
        else { return nil }
        do {
            let (datos, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: datos) as? [Any],
                let bloques = json.first as? [[Any]]
            else { return nil }
            let partes = bloques.compactMap { $0.first as? String }
            let unido = partes.joined()
            return unido.isEmpty ? nil : unido
        } catch {
            return nil
        }
    }
}

/// Módulo de Traducción en el notch (`character.bubble.fill`).
@MainActor
public final class ModuloDeTraductor: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "traductor",
        nombre: "Translate",
        icono: "character.bubble.fill",
        color: Paleta.hexTraductor,
        lado: .derecha
    )
    public let tamanoExpandido = Medidas.traductor
    public let modelo: ModeloDeTraductor

    public init(modelo: ModeloDeTraductor) {
        self.modelo = modelo
    }

    public var salud: SaludDeModulo { .listo }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeTraductor(modelo: modelo))
    }

    public func arrancar() {}
    public func detener() {}
}

struct VistaDeTraductor: View {
    @Bindable var modelo: ModeloDeTraductor
    @FocusState private var enfocado: Bool

    var body: some View {
        VStack(spacing: 8) {
            barraSuperior
            HStack(spacing: 10) {
                panelOrigen
                columnaBotonesCentro
                panelDestino
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 4)
    }

    private var barraSuperior: some View {
        HStack(spacing: 8) {
            selectorIdioma(seleccion: $modelo.idiomaOrigen)
                .onChange(of: modelo.idiomaOrigen) { _, _ in
                    modelo.traducir()
                }

            Button {
                modelo.limpiar()
                enfocado = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .frame(width: 20, height: 20)
                    .background(Paleta.superficie, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Limpiar texto")

            Spacer(minLength: 0)

            Button {
                modelo.copiarTraduccion()
            } label: {
                Image(systemName: modelo.copiadoReciente ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(modelo.copiadoReciente ? Color(hex: 0x30D158) : Paleta.textoDeApoyo)
                    .frame(width: 22, height: 22)
                    .background(Paleta.superficie, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Copiar traducción")

            selectorIdioma(seleccion: $modelo.idiomaDestino)
                .onChange(of: modelo.idiomaDestino) { _, _ in
                    modelo.traducir()
                }

            Button {
                modelo.usarOpenCodeLLM.toggle()
                modelo.traducir()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: modelo.usarOpenCodeLLM ? "sparkles" : "bolt.fill")
                        .font(.system(size: 8.5, weight: .bold))
                    Text(modelo.usarOpenCodeLLM ? "LLM" : "Fast")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(modelo.usarOpenCodeLLM ? Paleta.agente : Paleta.traductor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Paleta.superficie, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Alternar entre traducción instantánea y LLM con OpenCode")
        }
    }

    private func selectorIdioma(seleccion: Binding<IdiomaDeTraduccion>) -> some View {
        Menu {
            ForEach(IdiomaDeTraduccion.allCases) { idioma in
                Button(idioma.nombreCompleto) {
                    seleccion.wrappedValue = idioma
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(seleccion.wrappedValue.etiqueta)
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.5)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Paleta.texto)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Paleta.superficieAlta, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var panelOrigen: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Escribe o pega texto…", text: $modelo.textoOrigen, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Paleta.texto)
                .lineLimit(1...5)
                .focused($enfocado)
                .onSubmit {
                    modelo.traducir()
                }

            Spacer(minLength: 0)

            HStack {
                Button {
                    modelo.pegarDesdePortapapeles()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("Pegar")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundStyle(Paleta.textoDeApoyo)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Paleta.borde.opacity(0.7), lineWidth: 1)
        )
    }

    private var columnaBotonesCentro: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Button {
                modelo.traducir()
            } label: {
                Image(systemName: modelo.traduciendo ? "ellipsis" : "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 30, height: 30)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Traducir ahora")

            Button {
                modelo.intercambiarIdiomas()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .frame(width: 26, height: 26)
                    .background(Paleta.superficieAlta, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Intercambiar idiomas")
            Spacer(minLength: 0)
        }
    }

    private var panelDestino: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(modelo.textoTraducido.isEmpty ? "Traducción…" : modelo.textoTraducido)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(modelo.textoTraducido.isEmpty ? Paleta.textoDeApoyo : Paleta.texto)
                .textSelection(.enabled)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Paleta.borde.opacity(0.7), lineWidth: 1)
        )
        .onTapGesture {
            modelo.copiarTraduccion()
        }
    }
}
