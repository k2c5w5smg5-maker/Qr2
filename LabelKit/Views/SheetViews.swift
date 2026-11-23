import SwiftUI
import UIKit

/// Sheet type, start position and look.
struct SheetSettingsSection: View {
    @ObservedObject var studio: LabelStudio

    var body: some View {
        Section {
            Picker("Sheet", selection: $studio.templateID) {
                ForEach(LabelTemplate.all) { template in
                    Text(template.name).tag(template.id)
                }
            }
            Text(studio.template.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Stepper(value: $studio.startPosition, in: 1...studio.template.perPage) {
                Text("Start at label \(studio.startPosition)")
            }
            Picker("Look", selection: $studio.design.look) {
                ForEach(LabelLook.allCases) { Text($0.title).tag($0) }
            }
            Picker("Align", selection: $studio.design.alignment) {
                ForEach(LabelAlignment.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("QR codes", isOn: $studio.design.showQR)
            Toggle("Prices", isOn: $studio.design.showPrice)
            Toggle("Codes / SKUs", isOn: $studio.design.showCode)
            Toggle("Print outlines", isOn: $studio.design.outlines)
        } header: {
            Text("Sheet")
        } footer: {
            Text("Use \"Start at label\" to reuse a part-used sheet. Print at 100% (Actual Size), not \"Fit to page\", so labels line up.")
        }
        .onChange(of: studio.templateID) { _, _ in
            studio.startPosition = min(studio.startPosition, studio.template.perPage)
        }
    }
}

/// Picture of the printed sheet, page by page.
struct SheetPreview: View {
    @ObservedObject var studio: LabelStudio
    @State private var page = 0
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let sheet = studio.sheet
        let pages = sheet.pageCount
        let current = min(page, pages - 1)

        VStack(spacing: 12) {
            if let first = studio.labels.first(where: { !$0.isBlank }) {
                LabelPreview(label: first, design: studio.design, template: studio.template)
            }
            Image(uiImage: sheet.previewImage(page: current, width: 300, scale: displayScale))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .overlay(Rectangle().stroke(.quaternary))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                .accessibilityLabel("Sheet preview, page \(current + 1) of \(pages)")

            HStack {
                Text("\(sheet.slots.count) labels · \(pages) \(pages == 1 ? "sheet" : "sheets")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if pages > 1 {
                    Stepper("Page \(current + 1)", value: $page, in: 0...(pages - 1))
                        .labelsHidden()
                    Text("Page \(current + 1)/\(pages)").font(.footnote.monospacedDigit())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// AirPrint for a finished PDF.
enum PrintController {
    @MainActor
    static func print(pdf url: URL) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = url.deletingPathExtension().lastPathComponent
        controller.printInfo = info
        controller.printingItem = url
        _ = controller.present(animated: true)
    }
}

/// The system share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
