import SwiftUI

/// Lets the user pick a square or rectangular output and adjust its pixel dimensions.
struct ShapeSettingsView: View {
    @Binding var canvas: CanvasSpec

    private struct Preset: Identifiable {
        let id: String
        let ratio: Double
    }

    private let presets = [
        Preset(id: "3:2", ratio: 3.0 / 2.0),
        Preset(id: "16:9", ratio: 16.0 / 9.0),
        Preset(id: "2:1", ratio: 2.0),
        Preset(id: "2:3", ratio: 2.0 / 3.0),
        Preset(id: "9:16", ratio: 9.0 / 16.0),
    ]

    var body: some View {
        Picker("Shape", selection: $canvas.shape) {
            ForEach(CanvasShape.allCases) { shape in
                Text(shape.title).tag(shape)
            }
        }
        .pickerStyle(.segmented)

        if canvas.shape == .square {
            SizeControl(title: "Size", value: $canvas.width)
        } else {
            SizeControl(title: "Width", value: $canvas.width)
            SizeControl(title: "Height", value: $canvas.height)
            HStack {
                Text("Presets")
                Spacer()
                ForEach(presets) { preset in
                    Button(preset.id) {
                        let height = Int((Double(canvas.width) / preset.ratio).rounded())
                        canvas.height = height.clamped(to: CanvasSpec.minSide...CanvasSpec.maxSide)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .font(.footnote)
        }

        LabeledContent("Output", value: canvas.summary)
    }
}

/// A slider plus stepper for one pixel dimension.
struct SizeControl: View {
    let title: String
    @Binding var value: Int

    private var range: ClosedRange<Double> {
        Double(CanvasSpec.minSide)...Double(CanvasSpec.maxSide)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value) px")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { value = Int($0.rounded()) }
                    ),
                    in: range,
                    step: 16
                )
                Stepper("", value: $value, in: CanvasSpec.minSide...CanvasSpec.maxSide, step: 64)
                    .labelsHidden()
            }
        }
    }
}
