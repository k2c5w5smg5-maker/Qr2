import SwiftUI

/// Renders a code off the main thread and shows it. When `obscured` is true the image is
/// blurred and badged so it can be previewed but not scanned or screenshotted before purchase.
struct QRImage: View {
    let content: String?
    let style: QRStyle
    var maxSide: CGFloat = 260
    var obscured = false

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private struct RenderKey: Equatable {
        let content: String?
        let style: QRStyle
        let maxSide: CGFloat
    }

    /// The largest size with the canvas's aspect ratio that fits in a `maxSide` square.
    private var fittedSize: CGSize {
        let ratio = style.canvas.aspectRatio
        return ratio >= 1
            ? CGSize(width: maxSide, height: maxSide / ratio)
            : CGSize(width: maxSide * ratio, height: maxSide)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .blur(radius: obscured ? 9 : 0)
                    .overlay {
                        if obscured {
                            Label("Preview", systemImage: "lock.fill")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .overlay {
                        if content == nil {
                            Text("Enter a valid link to see a preview")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding()
                        } else {
                            ProgressView()
                        }
                    }
            }
        }
        .frame(width: fittedSize.width, height: fittedSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: RenderKey(content: content, style: style, maxSide: maxSide)) {
            guard let content else {
                image = nil
                return
            }
            let style = style, maxSide = maxSide, scale = displayScale
            let rendered = await Task.detached(priority: .userInitiated) {
                QRRenderer.previewImage(for: content, style: style, maxSide: maxSide, scale: scale)
            }.value
            if !Task.isCancelled { image = rendered }
        }
    }
}
