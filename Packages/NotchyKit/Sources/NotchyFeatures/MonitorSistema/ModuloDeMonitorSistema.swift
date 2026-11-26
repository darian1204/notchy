import Foundation
import NotchyCore
import NotchyDesign
import Observation
import SwiftUI

/// Modelo observable del módulo System Monitor (System Analytics en vivo).
@MainActor
@Observable
public final class ModeloDeMonitorSistema {
    public private(set) var metricas: MetricasDelSistema

    @ObservationIgnored private let puerto: any PuertoMonitorDelSistema
    @ObservationIgnored private var tareaRefresco: Task<Void, Never>?
    @ObservationIgnored private var tareaEventosIsla: Task<Void, Never>?
    @ObservationIgnored private let bus: BusDeEventos?

    /// Con `bus`, solo se refresca mientras la isla está abierta (las métricas solo se ven ahí).
    /// Sin `bus`, refresca siempre.
    public init(puerto: any PuertoMonitorDelSistema, bus: BusDeEventos? = nil) {
        self.puerto = puerto
        self.bus = bus
        self.metricas = puerto.leerMetricas()
    }

    public func iniciar() {
        detener()
        actualizar()
        guard let bus else {
            refrescarCadaDosSegundos()
            return
        }
        tareaEventosIsla = Task { [weak self] in
            let flujo = await bus.suscribir(a: IslaCambioDeEstado.self)
            for await cambio in flujo {
                guard !Task.isCancelled, let self else { break }
                if cambio.moduloAbierto != nil {
                    if self.tareaRefresco == nil {
                        self.actualizar()
                        self.refrescarCadaDosSegundos()
                    }
                } else {
                    self.tareaRefresco?.cancel()
                    self.tareaRefresco = nil
                }
            }
        }
    }

    private func refrescarCadaDosSegundos() {
        tareaRefresco?.cancel()
        tareaRefresco = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                self?.actualizar()
            }
        }
    }

    public func detener() {
        tareaRefresco?.cancel()
        tareaRefresco = nil
        tareaEventosIsla?.cancel()
        tareaEventosIsla = nil
    }

    public func actualizar() {
        metricas = puerto.leerMetricas()
    }
}

/// Módulo de System Monitor en el notch (`gauge.with.dots.needle.67percent`).
@MainActor
public final class ModuloDeMonitorSistema: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "monitor",
        nombre: "Sistema",
        icono: "gauge.with.dots.needle.67percent",
        color: Paleta.hexMonitorSistema,
        lado: .derecha
    )
    public let tamanoExpandido = Medidas.monitorSistema
    public let modelo: ModeloDeMonitorSistema

    public init(modelo: ModeloDeMonitorSistema) {
        self.modelo = modelo
    }

    public var salud: SaludDeModulo { .listo }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeMonitorSistema(modelo: modelo))
    }

    public func arrancar() {
        modelo.iniciar()
    }

    public func detener() {
        modelo.detener()
    }
}

struct VistaDeMonitorSistema: View {
    let modelo: ModeloDeMonitorSistema
    private let columnas = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        let m = modelo.metricas
        VStack(alignment: .leading, spacing: 8) {
            encabezado

            LazyVGrid(columns: columnas, spacing: 8) {
                tarjetaMetrica(
                    icono: "cpu",
                    titulo: "CPU",
                    color: Color(hex: 0x30D158),
                    porcentajeAnillo: m.usoCPUPorcentaje,
                    etiquetaAnillo: "\(Int(m.usoCPUPorcentaje.rounded()))%",
                    valorPrincipal: "\(Int(m.usoCPUPorcentaje.rounded()))%",
                    subtitulo: "Usage"
                )

                tarjetaMetrica(
                    icono: "memorychip",
                    titulo: "Memory",
                    color: Color(hex: 0x5AA9FF),
                    porcentajeAnillo: m.memoriaPorcentaje,
                    etiquetaAnillo: "\(Int(m.memoriaPorcentaje.rounded()))%",
                    valorPrincipal: "\(Int(m.memoriaPorcentaje.rounded()))%",
                    subtitulo: String(format: "%.1f GB / %.0f GB", m.memoriaUsadaGB, m.memoriaTotalGB)
                )

                tarjetaMetrica(
                    icono: "internaldrive",
                    titulo: "Storage",
                    color: Color(hex: 0x30D158),
                    porcentajeAnillo: m.almacenamientoUsadoPorcentaje,
                    etiquetaAnillo: "\(Int(m.almacenamientoUsadoPorcentaje.rounded()))%",
                    valorPrincipal: "\(Int(m.almacenamientoUsadoPorcentaje.rounded()))%",
                    subtitulo: String(format: "%.1f GB free", m.discoLibreGB)
                )

                tarjetaMetrica(
                    icono: "network",
                    titulo: "Network",
                    color: Color(hex: 0x30D158),
                    porcentajeAnillo: min(100, max(12, log10(max(10, m.redBytesPorSegundo)) * 18.0)),
                    etiquetaAnillo: "LIVE",
                    valorPrincipal: MetricasDelSistema.formatearVelocidadRed(m.redBytesPorSegundo),
                    subtitulo: "Throughput"
                )

                tarjetaMetrica(
                    icono: m.bateriaCargando ? "battery.100percent.bolt" : "battery.75percent",
                    titulo: "Battery",
                    color: Color(hex: 0x4FC3F7),
                    porcentajeAnillo: Double(m.bateriaPorcentaje),
                    etiquetaAnillo: "\(m.bateriaPorcentaje)%",
                    valorPrincipal: "\(m.bateriaPorcentaje)%",
                    subtitulo: m.bateriaCargando ? "Charging" : "On Battery"
                )

                tarjetaMetrica(
                    icono: "externaldrive.fill.badge.checkmark",
                    titulo: "Free Disk",
                    color: Color(hex: 0x5AA9FF),
                    porcentajeAnillo: m.discoLibrePorcentaje,
                    etiquetaAnillo: "\(Int(m.discoLibrePorcentaje.rounded()))%",
                    valorPrincipal: String(format: "%.1f GB", m.discoLibreGB),
                    subtitulo: String(format: "of %.0f GB total", m.discoTotalGB)
                )
            }
        }
        .padding(.horizontal, 4)
    }

    private var encabezado: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Paleta.textoDeApoyo)

            VStack(alignment: .leading, spacing: 0) {
                Text("System Analytics")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Paleta.texto)
                Text("Live system stats")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Paleta.textoDeApoyo)
            }

            Spacer(minLength: 0)

            Button {
                modelo.actualizar()
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Paleta.textoDeApoyo)
            }
            .buttonStyle(.plain)
            .help("Actualizar métricas ahora")
            .accessibilityLabel("Actualizar métricas ahora")
        }
    }

    private func tarjetaMetrica(
        icono: String,
        titulo: String,
        color: Color,
        porcentajeAnillo: Double,
        etiquetaAnillo: String,
        valorPrincipal: String,
        subtitulo: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icono)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(color)
                Text(titulo)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                AnilloSegmentado(
                    fraccion: min(max(porcentajeAnillo / 100.0, 0.04), 1.0),
                    color: color,
                    etiqueta: etiquetaAnillo
                )
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(valorPrincipal)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Paleta.texto)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(subtitulo)
                        .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Paleta.textoDeApoyo)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Paleta.borde.opacity(0.65), lineWidth: 1)
        )
    }
}

/// Anillo circular segmentado estilo System Analytics.
struct AnilloSegmentado: View {
    let fraccion: Double
    let color: Color
    let etiqueta: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [2.2, 2.2])
                )

            Circle()
                .trim(from: 0, to: CGFloat(fraccion))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [2.2, 2.2])
                )
                .rotationEffect(.degrees(-90))

            Text(etiqueta)
                .font(.system(size: 7.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Paleta.textoDeApoyo)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
