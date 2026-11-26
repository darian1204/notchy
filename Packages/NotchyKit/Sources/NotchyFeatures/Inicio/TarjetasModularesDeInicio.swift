import NotchyCore
import NotchyDesign
import SwiftUI

/// Encabezado de una tarjeta del Inicio: ícono de color, nombre y flecha que abre el módulo.
private struct EncabezadoDeTarjeta: View {
    let titulo: String
    let icono: String
    let color: Color
    let accion: (@MainActor () -> Void)?

    var body: some View {
        Button {
            accion?()
        } label: {
            HStack(spacing: 6) {
                Label(titulo, systemImage: icono)
                    .labelStyle(IconoDeColor(color: color))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Paleta.textoDeApoyo)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Paleta.texto)
            .contentShape(Rectangle())
        }
        .buttonStyle(.presion)
    }
}

/// Los eventos que quedan hoy.
struct TarjetaAgendaInicio: View {
    let fuentes: FuentesDeInicioTarjetas

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EncabezadoDeTarjeta(titulo: "Hoy", icono: "calendar", color: Paleta.agenda) {
                fuentes.alAbrirModulo?("agenda")
            }
            if proximos.isEmpty {
                Spacer(minLength: 0)
                Text("Sin eventos el resto del día").textoDeApoyo()
                Spacer(minLength: 0)
            } else {
                ForEach(proximos) { evento in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(
                            evento.todoElDia ? "Todo el día" : evento.inicio.formatted(date: .omitted, time: .shortened)
                        )
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Paleta.agenda)
                        .lineLimit(1)
                        Text(evento.titulo)
                            .font(.system(size: 11))
                            .foregroundStyle(Paleta.texto)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var proximos: [EventoDeCalendario] {
        let ahora = Date.now
        return Array(
            (fuentes.agenda?.eventosDeHoy ?? [])
                .filter { $0.todoElDia || $0.fin > ahora }
                .sorted { $0.inicio < $1.inicio }
                .prefix(4))
    }
}

/// Lo último copiado. Un clic lo vuelve a copiar.
struct TarjetaPortapapelesInicio: View {
    let fuentes: FuentesDeInicioTarjetas

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            EncabezadoDeTarjeta(titulo: "Copiado", icono: "doc.on.clipboard", color: Paleta.portapapeles) {
                fuentes.alAbrirModulo?("portapapeles")
            }
            if recientes.isEmpty {
                Spacer(minLength: 0)
                Text("Nada copiado todavía").textoDeApoyo()
                Spacer(minLength: 0)
            } else {
                ForEach(recientes) { elemento in
                    Button {
                        fuentes.portapapeles?.copiarAlSistema(elemento)
                    } label: {
                        Text(elemento.texto.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 11))
                            .foregroundStyle(Paleta.texto)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.presion)
                    .help("Copiar otra vez")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var recientes: [ElementoDePortapapeles] {
        Array(
            (fuentes.portapapeles?.elementos ?? [])
                .filter { $0.tipo == .texto || $0.tipo == .enlace }
                .prefix(3))
    }
}

/// CPU, memoria, disco y batería.
struct TarjetaMonitorInicio: View {
    let fuentes: FuentesDeInicioTarjetas

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EncabezadoDeTarjeta(
                titulo: "Monitor", icono: "gauge.with.dots.needle.33percent", color: Paleta.monitorSistema
            ) {
                fuentes.alAbrirModulo?("monitor")
            }
            if let metricas = fuentes.monitor?.metricas {
                fila("CPU", metricas.usoCPUPorcentaje / 100, "\(Int(metricas.usoCPUPorcentaje.rounded()))%")
                fila(
                    "Memoria",
                    metricas.memoriaTotalGB > 0 ? metricas.memoriaUsadaGB / metricas.memoriaTotalGB : 0,
                    String(format: "%.1f GB", metricas.memoriaUsadaGB)
                )
                fila(
                    "Disco",
                    metricas.almacenamientoUsadoPorcentaje / 100,
                    String(format: "%.0f GB libres", metricas.discoLibreGB)
                )
                fila(
                    "Batería",
                    Double(metricas.bateriaPorcentaje) / 100,
                    "\(metricas.bateriaPorcentaje)%\(metricas.bateriaCargando ? " ⚡︎" : "")"
                )
            } else {
                Spacer(minLength: 0)
                Text("Monitor apagado").textoDeApoyo()
            }
            Spacer(minLength: 0)
        }
    }

    private func fila(_ nombre: String, _ fraccion: Double, _ valor: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(nombre).font(.system(size: 10)).foregroundStyle(Paleta.textoDeApoyo)
                Spacer(minLength: 4)
                Text(valor)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Paleta.texto)
                    .lineLimit(1)
            }
            GeometryReader { geometria in
                Capsule().fill(Paleta.superficieAlta)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Paleta.monitorSistema)
                            .frame(width: geometria.size.width * min(max(fraccion, 0), 1))
                    }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Editor del Inicio dentro de la isla: ordenar, cambiar el ancho, quitar y agregar tarjetas.
struct EditorDeInicio: View {
    @Bindable var ajustes: Ajustes
    let alTerminar: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tarjetas del Inicio")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Paleta.texto)
                Text("Hasta \(Ajustes.maximoDeTarjetas)").textoDeApoyo()
                Spacer(minLength: 0)
                Button("Listo", action: alTerminar)
                    .buttonStyle(EstiloDePildora())
                    .keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 6) {
                ForEach(Array(ajustes.tarjetasDeInicio.enumerated()), id: \.element.id) { indice, elegida in
                    ficha(elegida, indice: indice)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(Movimiento.seleccion(reducir: reducirMovimiento), value: ajustes.tarjetasDeInicio)
            if !ajustes.tarjetasDisponibles.isEmpty {
                Text("AGREGAR")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                HStack(spacing: 6) {
                    ForEach(ajustes.tarjetasDisponibles) { tarjeta in
                        Button {
                            ajustes.agregarTarjeta(tarjeta)
                        } label: {
                            Label(tarjeta.nombre, systemImage: tarjeta.icono)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(ajustes.puedeAgregarTarjeta ? Paleta.texto : Paleta.decorativo)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(Paleta.superficie, in: Capsule())
                        }
                        .buttonStyle(.presion)
                        .disabled(!ajustes.puedeAgregarTarjeta)
                        .help(ajustes.puedeAgregarTarjeta ? "Agregar \(tarjeta.nombre)" : "Quita una tarjeta primero")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna))
        .overlay(RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna).strokeBorder(Paleta.bordeSuave))
    }

    private func ficha(_ elegida: TarjetaDeInicioElegida, indice: Int) -> some View {
        let tarjeta = elegida.tarjeta
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: tarjeta.icono)
                    .font(.system(size: 11, weight: .semibold))
                Text(tarjeta.nombre)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if ajustes.puedeQuitarTarjeta {
                    boton("xmark", "Quitar \(tarjeta.nombre)") { ajustes.quitarTarjeta(tarjeta) }
                }
            }
            .foregroundStyle(Paleta.texto)
            HStack(spacing: 4) {
                boton("chevron.left", "Mover a la izquierda") { ajustes.moverTarjeta(tarjeta, -1) }
                    .disabled(indice == 0)
                Button {
                    ajustes.cambiarAncho(de: tarjeta, a: elegida.ancho.siguiente)
                } label: {
                    Text(elegida.ancho.nombre)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Paleta.texto)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .background(Paleta.superficieAlta, in: Capsule())
                }
                .buttonStyle(.presion)
                .help("Cambiar el ancho")
                .accessibilityLabel("Ancho de \(tarjeta.nombre): \(elegida.ancho.nombre)")
                boton("chevron.right", "Mover a la derecha") { ajustes.moverTarjeta(tarjeta, 1) }
                    .disabled(indice == ajustes.tarjetasDeInicio.count - 1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Paleta.bordeSuave))
    }

    private func boton(_ simbolo: String, _ etiqueta: String, accion: @escaping @MainActor () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: simbolo)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Paleta.texto)
                .frame(width: 20, height: 20)
                .background(Paleta.superficieAlta, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.presion)
        .help(etiqueta)
        .accessibilityLabel(etiqueta)
    }
}
