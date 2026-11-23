import SwiftUI

/// Hand-edit one label. Edits made here are what gets printed (and, when training examples
/// are on, what your model learns from).
struct LabelEditView: View {
    @Binding var label: LabelContent
    let design: LabelDesign
    let template: LabelTemplate

    var body: some View {
        Form {
            Section {
                LabelPreview(label: label, design: design, template: template)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            Section("Text") {
                TextField("Title", text: $label.title)
                TextField("Subtitle (brand, size, variant)", text: $label.subtitle)
                ForEach(0..<3, id: \.self) { index in
                    TextField("Detail \(index + 1)", text: detailBinding(index))
                }
            }
            Section("Price and code") {
                TextField("Price, e.g. $19.99", text: $label.price)
                TextField("SKU or barcode number", text: $label.code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            Section {
                TextField("Link or text for the QR code", text: $label.qr)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("QR code")
            } footer: {
                Text("Leave empty for no QR code. Very small labels skip the code so it stays scannable.")
            }
            Section("Copies") {
                Stepper(value: $label.quantity, in: 1...LabelContent.maxQuantity) {
                    Text("\(label.quantity) \(label.quantity == 1 ? "copy" : "copies")")
                }
            }
        }
        .navigationTitle(label.title.isEmpty ? "Label" : label.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < label.details.count ? label.details[index] : "" },
            set: { newValue in
                var details = label.details
                while details.count <= index { details.append("") }
                details[index] = newValue
                // Drop trailing empty lines so the model's output format stays tidy.
                while let last = details.last, last.trimmed.isEmpty { details.removeLast() }
                label.details = details
            }
        )
    }
}

/// A single label drawn at its real proportions.
struct LabelPreview: View {
    let label: LabelContent
    let design: LabelDesign
    let template: LabelTemplate
    var maxWidth: CGFloat = 320
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let size = template.labelSize
        let factor = min(maxWidth / size.width, 220 / size.height)
        let image = LabelRenderer.image(label, design: design, size: size,
                                        cornerRadius: template.cornerRadius,
                                        scale: factor * displayScale)
        Image(uiImage: image)
            .resizable()
            .frame(width: size.width * factor, height: size.height * factor)
            .clipShape(RoundedRectangle(cornerRadius: template.cornerRadius * factor))
            .overlay(RoundedRectangle(cornerRadius: template.cornerRadius * factor).stroke(.quaternary))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            .accessibilityLabel("Label preview: \(label.title)")
    }
}
