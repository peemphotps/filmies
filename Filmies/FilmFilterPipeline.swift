//
//  FilmFilterPipeline.swift
//  Filmies
//
//  Builds a CoreImage filter chain from a FilmRecipe and applies it to a
//  CIImage. This is the native equivalent of recipes.jsx's `buildFilter` +
//  the overlay/grain/vignette compositing that viewfinder.jsx performed with
//  CSS filters and canvas blend modes — except here it runs on the GPU via
//  CoreImage for every live camera frame.
//
//  Pipeline order (mirrors the prototype): base look → tint overlays →
//  halation → grain → vignette → exposure.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

enum FilmFilterPipeline {

    /// Applies `recipe` to `image`, returning a filtered CIImage clipped to
    /// the original image's extent.
    ///
    /// - Parameters:
    ///   - exposure: -1...1 manual exposure nudge (matches the prototype's slider).
    ///   - grainAmount: effective 0...1 grain opacity for this frame
    ///     (recipe.grain × the user's strength multiplier, capped at 0.9 — see CameraViewModel).
    ///   - grainTileSize: on-screen pixel size of one grain tile (small/medium/large).
    static func apply(
        to image: CIImage,
        recipe: FilmRecipe,
        exposure: Double,
        grainAmount: Double,
        grainTileSize: CGFloat,
        vignetteEnabled: Bool = true
    ) -> CIImage {
        let extent = image.extent
        var result = image

        // ── 1. Base look: contrast / saturation / brightness / hue / sepia / grayscale ──
        result = applyBaseLook(recipe.look, exposure: exposure, to: result)

        // ── 2. Tint overlays, painted bottom → top with their blend mode ──
        for overlay in recipe.overlays {
            result = composite(overlay: overlay, over: result, extent: extent)
        }

        // ── 3. Halation — warm/red glow, screened over the highlights ──
        if let halation = recipe.halation {
            result = applyHalation(color: halation, over: result, extent: extent)
        }

        // ── 4. Grain — monochrome noise tile, overlay-blended ──
        if grainAmount > 0.01 {
            result = applyGrain(amount: grainAmount, tileSize: grainTileSize, over: result, extent: extent)
        }

        // ── 5. Vignette ──
        if vignetteEnabled && recipe.vignette > 0.001 {
            result = applyVignette(strength: recipe.vignette, to: result, extent: extent)
        }

        return result.cropped(to: extent)
    }

    // MARK: - Base look

    private static func applyBaseLook(_ look: FilmBaseLook, exposure: Double, to image: CIImage) -> CIImage {
        var result = image

        if look.grayscale {
            let mono = CIFilter.colorMonochrome()
            mono.inputImage = result
            mono.color = CIColor(red: 0.75, green: 0.75, blue: 0.75)
            mono.intensity = 1.0
            result = mono.outputImage ?? result
        }

        if look.sepia > 0 {
            let sepia = CIFilter.sepiaTone()
            sepia.inputImage = result
            sepia.intensity = Float(look.sepia)
            result = sepia.outputImage ?? result
        }

        if look.hueRotateDegrees != 0 {
            let hue = CIFilter.hueAdjust()
            hue.inputImage = result
            hue.angle = Float(look.hueRotateDegrees * .pi / 180)
            result = hue.outputImage ?? result
        }

        // Combined contrast/saturation/brightness, plus the exposure nudge
        // (mirrors `buildFilter`'s `brightness(1 + exposure*0.3)` multiplier,
        // expressed as CoreImage's additive brightness).
        let controls = CIFilter.colorControls()
        controls.inputImage = result
        controls.contrast = Float(look.contrast)
        controls.saturation = Float(look.saturation)
        controls.brightness = Float(look.brightness + exposure * 0.3)
        result = controls.outputImage ?? result

        return result
    }

    // MARK: - Tint overlays

    private static func composite(overlay: FilmOverlay, over base: CIImage, extent: CGRect) -> CIImage {
        let tint = solidColor(overlay.color, alpha: overlay.opacity, extent: extent)
        guard let blend = CIFilter(name: overlay.blend.ciFilterName) else { return base }
        blend.setValue(tint, forKey: kCIInputImageKey)
        blend.setValue(base, forKey: kCIInputBackgroundImageKey)
        return blend.outputImage?.cropped(to: extent) ?? base
    }

    // MARK: - Halation

    private static func applyHalation(color: Color, over base: CIImage, extent: CGRect) -> CIImage {
        let center = CIVector(x: extent.midX, y: extent.midY + extent.height * 0.12)
        let glow = CIFilter.radialGradient()
        glow.center = CGPoint(x: center.x, y: center.y)
        glow.radius0 = 0
        glow.radius1 = Float(extent.width * 0.8)
        glow.color0 = ciColor(color, alpha: 0.34)
        glow.color1 = ciColor(color, alpha: 0)
        guard let glowImage = glow.outputImage?.cropped(to: extent) else { return base }

        let screen = CIFilter.screenBlendMode()
        screen.inputImage = glowImage
        screen.backgroundImage = base
        return screen.outputImage?.cropped(to: extent) ?? base
    }

    // MARK: - Grain

    private static func applyGrain(amount: Double, tileSize: CGFloat, over base: CIImage, extent: CGRect) -> CIImage {
        // Generate monochrome random noise, scale it to the requested tile
        // size, tile it across the frame, then overlay-blend at `amount`.
        let noise = CIFilter.randomGenerator()
        guard var noiseImage = noise.outputImage else { return base }

        // CIRandomGenerator is full-color static; desaturate so it reads as
        // film grain rather than color confetti (mirrors the prototype's
        // monochrome noise tile).
        let mono = CIFilter.colorControls()
        mono.inputImage = noiseImage
        mono.saturation = 0
        mono.contrast = 1.1
        noiseImage = mono.outputImage ?? noiseImage

        let tile = max(8, tileSize)
        let scale = tile / 64.0 // base noise reads at ~64px grain; scale to requested tile size
        let scaled = noiseImage
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .cropped(to: extent)

        let overlay = CIFilter.overlayBlendMode()
        overlay.inputImage = scaled
        overlay.backgroundImage = base
        guard let blended = overlay.outputImage?.cropped(to: extent) else { return base }

        // Dial the effect down to `amount` by cross-dissolving with the base.
        return dissolve(blended, with: base, fraction: amount, extent: extent)
    }

    // MARK: - Vignette

    private static func applyVignette(strength: Double, to image: CIImage, extent: CGRect) -> CIImage {
        let vignette = CIFilter.vignette()
        vignette.inputImage = image
        vignette.intensity = Float(strength * 2.2)
        vignette.radius = Float(max(extent.width, extent.height) * 0.55)
        return vignette.outputImage?.cropped(to: extent) ?? image
    }

    // MARK: - Helpers

    private static func solidColor(_ color: Color, alpha: Double, extent: CGRect) -> CIImage {
        CIImage(color: ciColor(color, alpha: alpha)).cropped(to: extent)
    }

    private static func ciColor(_ color: Color, alpha: Double) -> CIColor {
        let resolved = color.resolve(in: EnvironmentValues())
        return CIColor(red: CGFloat(resolved.red),
                       green: CGFloat(resolved.green),
                       blue: CGFloat(resolved.blue),
                       alpha: CGFloat(alpha))
    }

    /// Linear cross-dissolve between two images by `fraction` (0 = `base`, 1 = `top`).
    private static func dissolve(_ top: CIImage, with base: CIImage, fraction: Double, extent: CGRect) -> CIImage {
        let f = max(0, min(1, fraction))
        let dissolve = CIFilter.dissolveTransition()
        dissolve.inputImage = base
        dissolve.targetImage = top
        dissolve.time = Float(f)
        return dissolve.outputImage?.cropped(to: extent) ?? top
    }
}
