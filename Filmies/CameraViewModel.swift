//
//  CameraViewModel.swift
//  Filmies
//
//  Lightweight MVVM view model — owns user-facing camera state and keeps the
//  CameraService's live look configuration in sync. Mirrors the shape of
//  camera.jsx's useState calls (index/exposure/grain*/frames/etc.) translated
//  into @Observable properties, per the agreed architecture.
//

import SwiftUI
import Observation
import SwiftData

@MainActor
@Observable
final class CameraViewModel {

    let camera = CameraService()

    // ── Persisted "remember last time" state ──────────────────────────────
    // Recipe, exposure, and grain settings are all remembered across launches
    // via UserDefaults/@AppStorage — simple, durable scalar prefs, no need
    // for SwiftData here. Reopening Filmies picks up exactly where you left
    // off, like setting down and picking up a real camera mid-roll.
    @ObservationIgnored @AppStorage("filmies.recipeIndex") private var storedRecipeIndex: Int = 1
    @ObservationIgnored @AppStorage("filmies.exposure") private var storedExposure: Double = 0
    @ObservationIgnored @AppStorage("filmies.grainStrength") private var storedGrainStrength: String = GrainStrength.off.rawValue
    @ObservationIgnored @AppStorage("filmies.grainSize") private var storedGrainSize: String = GrainSize.medium.rawValue
    @ObservationIgnored @AppStorage("filmies.aspectRatio") private var storedAspectRatio: String = AspectRatio.fourThree.rawValue
    @ObservationIgnored @AppStorage("filmies.lens") private var storedLens: String = CameraLens.wide.rawValue
    @ObservationIgnored @AppStorage("filmies.isFrontCamera") private var storedIsFrontCamera: Bool = false

    // ── Selection & adjustment state (mirrors camera.jsx's useState) ──────
    var recipeIndex: Int {
        didSet {
            storedRecipeIndex = recipeIndex
            syncLookConfiguration()
        }
    }
    var exposure: Double {
        didSet {
            storedExposure = exposure
            syncLookConfiguration()
        }
    }
    var grainStrength: GrainStrength {
        didSet {
            storedGrainStrength = grainStrength.rawValue
            syncLookConfiguration()
        }
    }
    var grainSize: GrainSize {
        didSet {
            storedGrainSize = grainSize.rawValue
            syncLookConfiguration()
        }
    }
    var aspectRatio: AspectRatio {
        didSet {
            storedAspectRatio = aspectRatio.rawValue
            camera.aspectRatio = aspectRatio
        }
    }
    var lens: CameraLens {
        didSet {
            storedLens = lens.rawValue
            camera.setLens(lens)
        }
    }
    var adjustOpen: Bool = false
    var flashOn: Bool = false
    var isFrontCamera: Bool {
        didSet { storedIsFrontCamera = isFrontCamera }
    }

    /// Whether the device's back camera offers a 0.5× ultra-wide lens (so the
    /// lens pill should be shown). Front camera has no ultra-wide.
    var supportsUltraWide: Bool { CameraLens.ultraWide.isAvailableOnBack }

    enum GrainStrength: String, CaseIterable, Identifiable {
        case off = "Off", low = "Low", high = "High"
        var id: String { rawValue }
        /// Multiplier applied to the recipe's native grain weight — Low/High
        /// values ported directly from the prototype's GRAIN_STRENGTH map;
        /// "Off" is a true zero override (no grain regardless of recipe).
        var multiplier: Double {
            switch self {
            case .off:  return 0
            case .low:  return 0.55
            case .high: return 1.3
            }
        }
    }

    enum GrainSize: String, CaseIterable, Identifiable {
        case small = "Small", medium = "Medium", large = "Large"
        var id: String { rawValue }
        /// On-screen grain tile size in points — ported from GRAIN_SIZE_PX.
        var pixelSize: CGFloat {
            switch self {
            case .small: return 110
            case .medium: return 175
            case .large: return 260
            }
        }
    }

    var recipes: [FilmRecipe] { FilmLibrary.recipes }
    var currentRecipe: FilmRecipe { recipes[recipeIndex] }

    /// Effective grain opacity for the current recipe + user settings,
    /// capped exactly like the prototype's `Math.min(0.9, recipe.grain * grainMul)`.
    var effectiveGrain: Double {
        min(0.9, currentRecipe.grain * grainStrength.multiplier)
    }

    var capturedCount: Int { camera.capturedCount }
    var isSaving: Bool { camera.isSaving }
    var isAuthorized: Bool { camera.isAuthorized }
    var lastError: String? { camera.lastError }
    var previewImage: CIImage? { camera.previewImage }

    init() {
        // Restore from last time — falls back to the prototype's defaults
        // (Portra 400, neutral exposure, grain off) on first-ever launch.
        let defaults = UserDefaults.standard
        let restoredIndex = defaults.object(forKey: "filmies.recipeIndex") as? Int ?? 1
        recipeIndex = FilmLibrary.recipes.indices.contains(restoredIndex) ? restoredIndex : 1
        exposure = defaults.object(forKey: "filmies.exposure") as? Double ?? 0
        grainStrength = GrainStrength(rawValue: defaults.string(forKey: "filmies.grainStrength") ?? "") ?? .off
        grainSize = GrainSize(rawValue: defaults.string(forKey: "filmies.grainSize") ?? "") ?? .medium
        aspectRatio = AspectRatio(rawValue: defaults.string(forKey: "filmies.aspectRatio") ?? "") ?? .fourThree
        lens = CameraLens(rawValue: defaults.string(forKey: "filmies.lens") ?? "") ?? .wide
        // Default to the back 1× camera on first launch; otherwise restore the
        // camera the user last used.
        isFrontCamera = defaults.object(forKey: "filmies.isFrontCamera") as? Bool ?? false

        camera.aspectRatio = aspectRatio
        syncLookConfiguration()
    }

    // MARK: - Actions

    func start() async {
        // Tell the service which camera + lens to bring up BEFORE the session
        // configures, so we open directly on the remembered camera (default:
        // back 1×) rather than starting on the front and flipping.
        camera.configureStartupState(isFront: isFrontCamera, lens: lens)
        await camera.requestAccessAndStart()
        syncLookConfiguration()
    }

    /// Hands the SwiftUI environment's model context down to the camera
    /// service so it can record a `FilmieShot` for each capture.
    func attachModelContext(_ context: ModelContext) {
        camera.modelContext = context
    }

    func stop() {
        camera.stopRunning()
    }

    func selectRecipe(_ index: Int) {
        guard recipes.indices.contains(index) else { return }
        recipeIndex = index
    }

    func capture() {
        camera.capturePhoto()
    }

    func flipCamera() {
        isFrontCamera.toggle()
        camera.flipCamera()
    }

    func toggleAdjust() {
        adjustOpen.toggle()
    }

    // MARK: - Sync to camera service

    private func syncLookConfiguration() {
        camera.lookConfiguration = CameraService.LookConfiguration(
            recipe: currentRecipe,
            exposure: exposure,
            grainAmount: effectiveGrain,
            grainTileSize: grainSize.pixelSize,
            mirrored: isFrontCamera
        )
    }
}
