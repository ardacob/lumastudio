import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
struct LumaStudioApp: App {
    @StateObject private var editor = PhotoEditor()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environmentObject(editor)
                .preferredColorScheme(ThemeChoice(rawValue: appearance)?.colorScheme)
                .frame(minWidth: 1100, minHeight: 720)
                .onOpenURL { editor.open($0) }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Yeni Tuval…") { editor.showNewCanvas = true }
                    .keyboardShortcut("n")
                Button("Görsel Aç…") { editor.openPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .saveItem) {
                Button("Katmanlı Projeyi Kaydet…") { editor.saveProjectPanel() }
                    .keyboardShortcut("s")
                    .disabled(!editor.hasImage)
                Button("Dışa Aktar…") { editor.exportPanel() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!editor.hasImage)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Geri Al") { editor.undo() }
                    .keyboardShortcut("z")
                    .disabled(!editor.canUndo)
                Button("Yinele") { editor.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!editor.canRedo)
            }
        }
    }
}

private enum ThemeChoice: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Sistem"
        case .light: "Açık"
        case .dark: "Koyu"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Adjustment: String, CaseIterable, Identifiable, Codable {
    case exposure = "Pozlama"
    case brightness = "Parlaklık"
    case contrast = "Kontrast"
    case highlights = "Açık alanlar"
    case shadows = "Gölgeler"
    case saturation = "Doygunluk"
    case vibrance = "Canlılık"
    case warmth = "Sıcaklık"
    case sharpen = "Keskinlik"
    case vignette = "Vinyet"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .exposure: "plusminus.circle"
        case .brightness: "sun.max"
        case .contrast: "circle.lefthalf.filled"
        case .highlights: "sun.max.fill"
        case .shadows: "moon.fill"
        case .saturation: "drop.fill"
        case .vibrance: "sparkles"
        case .warmth: "thermometer.medium"
        case .sharpen: "viewfinder"
        case .vignette: "circle.dotted.circle"
        }
    }
    var range: ClosedRange<Double> {
        switch self {
        case .exposure: -2...2
        case .brightness, .contrast, .saturation, .vibrance, .warmth: -1...1
        case .highlights, .shadows, .sharpen, .vignette: 0...1
        }
    }
}

enum CropRatio: String, CaseIterable, Identifiable, Codable {
    case original = "Özgün"
    case square = "1:1"
    case landscape = "4:3"
    case photo = "3:2"
    case wide = "16:9"
    case portrait = "4:5"

    var id: String { rawValue }
    var ratio: CGFloat? {
        switch self {
        case .original: nil
        case .square: 1
        case .landscape: 4 / 3
        case .photo: 3 / 2
        case .wide: 16 / 9
        case .portrait: 4 / 5
        }
    }
}

struct EditState: Equatable, Codable {
    var values: [Adjustment: Double] = [:]
    var crop: CropRatio = .original
    var turns = 0
    var flipped = false

    func value(_ adjustment: Adjustment) -> Double { values[adjustment, default: 0] }
}

enum LayerKind: String, Codable {
    case image, text, paint, rectangle, ellipse

    var symbol: String {
        switch self {
        case .image: "photo"
        case .text: "textformat"
        case .paint: "paintbrush.pointed"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        }
    }
}

struct LayerColor: Codable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat = 1

    static let blue = LayerColor(red: 0.34, green: 0.43, blue: 0.94)
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    init(_ color: Color) {
        let value = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        self.init(red: value.redComponent, green: value.greenComponent,
                  blue: value.blueComponent, alpha: value.alphaComponent)
    }
}

struct PaintStroke: Codable {
    var points: [CGPoint]
    var width: CGFloat
    var color: LayerColor
}

struct CanvasLayer: Identifiable {
    var id = UUID()
    var name: String
    var kind: LayerKind
    var image: CIImage?
    var position: CGPoint
    var size: CGSize
    var opacity = 1.0
    var isVisible = true
    var text = ""
    var fontSize: CGFloat = 72
    var fill = LayerColor.blue
    var strokes: [PaintStroke] = []
}

private struct LayerArchive: Codable {
    var id: UUID
    var name: String
    var kind: LayerKind
    var imagePNG: Data?
    var position: CGPoint
    var size: CGSize
    var opacity: Double
    var isVisible: Bool
    var text: String
    var fontSize: CGFloat
    var fill: LayerColor
    var strokes: [PaintStroke]
}

private struct ProjectArchive: Codable {
    var version = 1
    var basePNG: Data
    var layers: [LayerArchive]
    var state: EditState
}

private struct DocumentSnapshot {
    var state: EditState
    var layers: [CanvasLayer]
    var selectedLayerID: UUID?
}

struct ExportFormat: Identifiable, Hashable {
    let type: UTType
    let name: String
    var id: String { type.identifier }

    static let supported: [ExportFormat] = {
        let encoders = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        let candidates: [(String, String)] = [
            ("public.png", "PNG"), ("public.jpeg", "JPEG"),
            ("public.heic", "HEIC"), ("public.tiff", "TIFF"),
            ("com.microsoft.bmp", "BMP"), ("com.compuserve.gif", "GIF"),
            ("org.webmproject.webp", "WebP"), ("public.avif", "AVIF"),
            ("com.adobe.photoshop-image", "PSD")
        ]
        return candidates.compactMap { identifier, name in
            guard encoders.contains(identifier), let type = UTType(identifier) else { return nil }
            return ExportFormat(type: type, name: name)
        }
    }()
}

@MainActor
final class PhotoEditor: ObservableObject {
    @Published private(set) var preview: NSImage?
    @Published private(set) var fileName = "Adsız çalışma"
    @Published private(set) var pixelSize = CGSize.zero
    @Published private(set) var state = EditState()
    @Published private(set) var layers: [CanvasLayer] = []
    @Published var selectedLayerID: UUID?
    @Published var errorMessage: String?
    @Published var selectedFormat: ExportFormat {
        didSet { UserDefaults.standard.set(selectedFormat.id, forKey: "preferredExportFormat") }
    }
    @Published var exportQuality: Double {
        didSet { UserDefaults.standard.set(exportQuality, forKey: "exportQuality") }
    }
    @Published var zoom = 1.0
    @Published var showOriginal = false
    @Published var showNewCanvas = false
    @Published private(set) var isDirty = false

    private var source: CIImage?
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private var undoStack: [DocumentSnapshot] = []
    private var redoStack: [DocumentSnapshot] = []
    private var interactionStart: DocumentSnapshot?

    init() {
        let savedFormat = UserDefaults.standard.string(forKey: "preferredExportFormat")
        selectedFormat = ExportFormat.supported.first { $0.id == savedFormat }
            ?? ExportFormat.supported.first
            ?? ExportFormat(type: .png, name: "PNG")
        exportQuality = UserDefaults.standard.object(forKey: "exportQuality") as? Double ?? 0.92
    }

    var hasImage: Bool { source != nil }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selectedLayer: CanvasLayer? { layers.first { $0.id == selectedLayerID } }
    private var cropRect: CGRect {
        let full = CGRect(origin: .zero, size: pixelSize)
        guard let ratio = state.crop.ratio else { return full }
        let width = min(full.width, full.height * ratio)
        let height = min(full.height, full.width / ratio)
        return CGRect(x: (full.width - width) / 2, y: (full.height - height) / 2,
                      width: width, height: height)
    }
    var displayedCanvasSize: CGSize {
        let crop = cropRect
        return state.turns % 2 == 0 ? crop.size : CGSize(width: crop.height, height: crop.width)
    }

    func canvasPoint(_ point: CGPoint, in displaySize: CGSize) -> CGPoint {
        let crop = cropRect
        let size = displayedCanvasSize
        let x = point.x / displaySize.width * size.width
        let y = (displaySize.height - point.y) / displaySize.height * size.height
        let local: CGPoint
        switch ((state.turns % 4) + 4) % 4 {
        case 1: local = CGPoint(x: crop.width - y, y: x)
        case 2: local = CGPoint(x: crop.width - x, y: crop.height - y)
        case 3: local = CGPoint(x: y, y: crop.height - x)
        default: local = CGPoint(x: x, y: y)
        }
        return CGPoint(x: local.x + crop.minX, y: local.y + crop.minY)
    }

    func moveSelected(screenTranslation: CGSize, displaySize: CGSize) {
        let actual = displayedCanvasSize
        let dx = screenTranslation.width / displaySize.width * actual.width
        let dy = -screenTranslation.height / displaySize.height * actual.height
        let delta: CGPoint
        switch ((state.turns % 4) + 4) % 4 {
        case 1: delta = CGPoint(x: -dy, y: dx)
        case 2: delta = CGPoint(x: -dx, y: -dy)
        case 3: delta = CGPoint(x: dy, y: -dx)
        default: delta = CGPoint(x: dx, y: dy)
        }
        moveSelected(dx: delta.x, dy: delta.y)
    }
    var dimensions: String {
        guard hasImage else { return "Görsel seçilmedi" }
        return "\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px"
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.title = "Bir görsel aç"
        panel.prompt = "Aç"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // ImageIO and Core Image determine which installed image codecs can be read.
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard confirmReplacingDocument() else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "luma" {
            openProject(url)
            return
        }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            errorMessage = "Bu dosya macOS tarafından görsel olarak açılamadı."
            return
        }
        source = image
        fileName = url.deletingPathExtension().lastPathComponent
        pixelSize = image.extent.size
        state = EditState()
        layers = []
        selectedLayerID = nil
        undoStack = []
        redoStack = []
        zoom = 1
        showOriginal = false
        isDirty = false
        renderPreview()
    }

    func newCanvas(width: Int, height: Int, background: Color) {
        guard width >= 64, height >= 64, width <= 10000, height <= 10000,
              width * height <= 60_000_000 else {
            errorMessage = "Tuval boyutu 64–10.000 piksel aralığında ve en fazla 60 megapiksel olmalı."
            return
        }
        guard confirmReplacingDocument() else { return }
        let color = LayerColor(background)
        source = CIImage(color: CIColor(red: color.red, green: color.green,
                                        blue: color.blue, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        fileName = "Yeni tuval"
        pixelSize = CGSize(width: width, height: height)
        state = EditState()
        layers = []
        selectedLayerID = nil
        undoStack = []
        redoStack = []
        zoom = 1
        showOriginal = false
        showNewCanvas = false
        isDirty = true
        renderPreview()
    }

    private func confirmReplacingDocument() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Kaydedilmemiş değişiklikler var"
        alert.informativeText = "Yeni bir çalışma açarsanız mevcut katman düzenlemeleri kaybolur."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "İptal")
        alert.addButton(withTitle: "Değişiklikleri at")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func set(_ adjustment: Adjustment, value: Double) {
        state.values[adjustment] = value
        isDirty = true
        renderPreview()
    }

    private func snapshot() -> DocumentSnapshot {
        DocumentSnapshot(state: state, layers: layers, selectedLayerID: selectedLayerID)
    }
    private func restore(_ snapshot: DocumentSnapshot) {
        state = snapshot.state
        layers = snapshot.layers
        selectedLayerID = snapshot.selectedLayerID
        renderPreview()
    }

    func beginInteraction() { interactionStart = snapshot() }
    func endInteraction() {
        if let before = interactionStart, before.state != state {
            undoStack.append(before)
            redoStack.removeAll()
        }
        interactionStart = nil
    }

    func change(_ mutation: (inout EditState) -> Void) {
        let before = snapshot()
        mutation(&state)
        if before.state != state {
            undoStack.append(before)
            redoStack.removeAll()
            isDirty = true
            renderPreview()
        }
    }

    func reset() { change { $0 = EditState() } }
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        restore(previous)
        isDirty = true
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        restore(next)
        isDirty = true
    }

    func applyPreset(_ preset: Preset) {
        change { value in value.values = preset.values }
    }

    private func mutateLayers(_ action: () -> Void) {
        undoStack.append(snapshot())
        redoStack.removeAll()
        isDirty = true
        action()
        renderPreview()
    }

    func addImageLayerPanel() {
        guard hasImage else { return }
        let panel = NSOpenPanel()
        panel.title = "Katman olarak görsel ekle"
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { addImageLayer(url) }
    }

    func addImageLayer(_ url: URL) {
        guard hasImage else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            errorMessage = "Bu görsel katman olarak eklenemedi."
            return
        }
        let width = min(pixelSize.width * 0.55, image.extent.width)
        let height = width * image.extent.height / image.extent.width
        let size = CGSize(width: width, height: height)
        let layer = CanvasLayer(name: url.deletingPathExtension().lastPathComponent,
                                kind: .image, image: image,
                                position: CGPoint(x: (pixelSize.width - width) / 2,
                                                  y: (pixelSize.height - height) / 2), size: size)
        mutateLayers { layers.append(layer); selectedLayerID = layer.id }
    }

    func addTextLayer(_ text: String) {
        guard hasImage, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let size = CGSize(width: pixelSize.width * 0.7, height: min(180, pixelSize.height * 0.2))
        var layer = CanvasLayer(name: "Metin", kind: .text, image: nil,
                                position: CGPoint(x: pixelSize.width * 0.15,
                                                  y: (pixelSize.height - size.height) / 2), size: size)
        layer.text = text
        layer.fontSize = max(20, min(72, pixelSize.width * 0.06))
        mutateLayers { layers.append(layer); selectedLayerID = layer.id }
    }

    func addShapeLayer(_ kind: LayerKind, color: Color) {
        guard hasImage, kind == .rectangle || kind == .ellipse else { return }
        let size = CGSize(width: pixelSize.width * 0.3, height: pixelSize.height * 0.25)
        var layer = CanvasLayer(name: kind == .rectangle ? "Dikdörtgen" : "Elips",
                                kind: kind, image: nil,
                                position: CGPoint(x: (pixelSize.width - size.width) / 2,
                                                  y: (pixelSize.height - size.height) / 2), size: size)
        layer.fill = LayerColor(color)
        mutateLayers { layers.append(layer); selectedLayerID = layer.id }
    }

    func addStroke(points: [CGPoint], width: CGFloat, color: Color) {
        guard hasImage, !points.isEmpty else { return }
        let stroke = PaintStroke(points: points, width: width, color: LayerColor(color))
        mutateLayers {
            if let index = layers.firstIndex(where: { $0.id == selectedLayerID && $0.kind == .paint }) {
                layers[index].strokes.append(stroke)
            } else {
                var layer = CanvasLayer(name: "Fırça", kind: .paint, image: nil,
                                        position: .zero, size: pixelSize)
                layer.strokes = [stroke]
                layers.append(layer)
                selectedLayerID = layer.id
            }
        }
    }

    func moveSelected(dx: CGFloat, dy: CGFloat) {
        guard let index = layers.firstIndex(where: { $0.id == selectedLayerID }),
              layers[index].kind != .paint else { return }
        mutateLayers { layers[index].position.x += dx; layers[index].position.y += dy }
    }

    func setSelectedOpacity(_ value: Double) {
        guard let index = layers.firstIndex(where: { $0.id == selectedLayerID }) else { return }
        layers[index].opacity = value
        isDirty = true
        renderPreview()
    }

    func commitLayerInteraction(_ before: [CanvasLayer]) {
        guard layers.count == before.count else { return }
        undoStack.append(DocumentSnapshot(state: state, layers: before, selectedLayerID: selectedLayerID))
        redoStack.removeAll()
        isDirty = true
    }

    func toggleVisibility(_ id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        mutateLayers { layers[index].isVisible.toggle() }
    }

    func moveLayer(_ id: UUID, direction: Int) {
        guard let index = layers.firstIndex(where: { $0.id == id }),
              layers.indices.contains(index + direction) else { return }
        mutateLayers { layers.swapAt(index, index + direction) }
    }

    func duplicateSelectedLayer() {
        guard let selectedLayer else { return }
        var copy = selectedLayer
        copy.id = UUID()
        copy.name += " kopya"
        copy.position.x += 24
        copy.position.y += 24
        mutateLayers { layers.append(copy); selectedLayerID = copy.id }
    }

    func deleteSelectedLayer() {
        guard let id = selectedLayerID else { return }
        mutateLayers { layers.removeAll { $0.id == id }; selectedLayerID = layers.last?.id }
    }

    func updateSelectedText(_ text: String) {
        guard let index = layers.firstIndex(where: { $0.id == selectedLayerID }),
              layers[index].kind == .text, layers[index].text != text else { return }
        mutateLayers { layers[index].text = text }
    }

    func saveProjectPanel() {
        guard hasImage else { return }
        let panel = NSSavePanel()
        panel.title = "Katmanlı projeyi kaydet"
        panel.nameFieldStringValue = fileName + ".luma"
        panel.allowedContentTypes = [UTType(exportedAs: "studio.luma.document", conformingTo: .data)]
        if panel.runModal() == .OK, let url = panel.url { saveProject(to: url) }
    }

    private func saveProject(to url: URL) {
        guard let source, let basePNG = pngData(source) else {
            errorMessage = "Proje kaydedilemedi."
            return
        }
        let archives = layers.map { layer in
            LayerArchive(id: layer.id, name: layer.name, kind: layer.kind,
                         imagePNG: layer.image.flatMap(pngData),
                         position: layer.position, size: layer.size, opacity: layer.opacity,
                         isVisible: layer.isVisible, text: layer.text, fontSize: layer.fontSize,
                         fill: layer.fill, strokes: layer.strokes)
        }
        do {
            let data = try JSONEncoder().encode(ProjectArchive(basePNG: basePNG, layers: archives, state: state))
            try data.write(to: url, options: .atomic)
            isDirty = false
        } catch { errorMessage = "Proje kaydedilemedi: \(error.localizedDescription)" }
    }

    private func openProject(_ url: URL) {
        do {
            let archive = try JSONDecoder().decode(ProjectArchive.self, from: Data(contentsOf: url))
            guard let base = CIImage(data: archive.basePNG) else { throw CocoaError(.fileReadCorruptFile) }
            source = base
            fileName = url.deletingPathExtension().lastPathComponent
            pixelSize = base.extent.size
            layers = archive.layers.map { item in
                var layer = CanvasLayer(id: item.id, name: item.name, kind: item.kind,
                                        image: item.imagePNG.flatMap(CIImage.init(data:)),
                                        position: item.position, size: item.size)
                layer.opacity = item.opacity
                layer.isVisible = item.isVisible
                layer.text = item.text
                layer.fontSize = item.fontSize
                layer.fill = item.fill
                layer.strokes = item.strokes
                return layer
            }
            state = archive.state
            selectedLayerID = layers.last?.id
            undoStack = []
            redoStack = []
            zoom = 1
            showOriginal = false
            isDirty = false
            renderPreview()
        } catch { errorMessage = "Katmanlı proje açılamadı: \(error.localizedDescription)" }
    }

    private func pngData(_ image: CIImage) -> Data? {
        guard let cgImage = context.createCGImage(image, from: image.extent.integral) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    func exportPanel() {
        guard hasImage else { return }
        let panel = NSSavePanel()
        panel.title = "Görseli dışa aktar"
        panel.nameFieldStringValue = fileName + "-duzenlenmis.\(selectedFormat.type.preferredFilenameExtension ?? "png")"
        panel.allowedContentTypes = [selectedFormat.type]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { export(to: url, format: selectedFormat) }
    }

    func export(to url: URL, format: ExportFormat) {
        guard let image = processedImage(preview: false),
              let cgImage = context.createCGImage(image, from: image.extent.integral),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil)
        else {
            errorMessage = "Görsel dışa aktarılamadı."
            return
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: exportQuality]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            errorMessage = "Dosya kaydedilemedi."
        }
    }

    private func renderPreview() {
        guard let image = processedImage(preview: true),
              let cgImage = context.createCGImage(image, from: image.extent.integral) else {
            preview = nil
            return
        }
        preview = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func imageForLayer(_ layer: CanvasLayer) -> CIImage? {
        if layer.kind == .image, let image = layer.image {
            let extent = image.extent
            guard extent.width > 0, extent.height > 0 else { return nil }
            return image
                .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                .transformed(by: CGAffineTransform(scaleX: layer.size.width / extent.width,
                                                   y: layer.size.height / extent.height))
                .transformed(by: CGAffineTransform(translationX: layer.position.x,
                                                   y: layer.position.y))
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: max(1, Int(pixelSize.width)),
                                            pixelsHigh: max(1, Int(pixelSize.height)),
                                            bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let rect = CGRect(origin: layer.position, size: layer.size)
        layer.fill.nsColor.setFill()
        switch layer.kind {
        case .text:
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            (layer.text as NSString).draw(in: rect, withAttributes: [
                .font: NSFont.systemFont(ofSize: layer.fontSize, weight: .bold),
                .foregroundColor: layer.fill.nsColor,
                .paragraphStyle: paragraph
            ])
        case .rectangle:
            NSBezierPath(roundedRect: rect, xRadius: min(20, rect.width * 0.1),
                         yRadius: min(20, rect.height * 0.1)).fill()
        case .ellipse:
            NSBezierPath(ovalIn: rect).fill()
        case .paint:
            for stroke in layer.strokes where !stroke.points.isEmpty {
                let path = NSBezierPath()
                path.lineWidth = stroke.width
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: stroke.points[0])
                for point in stroke.points.dropFirst() { path.line(to: point) }
                if stroke.points.count == 1 {
                    path.line(to: CGPoint(x: stroke.points[0].x + 0.01, y: stroke.points[0].y))
                }
                stroke.color.nsColor.setStroke()
                path.stroke()
            }
        case .image: break
        }
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = bitmap.cgImage else { return nil }
        return CIImage(cgImage: cgImage)
    }

    private func processedImage(preview isPreview: Bool) -> CIImage? {
        guard let source else { return nil }
        var image = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX,
                                                            y: -source.extent.minY))
        if !(showOriginal && isPreview) {
            let canvas = CGRect(origin: .zero, size: pixelSize)
            for layer in layers where layer.isVisible {
                guard var overlay = imageForLayer(layer) else { continue }
                if layer.opacity < 1 {
                    overlay = overlay.applyingFilter("CIColorMatrix", parameters: [
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: layer.opacity)
                    ])
                }
                image = overlay.applyingFilter("CISourceOverCompositing", parameters: [
                    "inputBackgroundImage": image
                ]).cropped(to: canvas)
            }
        }
        if let ratio = state.crop.ratio {
            let extent = image.extent
            let current = extent.width / extent.height
            let size = current > ratio
                ? CGSize(width: extent.height * ratio, height: extent.height)
                : CGSize(width: extent.width, height: extent.width / ratio)
            let rect = CGRect(x: extent.midX - size.width / 2,
                              y: extent.midY - size.height / 2,
                              width: size.width, height: size.height)
            image = image.cropped(to: rect)
        }
        if isPreview {
            let longest = max(image.extent.width, image.extent.height)
            if longest > 1800 { image = image.transformed(by: CGAffineTransform(scaleX: 1800 / longest, y: 1800 / longest)) }
        }
        if state.flipped {
            let extent = image.extent
            image = image.transformed(by: CGAffineTransform(translationX: extent.minX + extent.maxX, y: 0).scaledBy(x: -1, y: 1))
        }
        let orientation: [Int: Int32] = [1: 6, 2: 3, 3: 8]
        if let exif = orientation[((state.turns % 4) + 4) % 4] {
            image = image.oriented(forExifOrientation: exif)
        }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if showOriginal && isPreview { return image }

        func apply(_ name: String, _ values: [String: Any]) {
            guard let filter = CIFilter(name: name) else { return }
            filter.setValue(image, forKey: kCIInputImageKey)
            values.forEach { filter.setValue($0.value, forKey: $0.key) }
            if let output = filter.outputImage { image = output }
        }
        let v = state.value
        if v(.exposure) != 0 { apply("CIExposureAdjust", [kCIInputEVKey: v(.exposure)]) }
        if v(.brightness) != 0 || v(.contrast) != 0 || v(.saturation) != 0 {
            apply("CIColorControls", [kCIInputBrightnessKey: v(.brightness) * 0.35,
                                       kCIInputContrastKey: 1 + v(.contrast) * 0.7,
                                       kCIInputSaturationKey: 1 + v(.saturation)])
        }
        if v(.highlights) != 0 || v(.shadows) != 0 {
            apply("CIHighlightShadowAdjust", ["inputHighlightAmount": 1 - v(.highlights),
                                              "inputShadowAmount": v(.shadows)])
        }
        if v(.vibrance) != 0 { apply("CIVibrance", ["inputAmount": v(.vibrance)]) }
        if v(.warmth) != 0 {
            apply("CITemperatureAndTint", ["inputNeutral": CIVector(x: 6500, y: 0),
                                            "inputTargetNeutral": CIVector(x: 6500 - v(.warmth) * 2200, y: 0)])
        }
        if v(.sharpen) > 0 { apply("CISharpenLuminance", [kCIInputSharpnessKey: v(.sharpen) * 1.4]) }
        if v(.vignette) > 0 { apply("CIVignette", [kCIInputIntensityKey: v(.vignette) * 2,
                                                 kCIInputRadiusKey: 1.4]) }
        return image.cropped(to: image.extent.integral)
    }
}

struct Preset: Identifiable {
    let name: String
    let subtitle: String
    let symbol: String
    let values: [Adjustment: Double]
    var id: String { name }

    static let all: [Preset] = [
        Preset(name: "Özgün", subtitle: "Doğal görünüm", symbol: "circle", values: [:]),
        Preset(name: "Canlı", subtitle: "Renkleri öne çıkar", symbol: "sparkles", values: [.vibrance: 0.48, .contrast: 0.12, .saturation: 0.08]),
        Preset(name: "Sıcak", subtitle: "Altın tonlar", symbol: "sun.max", values: [.warmth: 0.42, .brightness: 0.06, .vibrance: 0.18]),
        Preset(name: "Dingin", subtitle: "Yumuşak ve serin", symbol: "cloud", values: [.warmth: -0.25, .contrast: -0.12, .highlights: 0.25]),
        Preset(name: "Dramatik", subtitle: "Güçlü kontrast", symbol: "circle.lefthalf.filled", values: [.contrast: 0.42, .shadows: 0.20, .vignette: 0.35]),
        Preset(name: "Monokrom", subtitle: "Siyah ve beyaz", symbol: "circle.dotted", values: [.saturation: -1, .contrast: 0.24, .sharpen: 0.16])
    ]
}

private enum Palette {
    private static func adaptive(_ light: (CGFloat, CGFloat, CGFloat),
                                 _ dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
    static let background = adaptive((0.90, 0.93, 0.97), (0.10, 0.13, 0.18))
    static let surface = adaptive((0.91, 0.94, 0.98), (0.15, 0.18, 0.23))
    static let ink = adaptive((0.19, 0.25, 0.34), (0.91, 0.94, 0.98))
    static let muted = adaptive((0.49, 0.55, 0.64), (0.61, 0.67, 0.75))
    static let accent = adaptive((0.35, 0.43, 0.91), (0.48, 0.57, 1.00))
    static let light = adaptive((1.00, 1.00, 1.00), (0.22, 0.27, 0.34)).opacity(0.80)
    static let dark = adaptive((0.68, 0.73, 0.82), (0.02, 0.04, 0.07)).opacity(0.80)
}

private struct SoftCard: ViewModifier {
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Palette.light, radius: 10, x: -6, y: -6)
            .shadow(color: Palette.dark, radius: 11, x: 7, y: 7)
    }
}

private extension View {
    func softCard(radius: CGFloat = 22) -> some View { modifier(SoftCard(radius: radius)) }
}

struct EditorView: View {
    @EnvironmentObject private var editor: PhotoEditor
    @AppStorage("appearance") private var appearance = "system"
    @State private var section: EditorSection = .adjust
    @State private var dropTarget = false
    @State private var activeTool: CanvasTool = .move
    @State private var pendingStroke: [CGPoint] = []
    @State private var dragOffset = CGSize.zero
    @State private var brushColor = Color(red: 0.36, green: 0.45, blue: 0.98)
    @State private var shapeColor = Color(red: 0.36, green: 0.45, blue: 0.98)
    @State private var brushSize = 24.0
    @State private var newText = "Yeni metin"
    @State private var textDraft = ""
    @State private var opacityBefore: [CanvasLayer] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                toolRail
                workspace
                inspector
            }
            footer
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .fontDesign(.default)
        .alert("Bir sorun oluştu", isPresented: Binding(get: { editor.errorMessage != nil }, set: { if !$0 { editor.errorMessage = nil } })) {
            Button("Tamam", role: .cancel) { editor.errorMessage = nil }
        } message: { Text(editor.errorMessage ?? "") }
        .sheet(isPresented: $editor.showNewCanvas) {
            NewCanvasSheet().environmentObject(editor)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in editor.open(url) } }
            }
            return true
        }
        .onChange(of: editor.selectedLayerID) { _, _ in textDraft = editor.selectedLayer?.text ?? "" }
    }

    private var header: some View {
        HStack(spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "camera.filters")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Palette.accent.gradient, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Luma Studio").font(.system(size: 17, weight: .bold))
                    Text("FOTOĞRAF ATÖLYESİ").font(.system(size: 8, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(Palette.muted)
                }
            }
            Spacer()
            if editor.hasImage {
                HStack(spacing: 5) {
                    Image(systemName: "photo")
                    Text(editor.fileName)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .frame(maxWidth: 240)
            }
            Spacer()
            HStack(spacing: 12) {
                topButton("arrow.uturn.backward", label: "Geri al") { editor.undo() }.disabled(!editor.canUndo)
                topButton("arrow.uturn.forward", label: "Yinele") { editor.redo() }.disabled(!editor.canRedo)
                topButton("gearshape", label: "Uygulama ayarları") { section = .settings }
                Rectangle().fill(Palette.dark).frame(width: 1, height: 23)
                Button { editor.showNewCanvas = true } label: {
                    Label("Yeni", systemImage: "plus.square")
                }.buttonStyle(SoftButtonStyle())
                Button { editor.openPanel() } label: {
                    Label("Aç", systemImage: "folder")
                }.buttonStyle(SoftButtonStyle())
                Button { editor.exportPanel() } label: {
                    Label("Dışa aktar", systemImage: "square.and.arrow.up")
                }.buttonStyle(AccentButtonStyle()).disabled(!editor.hasImage)
            }
        }
        .padding(.horizontal, 26)
        .frame(height: 76)
        .background(Palette.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.dark.opacity(0.25)).frame(height: 1) }
    }

    private func topButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).frame(width: 35, height: 35) }
            .buttonStyle(SoftButtonStyle()).help(label)
    }

    private var toolRail: some View {
        VStack(spacing: 19) {
            ForEach(EditorSection.allCases) { item in
                Button { section = item } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.symbol).font(.system(size: 18, weight: .medium)).frame(width: 48, height: 48)
                            .background(section == item ? Palette.accent : Palette.surface,
                                        in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(section == item ? .white : Palette.muted)
                            .shadow(color: section == item ? Palette.accent.opacity(0.26) : Palette.dark, radius: 7, x: 4, y: 5)
                        Text(item.rawValue).font(.system(size: 10, weight: .medium)).foregroundStyle(section == item ? Palette.ink : Palette.muted)
                    }
                }.buttonStyle(.plain)
            }
            Spacer()
            Image(systemName: "command").font(.system(size: 15)).foregroundStyle(Palette.muted.opacity(0.6)).padding(.bottom, 10)
        }
        .padding(.top, 28)
        .frame(width: 86)
        .background(Palette.background)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.dark.opacity(0.25)).frame(width: 1) }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(editor.hasImage ? "Çalışma alanı" : "Yaratıcılığa başlayın")
                        .font(.system(size: 22, weight: .bold))
                    Text(editor.hasImage ? "Görselini dilediğin gibi düzenle" : "Görselini aç veya buraya sürükle")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if editor.hasImage {
                    Button { editor.showOriginal.toggle(); editor.refresh() } label: {
                        Label("Özgünü gör", systemImage: "eye")
                    }
                    .buttonStyle(SoftButtonStyle())
                    Text("\(Int(editor.zoom * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 42)
                }
            }
            .padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 22)
            if editor.hasImage {
                HStack(spacing: 8) {
                    canvasToolButton(.move)
                    canvasToolButton(.brush)
                    Spacer()
                    Text(activeTool == .move ? "Seçili katmanı sürükle" : "Tuval üzerinde çiz")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 32).padding(.bottom, 16)
            }
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 30).fill(Palette.background)
                        .shadow(color: Palette.dark.opacity(0.8), radius: 14, x: 8, y: 8)
                        .shadow(color: Palette.light.opacity(0.8), radius: 14, x: -8, y: -8)
                    if let preview = editor.preview {
                        ScrollView([.horizontal, .vertical]) {
                            let fit = min((geometry.size.width - 90) / preview.size.width,
                                          (geometry.size.height - 90) / preview.size.height) * editor.zoom
                            canvasView(preview: preview,
                                       width: preview.size.width * fit,
                                       height: preview.size.height * fit)
                                .shadow(color: Palette.ink.opacity(0.22), radius: 20, x: 0, y: 12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .frame(minWidth: geometry.size.width - 48, minHeight: geometry.size.height - 48)
                        }
                        .scrollIndicators(.hidden)
                        .padding(24)
                    } else {
                        VStack(spacing: 17) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 42, weight: .ultraLight))
                                .foregroundStyle(Palette.accent)
                                .frame(width: 94, height: 94)
                                .softCard(radius: 28)
                            Text("Görselini buraya bırak")
                                .font(.system(size: 22, weight: .semibold))
                            Text("Fotoğraflarını düzenlemek için bir dosya seç.\nDesteklenen biçimler macOS görsel kod çözücülerine bağlıdır.")
                                .multilineTextAlignment(.center)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                                .lineSpacing(4)
                            HStack(spacing: 12) {
                                Button { editor.showNewCanvas = true } label: {
                                    Label("Yeni tuval", systemImage: "plus.square")
                                }.buttonStyle(SoftButtonStyle())
                                Button { editor.openPanel() } label: {
                                    Label("Görsel seç", systemImage: "photo")
                                }.buttonStyle(AccentButtonStyle())
                            }.padding(.top, 5)
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 30).stroke(dropTarget ? Palette.accent : Palette.light.opacity(0.55), lineWidth: dropTarget ? 3 : 1)
                }
            }
            .padding(.horizontal, 30).padding(.bottom, 25)
            if editor.hasImage {
                HStack(spacing: 12) {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: $editor.zoom, in: 0.5...2, step: 0.1).tint(Palette.accent).frame(width: 140)
                    Image(systemName: "plus.magnifyingglass")
                    Button("Sığdır") { editor.zoom = 1 }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 13)).foregroundStyle(Palette.muted)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func canvasToolButton(_ tool: CanvasTool) -> some View {
        Button { activeTool = tool; section = .layers; editor.showOriginal = false; editor.refresh() } label: {
            Label(tool.title, systemImage: tool.symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 13).frame(height: 32)
                .background(activeTool == tool ? Palette.accent : Palette.surface,
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(activeTool == tool ? .white : Palette.ink)
        }.buttonStyle(.plain)
    }

    private func canvasView(preview: NSImage, width: CGFloat, height: CGFloat) -> some View {
        let displaySize = CGSize(width: width, height: height)
        return ZStack(alignment: .topLeading) {
            Image(nsImage: preview).resizable().frame(width: width, height: height)
            if let layer = editor.selectedLayer, layer.kind != .paint,
               editor.state.crop == .original, editor.state.turns % 4 == 0,
               activeTool == .move {
                Rectangle()
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .frame(width: layer.size.width / editor.pixelSize.width * width,
                           height: layer.size.height / editor.pixelSize.height * height)
                    .position(x: (layer.position.x + layer.size.width / 2) / editor.pixelSize.width * width + dragOffset.width,
                              y: (editor.pixelSize.height - layer.position.y - layer.size.height / 2) / editor.pixelSize.height * height + dragOffset.height)
                    .allowsHitTesting(false)
            }
            if pendingStroke.count > 1 {
                Path { path in
                    path.move(to: pendingStroke[0])
                    for point in pendingStroke.dropFirst() { path.addLine(to: point) }
                }
                .stroke(brushColor, style: StrokeStyle(lineWidth: brushSize * width / editor.displayedCanvasSize.width,
                                                       lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if activeTool == .move { dragOffset = value.translation }
                else if value.location.x >= 0 && value.location.x <= width &&
                        value.location.y >= 0 && value.location.y <= height {
                    pendingStroke.append(value.location)
                }
            }
            .onEnded { value in
                if activeTool == .move {
                    if value.translation != .zero {
                        editor.moveSelected(screenTranslation: value.translation, displaySize: displaySize)
                    }
                    dragOffset = .zero
                } else {
                    let points = pendingStroke.map { editor.canvasPoint($0, in: displaySize) }
                    editor.addStroke(points: points, width: brushSize, color: brushColor)
                    pendingStroke = []
                }
            })
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(section.rawValue).font(.system(size: 20, weight: .bold))
                        Text(section.subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Image(systemName: section.symbol)
                        .foregroundStyle(Palette.accent)
                        .frame(width: 38, height: 38)
                        .softCard(radius: 12)
                }
                .padding(.bottom, 3)
                if section == .settings {
                    settingsTools
                } else if !editor.hasImage {
                    Text("Düzenleme araçları bir görsel açtıktan sonra kullanılabilir.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading).softCard(radius: 18)
                } else {
                    switch section {
                    case .adjust: adjustments
                    case .presets: presets
                    case .crop: cropTools
                    case .export: exportTools
                    case .layers: layerTools
                    case .settings: settingsTools
                    }
                }
            }
            .padding(25)
        }
        .frame(width: 310)
        .background(Palette.background)
        .overlay(alignment: .leading) { Rectangle().fill(Palette.dark.opacity(0.25)).frame(width: 1) }
    }

    private var adjustments: some View {
        VStack(alignment: .leading, spacing: 20) {
            inspectorHeading("IŞIK VE RENK", trailing: "10 AYAR")
            ForEach(Adjustment.allCases) { adjustment in
                VStack(spacing: 8) {
                    HStack {
                        Label(adjustment.rawValue, systemImage: adjustment.symbol)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(String(format: "%+.0f", editor.state.value(adjustment) * 100))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.muted)
                    }
                    Slider(value: Binding(get: { editor.state.value(adjustment) },
                                          set: { editor.set(adjustment, value: $0) }),
                           in: adjustment.range, onEditingChanged: { active in
                        if active { editor.beginInteraction() } else { editor.endInteraction() }
                    })
                    .tint(Palette.accent)
                }
            }
            Button { editor.reset() } label: { Label("Tüm ayarları sıfırla", systemImage: "arrow.counterclockwise") }
                .buttonStyle(SoftButtonStyle()).frame(maxWidth: .infinity)
        }
        .padding(19).softCard(radius: 20)
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 15) {
            inspectorHeading("HAZIR GÖRÜNÜMLER", trailing: "6 STİL")
            ForEach(Preset.all) { preset in
                Button { editor.applyPreset(preset) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: preset.symbol)
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 42, height: 42)
                            .background(Palette.background, in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.name).font(.system(size: 13, weight: .semibold))
                            Text(preset.subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.muted)
                    }
                    .padding(10).frame(maxWidth: .infinity)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
            }
        }.padding(16).softCard(radius: 20)
    }

    private var cropTools: some View {
        VStack(alignment: .leading, spacing: 23) {
            VStack(alignment: .leading, spacing: 15) {
                inspectorHeading("EN BOY ORANI")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(CropRatio.allCases) { ratio in
                        Button(ratio.rawValue) { editor.change { $0.crop = ratio } }
                            .buttonStyle(RatioButtonStyle(selected: editor.state.crop == ratio))
                    }
                }
                Text("Kırpma, görselin merkezinden uygulanır.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.padding(18).softCard(radius: 20)
            VStack(alignment: .leading, spacing: 15) {
                inspectorHeading("DÖNDÜR VE YANSIT")
                HStack(spacing: 10) {
                    Button { editor.change { $0.turns = ($0.turns + 3) % 4 } } label: {
                        Label("Sola", systemImage: "rotate.left")
                    }.buttonStyle(SoftButtonStyle())
                    Button { editor.change { $0.turns = ($0.turns + 1) % 4 } } label: {
                        Label("Sağa", systemImage: "rotate.right")
                    }.buttonStyle(SoftButtonStyle())
                }
                Button { editor.change { $0.flipped.toggle() } } label: {
                    Label("Yatay yansıt", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }.buttonStyle(SoftButtonStyle())
            }.padding(18).softCard(radius: 20)
        }
    }

    private var exportTools: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                inspectorHeading("DOSYA BİLGİSİ")
                infoRow("Dosya", editor.fileName)
                infoRow("Boyut", editor.dimensions)
                infoRow("Kırpma", editor.state.crop.rawValue)
            }.padding(18).softCard(radius: 20)
            VStack(alignment: .leading, spacing: 15) {
                inspectorHeading("BİÇİM")
                Picker("Biçim", selection: $editor.selectedFormat) {
                    ForEach(ExportFormat.supported) { format in Text(format.name).tag(format) }
                }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
                Text("Listede macOS’un bu bilgisayarda yazabildiği biçimler yer alır.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Button { editor.exportPanel() } label: {
                    Label("Dışa aktar", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(AccentButtonStyle())
            }.padding(18).softCard(radius: 20)
        }
    }

    private var layerTools: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                inspectorHeading("KATMAN EKLE")
                Button { editor.addImageLayerPanel() } label: {
                    Label("Görsel katmanı", systemImage: "photo.badge.plus")
                }.buttonStyle(SoftButtonStyle())
                HStack(spacing: 7) {
                    TextField("Metin", text: $newText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    Button { editor.addTextLayer(newText) } label: {
                        Image(systemName: "plus").frame(width: 23, height: 25)
                    }.buttonStyle(AccentButtonStyle())
                        .help("Metin katmanı ekle")
                }
                HStack(spacing: 8) {
                    Button { editor.addShapeLayer(.rectangle, color: shapeColor) } label: {
                        Label("Kare", systemImage: "rectangle")
                    }.buttonStyle(SoftButtonStyle())
                    Button { editor.addShapeLayer(.ellipse, color: shapeColor) } label: {
                        Label("Elips", systemImage: "circle")
                    }.buttonStyle(SoftButtonStyle())
                    ColorPicker("Şekil rengi", selection: $shapeColor).labelsHidden()
                }
            }.padding(17).softCard(radius: 19)

            VStack(alignment: .leading, spacing: 13) {
                inspectorHeading("FIRÇA")
                HStack {
                    ColorPicker("Fırça rengi", selection: $brushColor)
                    Text("\(Int(brushSize)) px")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                }
                Slider(value: $brushSize, in: 2...100, step: 1).tint(Palette.accent)
                Text("Üstte Fırça aracını seçip tuval üzerinde çiz.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(17).softCard(radius: 19)

            VStack(alignment: .leading, spacing: 12) {
                inspectorHeading("KATMANLAR", trailing: "\(editor.layers.count + 1)")
                ForEach(editor.layers.reversed()) { layer in
                    HStack(spacing: 8) {
                        Button {
                            editor.selectedLayerID = layer.id
                            activeTool = .move
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: layer.kind.symbol)
                                    .frame(width: 21)
                                    .foregroundStyle(Palette.accent)
                                Text(layer.name).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.vertical, 9).padding(.leading, 9)
                            .background(editor.selectedLayerID == layer.id ? Palette.accent.opacity(0.20) : Palette.background,
                                        in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                        Button { editor.toggleVisibility(layer.id) } label: {
                            Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                                .font(.system(size: 12)).frame(width: 26, height: 30)
                        }.buttonStyle(.plain).help(layer.isVisible ? "Gizle" : "Göster")
                    }
                }
                HStack(spacing: 9) {
                    Image(systemName: "lock.fill").frame(width: 21)
                    Text("Arka plan")
                    Spacer()
                    Image(systemName: "eye")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(11)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))

                if let layer = editor.selectedLayer {
                    Divider().padding(.vertical, 4)
                    HStack {
                        Text("Opaklık").font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(Int(layer.opacity * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.muted)
                    }
                    Slider(value: Binding(get: { editor.selectedLayer?.opacity ?? 1 },
                                          set: { editor.setSelectedOpacity($0) }),
                           in: 0...1, onEditingChanged: { editing in
                        if editing { opacityBefore = editor.layers }
                        else if !opacityBefore.isEmpty {
                            editor.commitLayerInteraction(opacityBefore)
                            opacityBefore = []
                        }
                    }).tint(Palette.accent)
                    HStack(spacing: 8) {
                        Button { editor.moveLayer(layer.id, direction: 1) } label: { Image(systemName: "arrow.up") }
                            .help("Öne getir")
                        Button { editor.moveLayer(layer.id, direction: -1) } label: { Image(systemName: "arrow.down") }
                            .help("Arkaya gönder")
                        Button { editor.duplicateSelectedLayer() } label: { Image(systemName: "plus.square.on.square") }
                            .help("Çoğalt")
                        Button { editor.deleteSelectedLayer() } label: { Image(systemName: "trash") }
                            .help("Sil")
                    }.buttonStyle(SoftButtonStyle())
                    if layer.kind == .text {
                        TextField("Metni düzenle", text: $textDraft)
                            .textFieldStyle(.roundedBorder)
                        Button("Metni uygula") { editor.updateSelectedText(textDraft) }
                            .buttonStyle(SoftButtonStyle())
                    }
                }
            }.padding(17).softCard(radius: 19)

            Button { editor.saveProjectPanel() } label: {
                Label("Katmanlı projeyi kaydet", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(AccentButtonStyle())
        }
    }

    private var settingsTools: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                inspectorHeading("GÖRÜNÜM")
                HStack(spacing: 7) {
                    ForEach(ThemeChoice.allCases) { choice in
                        Button(choice.title) { appearance = choice.rawValue }
                            .buttonStyle(RatioButtonStyle(selected: appearance == choice.rawValue))
                    }
                }
                Text("Sistem seçeneği, Mac’in görünüm ayarını izler.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(18).softCard(radius: 20)

            VStack(alignment: .leading, spacing: 16) {
                inspectorHeading("VARSAYILAN DIŞA AKTARMA")
                HStack {
                    Text("Biçim").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("Biçim", selection: $editor.selectedFormat) {
                        ForEach(ExportFormat.supported) { format in
                            Text(format.name).tag(format)
                        }
                    }.labelsHidden().pickerStyle(.menu)
                }
                VStack(spacing: 7) {
                    HStack {
                        Text("Kayıplı kalite").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(Int(editor.exportQuality * 100))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.muted)
                    }
                    Slider(value: $editor.exportQuality, in: 0.5...1, step: 0.01)
                        .tint(Palette.accent)
                }
                Text("Kalite ayarı JPEG, HEIC ve AVIF gibi kayıplı biçimlerde uygulanır.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(18).softCard(radius: 20)

            VStack(alignment: .leading, spacing: 13) {
                inspectorHeading("UYGULAMA")
                infoRow("Sürüm", "1.1")
                infoRow("Yazı tipi", "San Francisco")
                infoRow("Aç", "⌘ O")
                infoRow("Dışa aktar", "⇧ ⌘ S")
            }.padding(18).softCard(radius: 20)
        }
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).foregroundStyle(Palette.muted)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).lineLimit(2)
        }.font(.system(size: 11))
    }

    private func inspectorHeading(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(1.2)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 9, weight: .bold)).tracking(0.5).foregroundStyle(Palette.muted) }
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 7) {
                Circle().fill(Palette.accent).frame(width: 6, height: 6)
                Text(editor.hasImage ? "Düzenlemeye hazır" : "Bir görsel açarak başla")
            }
            Spacer()
            Text(editor.dimensions)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, 27)
        .frame(height: 36)
        .overlay(alignment: .top) { Rectangle().fill(Palette.dark.opacity(0.25)).frame(height: 1) }
    }
}

private struct NewCanvasSheet: View {
    @EnvironmentObject private var editor: PhotoEditor
    @State private var width = "1920"
    @State private var height = "1080"
    @State private var background = Color.white

    private var valid: Bool {
        guard let w = Int(width), let h = Int(height) else { return false }
        return w >= 64 && h >= 64 && w <= 10000 && h <= 10000 && w * h <= 60_000_000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 50, height: 50).softCard(radius: 15)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Yeni tuval").font(.system(size: 22, weight: .bold))
                    Text("Boş bir katmanlı çalışma başlat")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
            VStack(spacing: 14) {
                HStack {
                    Text("Genişlik")
                    Spacer()
                    TextField("1920", text: $width)
                        .frame(width: 95).textFieldStyle(.roundedBorder)
                    Text("px").foregroundStyle(Palette.muted)
                }
                HStack {
                    Text("Yükseklik")
                    Spacer()
                    TextField("1080", text: $height)
                        .frame(width: 95).textFieldStyle(.roundedBorder)
                    Text("px").foregroundStyle(Palette.muted)
                }
                ColorPicker("Arka plan rengi", selection: $background)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(20).softCard(radius: 20)
            HStack {
                Text("64–10.000 px • En fazla 60 MP")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer()
                Button("İptal") { editor.showNewCanvas = false }.buttonStyle(SoftButtonStyle())
                Button("Oluştur") {
                    if let w = Int(width), let h = Int(height) {
                        editor.newCanvas(width: w, height: h, background: background)
                    }
                }.buttonStyle(AccentButtonStyle()).disabled(!valid)
            }
        }
        .padding(28)
        .frame(width: 440)
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
    }
}

private enum CanvasTool {
    case move, brush
    var title: String { self == .move ? "Taşı" : "Fırça" }
    var symbol: String { self == .move ? "arrow.up.left.and.arrow.down.right" : "paintbrush.pointed" }
}

private enum EditorSection: String, CaseIterable, Identifiable {
    case adjust = "Düzenle"
    case layers = "Katmanlar"
    case presets = "Stiller"
    case crop = "Kırp"
    case export = "Çıktı"
    case settings = "Ayarlar"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .adjust: "slider.horizontal.3"
        case .layers: "square.3.layers.3d"
        case .presets: "square.stack.3d.up"
        case .crop: "crop.rotate"
        case .export: "square.and.arrow.up"
        case .settings: "gearshape"
        }
    }
    var subtitle: String {
        switch self {
        case .adjust: "Işık, renk ve detay"
        case .layers: "Katmanlı çalışma ve araçlar"
        case .presets: "Tek dokunuşla yeni bir his"
        case .crop: "Kadrajını yeniden oluştur"
        case .export: "Görselini paylaşmaya hazırla"
        case .settings: "Görünüm ve dışa aktarma tercihleri"
        }
    }
}

private struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14).frame(minHeight: 35)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 11))
            .shadow(color: Palette.light.opacity(configuration.isPressed ? 0.2 : 0.9), radius: 5, x: -3, y: -3)
            .shadow(color: Palette.dark.opacity(configuration.isPressed ? 0.25 : 0.8), radius: 6, x: 4, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white)
            .padding(.horizontal, 17).frame(minHeight: 37)
            .background(Palette.accent.gradient, in: RoundedRectangle(cornerRadius: 11))
            .shadow(color: Palette.accent.opacity(0.28), radius: 9, x: 3, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct RatioButtonStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(selected ? .white : Palette.ink)
            .frame(maxWidth: .infinity).frame(height: 37)
            .background(selected ? Palette.accent : Palette.background,
                        in: RoundedRectangle(cornerRadius: 10))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private extension PhotoEditor {
    func refresh() { renderPreview() }
}
