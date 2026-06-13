//
//  CameraService.swift
//  Filmies
//
//  Owns the AVCaptureSession, pulls live frames via AVCaptureVideoDataOutput,
//  runs each one through the FilmFilterPipeline on the GPU (CoreImage +
//  Metal), and republishes the filtered frame for the live preview. Also
//  bakes the current look into a still photo on capture and saves it to the
//  Photos library.
//
//  This is the native equivalent of the prototype's Viewfinder (live CSS
//  filter stack) + bakeCapture (canvas compositing) combined — except the
//  "live" path and the "capture" path now share the exact same CoreImage
//  pipeline, so what you see really is what you get.
//

import AVFoundation
import CoreImage
import UIKit
import Photos
import Combine
import SwiftData

@MainActor
@Observable
final class CameraService: NSObject {

    // Published to the view layer
    private(set) var previewImage: CIImage?
    private(set) var isAuthorized = false
    private(set) var isRunning = false
    private(set) var isSaving = false
    private(set) var lastError: String?
    private(set) var capturedCount = 0

    /// Set by the view layer (which has `@Environment(\.modelContext)`) so
    /// captures can be recorded into the SwiftData-backed gallery index.
    var modelContext: ModelContext?

    /// Looks/adjustments applied to every frame — the view model keeps this
    /// in sync with user selections (recipe, exposure, grain settings).
    var lookConfiguration = LookConfiguration() {
        didSet { /* read on the processing queue per-frame; no action needed here */ }
    }

    struct LookConfiguration {
        var recipe: FilmRecipe = FilmLibrary.default
        var exposure: Double = 0
        var grainAmount: Double = 0
        var grainTileSize: CGFloat = 175
        var mirrored: Bool = true
    }

    /// The aspect ratio the live preview AND captures are cropped to. Updated
    /// by the view model; read per-frame on the processing path.
    var aspectRatio: AspectRatio = .fourThree

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "filmies.camera.processing", qos: .userInteractive)
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    private var currentInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    /// Which back-camera lens to use (front always uses its wide lens).
    private var currentLens: CameraLens = .wide

    /// Derives the correct buffer-rotation angle per physical device — the
    /// Apple-recommended replacement for hand-picking a fixed angle, since
    /// front/back sensors are mounted differently and a single fixed value
    /// is wrong for one of them. Must be retained per-device.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    /// The portrait-upright buffer-rotation angle for each camera position,
    /// captured ONCE at startup while the device is in portrait. The app is
    /// locked to portrait, so we never want the angle to depend on the phone's
    /// current physical orientation — re-reading it after the user has rotated
    /// (e.g. on a lens switch) is exactly what made the preview flip 90°.
    private var lockedAngles: [AVCaptureDevice.Position: CGFloat] = [:]

    /// The most recent raw (unfiltered) frame — used to bake the still photo
    /// with the *exact* same pipeline as the live preview.
    private var latestRawFrame: CIImage?

    override init() {
        super.init()
    }

    // MARK: - Authorization & lifecycle

    /// Sets which camera + lens the session should open with, before it's
    /// configured. Must be called prior to `requestAccessAndStart()`.
    func configureStartupState(isFront: Bool, lens: CameraLens) {
        guard session.inputs.isEmpty else { return } // only meaningful pre-config
        currentPosition = isFront ? .front : .back
        currentLens = lens
        lookConfiguration.mirrored = isFront
    }

    func requestAccessAndStart() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            isAuthorized = false
        }

        guard isAuthorized else { return }
        configureSessionIfNeeded()
        startRunning()
    }

    private func configureSessionIfNeeded() {
        guard session.inputs.isEmpty else { return }

        // Capture the portrait-upright angles for both cameras now, at startup,
        // while the device is in portrait — so later lens switches / flips
        // never re-derive an angle from a rotated physical orientation.
        cachePortraitAngles()

        session.beginConfiguration()
        session.sessionPreset = .high

        attachInput(for: currentPosition)

        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        applyConnectionOrientation(for: currentPosition)

        session.commitConfiguration()
    }

    private func attachInput(for position: AVCaptureDevice.Position) {
        if let existing = currentInput {
            session.removeInput(existing)
            currentInput = nil
        }
        // Front always uses its wide lens; the back honors the selected lens
        // (0.5× ultra-wide / 1× wide), falling back to wide if ultra-wide
        // isn't present on this device.
        let desiredType: AVCaptureDevice.DeviceType = (position == .back)
            ? currentLens.deviceType
            : .builtInWideAngleCamera
        let device = AVCaptureDevice.default(desiredType, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)

        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            lastError = "Couldn't access the \(position == .front ? "front" : "back") camera."
            return
        }
        session.addInput(input)
        currentInput = input
    }

    /// Switches the back-camera lens (0.5× ⇄ 1×). No-op on the front camera or
    /// if the requested lens is already active.
    func setLens(_ lens: CameraLens) {
        guard currentLens != lens else { return }
        currentLens = lens
        guard currentPosition == .back else { return } // applied next time we're on the back camera
        session.beginConfiguration()
        attachInput(for: .back)
        applyConnectionOrientation(for: .back)
        session.commitConfiguration()
    }

    func startRunning() {
        guard !session.isRunning else { return }
        Task.detached(priority: .userInitiated) { [session] in
            session.startRunning()
        }
        isRunning = true
    }

    func stopRunning() {
        guard session.isRunning else { return }
        Task.detached(priority: .userInitiated) { [session] in
            session.stopRunning()
        }
        isRunning = false
    }

    /// Flips between front and back camera.
    func flipCamera() {
        currentPosition = (currentPosition == .front) ? .back : .front
        lookConfiguration.mirrored = (currentPosition == .front)

        session.beginConfiguration()
        attachInput(for: currentPosition)
        applyConnectionOrientation(for: currentPosition)
        session.commitConfiguration()
    }

    /// Applies the correct buffer rotation + mirroring for the given camera
    /// position. Front and back sensors are physically mounted differently,
    /// so a single hand-picked rotation angle is wrong for one of them —
    /// that mismatch was the root cause of the front camera appearing
    /// sideways/rotated and cropped (the buffer arrived essentially in
    /// landscape and got aspect-fill-cropped into the portrait preview).
    ///
    /// Rather than guess a fixed angle, we ask `AVCaptureDevice.RotationCoordinator`
    /// — Apple's iOS 17+ replacement for `AVCaptureVideoOrientation` — for the
    /// angle that makes this *specific* device's buffer appear upright for
    /// "horizon level capture" (portrait, holding the phone upright).
    ///
    /// We use the angle cached at startup (`lockedAngles`) — captured while in
    /// portrait — and never re-derive it from the phone's current orientation.
    /// The app is locked to portrait, so the buffer must stay portrait no
    /// matter how the phone is held; re-reading the live angle on a lens
    /// switch while rotated is exactly what flipped the preview 90°.
    private func applyConnectionOrientation(for position: AVCaptureDevice.Position) {
        guard let connection = videoOutput.connection(with: .video) else { return }

        let angle = lockedAngles[position] ?? fallbackAngle(for: position)
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        connection.isVideoMirrored = (position == .front)
    }

    /// Reads & caches the portrait-upright rotation angle for both cameras via
    /// `AVCaptureDevice.RotationCoordinator` (Apple's iOS 17+ replacement for
    /// `AVCaptureVideoOrientation`). Called once at startup, in portrait.
    private func cachePortraitAngles() {
        for position in [AVCaptureDevice.Position.back, .front] {
            guard lockedAngles[position] == nil,
                  let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            else { continue }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            rotationCoordinator = coordinator // retain the most recent
            lockedAngles[position] = coordinator.videoRotationAngleForHorizonLevelCapture
        }
    }

    /// If a cached angle is somehow missing, fall back to the typical iPhone
    /// portrait angle (90° back, 90° front with mirroring handled separately).
    private func fallbackAngle(for position: AVCaptureDevice.Position) -> CGFloat { 90 }

    // MARK: - Capture

    /// Bakes the current look into the latest frame at full resolution and
    /// saves the result to the Photos library.
    func capturePhoto() {
        guard let raw = latestRawFrame else { return }
        let config = lookConfiguration
        let ratio = aspectRatio
        isSaving = true

        Task.detached(priority: .userInitiated) { [context] in
            var image = raw
            if config.mirrored {
                image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                    .translatedBy(x: -image.extent.width, y: 0))
            }
            // Crop to the selected aspect ratio before baking the look so the
            // saved photo matches the framing shown in the viewfinder.
            image = ratio.crop(image)
            let filtered = FilmFilterPipeline.apply(
                to: image,
                recipe: config.recipe,
                exposure: config.exposure,
                grainAmount: config.grainAmount,
                grainTileSize: config.grainTileSize,
                // XPan is a clean panoramic crop — no vignette darkening.
                vignetteEnabled: ratio != .xpan
            )
            guard let cgImage = context.createCGImage(filtered, from: filtered.extent) else {
                await MainActor.run { self.isSaving = false; self.lastError = "Couldn't process the photo." }
                return
            }
            let uiImage = UIImage(cgImage: cgImage)
            await self.save(uiImage, recipeID: config.recipe.id)
        }
    }

    /// Saves the baked photo into the Photos library, files it into a
    /// dedicated "Filmies" album (creating the album on first use), and
    /// records a lightweight `FilmieShot` entry (asset id + recipe + date)
    /// in SwiftData so the in-app gallery can list/sort/filter without
    /// re-querying Photos metadata.
    private func save(_ image: UIImage, recipeID: String) async {
        // .readWrite (not just .addOnly) — the in-app gallery needs to read
        // photos back (fetch the "Filmies" album, load thumbnails/full images),
        // not just add new ones.
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            isSaving = false
            lastError = "Filmies needs Photos access to save your shots. Enable it in Settings."
            return
        }
        do {
            let album = try await Self.fetchOrCreateFilmiesAlbum()

            var createdIdentifier: String?
            try await PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                guard let placeholder = creationRequest.placeholderForCreatedAsset else { return }
                createdIdentifier = placeholder.localIdentifier
                if let albumRequest = PHAssetCollectionChangeRequest(for: album) {
                    albumRequest.addAssets(NSArray(array: [placeholder]))
                }
            }

            isSaving = false
            capturedCount += 1

            if let identifier = createdIdentifier {
                recordShot(assetIdentifier: identifier, recipeID: recipeID)
            }
        } catch {
            isSaving = false
            lastError = "Couldn't save the photo: \(error.localizedDescription)"
        }
    }

    /// Fetches the existing "Filmies" album, creating it if this is the
    /// first capture ever made. Album creation is its own change transaction
    /// (required by PhotoKit — you can't create a collection and reference
    /// its placeholder across separate `performChanges` calls), so we
    /// re-fetch the freshly created collection by its placeholder identifier.
    private static func fetchOrCreateFilmiesAlbum() async throws -> PHAssetCollection {
        let title = "Filmies"
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", title)
        if let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject {
            return existing
        }

        var placeholderIdentifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            placeholderIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let identifier = placeholderIdentifier,
              let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject
        else {
            throw NSError(domain: "Filmies", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn't create the Filmies album."])
        }
        return created
    }

    /// Inserts a `FilmieShot` record for this capture so the in-app gallery
    /// can list it (sorted/filtered) without touching the Photos library.
    private func recordShot(assetIdentifier: String, recipeID: String) {
        guard let modelContext else { return }
        let shot = FilmieShot(assetIdentifier: assetIdentifier, recipeID: recipeID, capturedAt: .now)
        modelContext.insert(shot)
        try? modelContext.save()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let raw = CIImage(cvPixelBuffer: pixelBuffer)

        Task { @MainActor in
            self.latestRawFrame = raw
            let config = self.lookConfiguration
            // Crop to the selected aspect ratio so the live preview frames
            // exactly what will be captured (WYSIWYG).
            let cropped = self.aspectRatio.crop(raw)
            let filtered = FilmFilterPipeline.apply(
                to: cropped,
                recipe: config.recipe,
                exposure: config.exposure,
                grainAmount: config.grainAmount,
                grainTileSize: config.grainTileSize,
                // XPan is a clean panoramic crop — no vignette darkening.
                vignetteEnabled: self.aspectRatio != .xpan
            )
            self.previewImage = filtered
        }
    }
}
