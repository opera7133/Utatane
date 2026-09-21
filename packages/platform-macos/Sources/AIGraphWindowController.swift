import AppKit
import SwiftUI

public struct AIGraphSeries: Identifiable, Sendable, Equatable {
    public let id: Int
    public let values: [Double]
    public let labels: [String]
    public let additions: [Double]
    public let maxima: [Double]

    public init?(id: Int, response: String) {
        let fields = response.components(separatedBy: "\u{1}")
        let values = Self.numbers(fields.first ?? "")
        guard !values.isEmpty else { return nil }

        let defaultLabels = ["Neuron", "NeuronM", "NeuronK", "NeuronD", "NeuronE", "Synapse"]
        let suppliedLabels = fields.count > 1
            ? fields[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            : []
        let suppliedAdditions = fields.count > 2 ? Self.numbers(fields[2]) : []
        let suppliedMaxima = fields.count > 3 ? Self.numbers(fields[3]) : []
        let totals = values.enumerated().map { index, value in
            value + (suppliedAdditions.indices.contains(index) ? suppliedAdditions[index] : 0)
        }
        let commonMaximum = max(totals.max() ?? 0, 1)

        self.id = id
        self.values = values
        labels = values.indices.map { index in
            if suppliedLabels.indices.contains(index), !suppliedLabels[index].isEmpty {
                return suppliedLabels[index]
            }
            if defaultLabels.indices.contains(index) {
                return defaultLabels[index]
            }
            return "Value \(index + 1)"
        }
        additions = values.indices.map { index in
            suppliedAdditions.indices.contains(index) ? suppliedAdditions[index] : 0
        }
        maxima = values.indices.map { index in
            max(suppliedMaxima.indices.contains(index) ? suppliedMaxima[index] : commonMaximum, 1)
        }
    }

    private static func numbers(_ value: String) -> [Double] {
        let fields = value.split(separator: ",", omittingEmptySubsequences: false)
        guard !fields.isEmpty else { return [] }

        var numbers: [Double] = []
        numbers.reserveCapacity(fields.count)
        for field in fields {
            guard let number = Double(field.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return []
            }
            numbers.append(number)
        }
        return numbers
    }
}

@MainActor
public final class AIGraphWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    public var isVisible: Bool {
        window?.isVisible == true
    }

    public func show(title: String, series: [AIGraphSeries]) {
        guard !series.isEmpty else { return }
        let view = AIGraphView(title: title, series: series)
        if let window {
            window.title = title
            window.contentViewController = NSHostingController(rootView: view)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 640, height: 520))
        window.minSize = NSSize(width: 420, height: 360)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        window?.close()
    }

    public func windowWillClose(_: Notification) {
        window = nil
    }
}

private struct AIGraphView: View {
    let title: String
    let series: [AIGraphSeries]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                ForEach(series) { graph in
                    VStack(alignment: .leading, spacing: 10) {
                        if series.count > 1 {
                            Text("AI \(graph.id)")
                                .font(.headline)
                        }
                        RadarChart(series: graph)
                            .frame(minHeight: 260)
                    }
                    .padding(14)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(20)
        }
        .navigationTitle(title)
    }
}

private struct RadarChart: View {
    let series: AIGraphSeries

    var body: some View {
        Canvas { context, size in
            guard series.values.count >= 3 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(20, min(size.width, size.height) / 2 - 42)
            let count = series.values.count

            for step in 1 ... 4 {
                let scale = CGFloat(step) / 4
                context.stroke(polygon(center: center, radius: radius * scale, count: count),
                               with: .color(.secondary.opacity(0.25)), lineWidth: 1)
            }

            for index in 0 ..< count {
                let point = vertex(center: center, radius: radius, index: index, count: count)
                var axis = Path()
                axis.move(to: center)
                axis.addLine(to: point)
                context.stroke(axis, with: .color(.secondary.opacity(0.3)), lineWidth: 1)

                let labelPoint = vertex(center: center, radius: radius + 24, index: index, count: count)
                context.draw(
                    Text(series.labels[index]).font(.caption).foregroundStyle(.secondary),
                    at: labelPoint,
                    anchor: .center
                )
            }

            let basePoints = normalizedPoints(values: series.values, additions: Array(repeating: 0, count: count), center: center, radius: radius)
            let totalPoints = normalizedPoints(values: series.values, additions: series.additions, center: center, radius: radius)
            draw(points: totalPoints, color: .orange, context: &context)
            draw(points: basePoints, color: .accentColor, context: &context)
        }
        .accessibilityLabel("\(titleForAccessibility) AI graph")
    }

    private var titleForAccessibility: String {
        series.labels.enumerated().map { index, label in
            let total = series.values[index] + series.additions[index]
            return "\(label) \(total) / \(series.maxima[index])"
        }.joined(separator: ", ")
    }

    private func normalizedPoints(
        values: [Double], additions: [Double], center: CGPoint, radius: CGFloat
    ) -> [CGPoint] {
        values.indices.map { index in
            let maximum = max(series.maxima[index], 1)
            let fraction = min(max((values[index] + additions[index]) / maximum, 0), 1)
            return vertex(center: center, radius: radius * CGFloat(fraction), index: index, count: values.count)
        }
    }

    private func draw(points: [CGPoint], color: Color, context: inout GraphicsContext) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(0.18)))
        context.stroke(path, with: .color(color), lineWidth: 2)
    }

    private func polygon(center: CGPoint, radius: CGFloat, count: Int) -> Path {
        var path = Path()
        for index in 0 ..< count {
            let point = vertex(center: center, radius: radius, index: index, count: count)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func vertex(center: CGPoint, radius: CGFloat, index: Int, count: Int) -> CGPoint {
        let angle = Double(index) * 2 * .pi / Double(count) - .pi / 2
        return CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }
}
