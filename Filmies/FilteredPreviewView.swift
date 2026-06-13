//
//  FilteredPreviewView.swift
//  Filmies
//
//  Renders a stream of already-filtered CIImages to the screen via a
//  Metal-backed CAMetalLayer, wrapped for SwiftUI. This is what makes the
//  "live filtered preview" real: rather than showing the camera's standard
//  AVCaptureVideoPreviewLayer (raw feed) and filtering only on capture, every
//  displayed frame has already passed through FilmFilterPipeline — what you
//  see in the viewfinder is exactly what gets baked into the photo.
//

import SwiftUI
import MetalKit
import CoreImage

struct FilteredPreviewView: UIViewRepresentable {
    var image: CIImage?

    func makeUIView(context: Context) -> MetalPreviewUIView {
        MetalPreviewUIView()
    }

    func updateUIView(_ uiView: MetalPreviewUIView, context: Context) {
        uiView.draw(ciImage: image)
    }
}

/// A minimal Metal-backed view that draws a CIImage scaled to fill, using
/// CoreImage's Metal-accelerated renderer. Avoids MTKView's delegate/draw-loop
/// ceremony since we only need to draw on demand (each new camera frame).
final class MetalPreviewUIView: UIView {

    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    private let device = MTLCreateSystemDefaultDevice()
    private lazy var commandQueue = device?.makeCommandQueue()
    private lazy var context: CIContext? = {
        guard let device else { return nil }
        return CIContext(mtlDevice: device)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.contentsScale = UIScreen.main.scale
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = UIScreen.main.scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    func draw(ciImage: CIImage?) {
        guard let ciImage,
              let context,
              let commandQueue,
              let drawable = metalLayer.nextDrawable() else { return }

        let drawableSize = metalLayer.drawableSize
        guard drawableSize.width > 0, drawableSize.height > 0 else { return }

        // Scale the image to "aspect fit" the drawable, centered — so the
        // selected aspect-ratio crop is shown in full with letterboxing
        // (essential for wide formats like XPan, which a fill would clip).
        // The black layer background shows through the bars.
        let imageExtent = ciImage.extent
        let scaleX = drawableSize.width / imageExtent.width
        let scaleY = drawableSize.height / imageExtent.height
        let scale = min(scaleX, scaleY)

        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaled.extent
        let dx = (drawableSize.width - scaledExtent.width) / 2 - scaledExtent.minX
        let dy = (drawableSize.height - scaledExtent.height) / 2 - scaledExtent.minY
        let positioned = scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))

        let destRect = CGRect(origin: .zero, size: drawableSize)

        // Composite the (letterboxed) frame over solid black. Metal drawables
        // are recycled from a pool, so the area outside the fitted image would
        // otherwise retain a stale previous frame — making the letterbox bars
        // look "frozen" on the last image. Painting black across the full
        // drawable each frame guarantees clean bars.
        let black = CIImage(color: CIColor.black).cropped(to: destRect)
        let composited = positioned.composited(over: black)

        guard let buffer = commandQueue.makeCommandBuffer() else { return }

        context.render(
            composited,
            to: drawable.texture,
            commandBuffer: buffer,
            bounds: destRect,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        buffer.present(drawable)
        buffer.commit()
    }
}
