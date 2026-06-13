//
//  CaptureFormat.swift
//  Filmies
//
//  Framing controls: the aspect ratio the viewfinder is cropped to, and which
//  physical back-camera lens is active. Both are independent and both persist
//  across launches (see CameraViewModel).
//

import CoreImage
import AVFoundation

/// The aspect ratio the captured frame is cropped to. Ratios are expressed as
/// width ÷ height in the portrait viewfinder:
///   • full   — no crop (the sensor's native frame)
///   • square — 1:1
///   • 4:3    — classic photo, portrait/tall (3:4)
///   • 16:9   — portrait/tall (9:16)
///   • xpan   — Hasselblad XPan 65:24, oriented vertically (a tall panoramic strip)
enum AspectRatio: String, CaseIterable, Identifiable {
    case full, square, fourThree, sixteenNine, xpan

    var id: String { rawValue }

    /// Short label shown on the selector chip.
    var label: String {
        switch self {
        case .full:        return "Full"
        case .square:      return "1:1"
        case .fourThree:   return "4:3"
        case .sixteenNine: return "16:9"
        case .xpan:        return "XPan"
        }
    }

    /// Target width ÷ height in the portrait viewfinder. `nil` means "no crop".
    var ratio: CGFloat? {
        switch self {
        case .full:        return nil
        case .square:      return 1.0
        case .fourThree:   return 3.0 / 4.0    // tall
        case .sixteenNine: return 9.0 / 16.0   // tall
        case .xpan:        return 24.0 / 65.0  // tall vertical panoramic
        }
    }

    /// Returns `image` cropped (centered) to this ratio. `.full` passes through.
    func crop(_ image: CIImage) -> CIImage {
        guard let r = ratio else { return image }
        let ext = image.extent
        guard ext.width > 0, ext.height > 0 else { return image }

        let sourceRatio = ext.width / ext.height
        var cropW = ext.width
        var cropH = ext.height
        if r >= sourceRatio {
            // Target is wider than the source → keep full width, trim height.
            cropH = ext.width / r
        } else {
            // Target is taller/narrower → keep full height, trim width.
            cropW = ext.height * r
        }
        let rect = CGRect(
            x: ext.midX - cropW / 2,
            y: ext.midY - cropH / 2,
            width: cropW,
            height: cropH
        )
        return image.cropped(to: rect)
    }
}

/// Which physical back-camera lens is active. The front camera always uses its
/// single wide lens; this only varies the back camera.
enum CameraLens: String, CaseIterable, Identifiable {
    case ultraWide   // 0.5×
    case wide        // 1×

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ultraWide: return "0.5×"
        case .wide:      return "1×"
        }
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide:      return .builtInWideAngleCamera
        }
    }

    /// Whether this lens exists on the current device's back camera.
    var isAvailableOnBack: Bool {
        AVCaptureDevice.default(deviceType, for: .video, position: .back) != nil
    }
}
