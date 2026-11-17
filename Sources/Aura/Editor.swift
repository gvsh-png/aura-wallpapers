import CoreImage
import SwiftUI
import UniformTypeIdentifiers

/// Light, color and blur for the whole picture.
struct Adjustments: Equatable {
    var brightness = 0.0, contrast = 1.0, saturation = 1.0, blur = 0.0, vignette = 0.0

    /// Blur scales with width, so the small preview and the full-size file look the same.
    func apply(to input: CIImage) -> CIImage {
        var img = input.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: brightness, kCIInputContrastKey: contrast, kCIInputSaturationKey: saturation,
        ])
        if blur > 0 { img = img.clampedToExtent().applyingGaussianBlur(sigma: blur * input.extent.width / 400).cropped(to: input.extent) }
        if vignette > 0 { img = img.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: vignette * 2, kCIInputRadiusKey: 1.6]) }
        return img
    }
}

/// Something placed on top of the wallpaper. Position is the center, 0…1 of the picture;
/// size is text height or image width as a share of the picture's width.
struct Layer: Identifiable {
    enum Kind { case text(String), image(URL, CGImage) }
    let id = UUID()
    var kind: Kind
    var x = 0.5, y = 0.5, size = 0.06
    var color = Color.white
}

struct Editor: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let wallpaper: Wallpaper

    @State private var base: CIImage?
    @State private var preview: CGImage?
    @State private var adjust = Adjustments()
    @State private var layers: [Layer] = []
    @State private var selected: UUID?
    @State private var saving = false
    @State private var context = CIContext()

    var body: some View {
        HStack(spacing: 0) {
            canvas.padding(20)
            panel.frame(width: 270).background(Matte.surface)
        }
        .frame(width: 1000, height: 620)
        .background(Matte.bg)
        .font(.sora(12.5))
        .task {
            let url = wallpaper.url
            let cg: CGImage? = await withCheckedContinuation { done in Thumbs.queue.async { done.resume(returning: Thumbs.decode(url, maxPixel: 1600)) } }
            if let cg { base = CIImage(cgImage: cg); render() }
        }
        .onChange(of: adjust) { render() }
    }

    // MARK: Canvas

    private var canvas: some View {
        let aspect = base.map { $0.extent.width / $0.extent.height } ?? 16 / 10
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                if let preview { Image(decorative: preview, scale: 1).resizable() } else { Matte.surface }
                ForEach($layers) { $layer in
                    layerView(layer, width: w)
                        .overlay {
                            if selected == layer.id { RoundedRectangle(cornerRadius: 4).strokeBorder(.tint, style: StrokeStyle(lineWidth: 1.5, dash: [4])).padding(-6) }
                        }
                        .position(x: layer.x * w, y: layer.y * h)
                        .gesture(DragGesture(coordinateSpace: .named("canvas")).onChanged { v in
                            selected = layer.id
                            layer.x = min(max(v.location.x / w, 0), 1)
                            layer.y = min(max(v.location.y / h, 0), 1)
                        })
                        .onTapGesture { selected = layer.id }
                }
            }
            .coordinateSpace(name: "canvas")
            .contentShape(Rectangle())
            .onTapGesture { selected = nil }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Matte.line))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func layerView(_ layer: Layer, width: CGFloat) -> some View {
        switch layer.kind {
        case .text(let s):
            Text(s.isEmpty ? " " : s)
                .font(.sora(layer.size * width, .semibold))
                .foregroundStyle(layer.color)
                .shadow(color: .black.opacity(0.45), radius: layer.size * width * 0.12)
                .fixedSize()
        case .image(_, let cg):
            Image(decorative: cg, scale: 1).resizable().aspectRatio(contentMode: .fit)
                .frame(width: layer.size * width * 4)
        }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Customize").font(.sora(16, .semibold))
            group("Adjust") {
                slider("Brightness", $adjust.brightness, -0.3...0.3)
                slider("Contrast", $adjust.contrast, 0.7...1.4)
                slider("Saturation", $adjust.saturation, 0...2)
                slider("Blur", $adjust.blur, 0...1)
                slider("Vignette", $adjust.vignette, 0...1)
            }
            group("Add") {
                HStack {
                    Button { add(Layer(kind: .text("Your text"))) } label: { Label("Text", systemImage: "textformat") }.buttonStyle(.matte)
                    Button { addImage() } label: { Label("Image", systemImage: "photo.badge.plus") }.buttonStyle(.matte)
                }
            }
            if let i = layers.firstIndex(where: { $0.id == selected }) {
                group("Selected") {
                    if case .text(let s) = layers[i].kind {
                        MatteField(prompt: "Text", text: Binding(get: { s }, set: { layers[i].kind = .text($0) }), symbol: "textformat")
                        ColorPicker("Color", selection: $layers[i].color, supportsOpacity: false).font(.sora(12))
                    }
                    slider("Size", $layers[i].size, 0.015...0.25)
                    Button("Remove", role: .destructive) { layers.remove(at: i); selected = nil }.buttonStyle(.matte)
                }
            }
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.matte).keyboardShortcut(.cancelAction)
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Save & Set") { save() }.buttonStyle(.accent).disabled(saving || base == nil).keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.sora(10.5, .semibold)).tracking(1.2).foregroundStyle(Matte.dim)
            content()
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sora(11.5)).foregroundStyle(Matte.dim)
            Slider(value: value, in: range).controlSize(.small)
        }
    }

    // MARK: Actions

    private func add(_ layer: Layer) {
        layers.append(layer)
        selected = layer.id
    }

    private func addImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url, let cg = Thumbs.decode(url, maxPixel: 800) else { return }
        add(Layer(kind: .image(url, cg), size: 0.06))
    }

    private func render() {
        guard let base else { return }
        preview = context.createCGImage(adjust.apply(to: base), from: base.extent)
    }

    /// Renders at full size into a new file next to the original, then puts it on the desktop.
    private func save() {
        saving = true
        let (url, adjust, layers, context) = (wallpaper.url, adjust, layers, context)
        let dest = library.uniqueURL(base: "\(wallpaper.collection) - \(wallpaper.title) custom", ext: "jpg")
        let texts = layers.map { l -> (Layer, NSColor) in (l, NSColor(l.color)) }
        Task.detached(priority: .userInitiated) {
            let ok = Self.renderFull(url, adjust: adjust, layers: texts, context: context, to: dest)
            await MainActor.run {
                saving = false
                guard ok else { return }
                library.reload()
                library.setDesktop(Wallpaper(url: dest))
                dismiss()
            }
        }
    }

    nonisolated private static func renderFull(_ url: URL, adjust: Adjustments, layers: [(Layer, NSColor)], context: CIContext, to dest: URL) -> Bool {
        guard let input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              let filtered = context.createCGImage(adjust.apply(to: input), from: input.extent) else { return false }
        let W = filtered.width, H = filtered.height
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(filtered, in: CGRect(x: 0, y: 0, width: W, height: H))
        // Flip so layer positions read top-left like the preview.
        ctx.translateBy(x: 0, y: CGFloat(H))
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let width = CGFloat(W)
        for (layer, color) in layers {
            let center = CGPoint(x: layer.x * width, y: layer.y * CGFloat(H))
            switch layer.kind {
            case .text(let s):
                let size = layer.size * width
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
                shadow.shadowBlurRadius = size * 0.12
                let font = NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: "Sora", .traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.semibold]]), size: size)
                    ?? .systemFont(ofSize: size, weight: .semibold)
                let text = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .shadow: shadow])
                let box = text.size()
                text.draw(at: CGPoint(x: center.x - box.width / 2, y: center.y - box.height / 2))
            case .image(let file, _):
                let w = layer.size * width * 4
                guard let cg = Thumbs.decode(file, maxPixel: Int(w * 1.2)) else { continue }
                let h = w * CGFloat(cg.height) / CGFloat(cg.width)
                NSImage(cgImage: cg, size: .zero).draw(in: CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h),
                                                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let out = ctx.makeImage() else { return false }
        return Thumbs.writeJPEG(out, to: dest, quality: 0.92)
    }
}
