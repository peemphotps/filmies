//
//  FilmRecipe.swift
//  Filmies
//
//  Film stock / recipe definitions — ported from the design prototype's
//  recipes.jsx. Each recipe describes a CoreImage-friendly "look": base
//  color adjustments (contrast/saturation/brightness/hue/sepia), a stack of
//  tint overlays painted with a blend mode, plus grain and vignette weights.
//
//  v1 ships three recipes that exercise the three "shapes" every film stock
//  in the original design is built from: a near-passthrough (Standard), a
//  full color-tint recipe (Portra 400), and a black & white conversion
//  (HP5 Plus). The remaining ten from the design can be ported the same way
//  once this pipeline is validated on-device.
//

import SwiftUI
import CoreImage

/// How a tint overlay should be composited over the base image.
/// Mirrors the CSS `mix-blend-mode` values used in the prototype, mapped to
/// the closest CoreImage compositing filter.
enum BlendMode: String {
    case softLight = "soft-light"
    case multiply
    case screen
    case lighten
    case normal

    /// CoreImage filter name that approximates this blend.
    var ciFilterName: String {
        switch self {
        case .softLight: return "CISoftLightBlendMode"
        case .multiply:  return "CIMultiplyBlendMode"
        case .screen:    return "CIScreenBlendMode"
        case .lighten:   return "CILightenBlendMode"
        case .normal:    return "CISourceOverCompositing"
        }
    }
}

/// A single tint layer painted over the base image at a given opacity.
struct FilmOverlay {
    let color: Color
    let blend: BlendMode
    let opacity: Double
}

/// The base look applied to the image before tint overlays — conceptually
/// the same knobs as the prototype's CSS `filter` strings (contrast,
/// saturation, brightness, hue-rotate, sepia, grayscale).
struct FilmBaseLook {
    var contrast: Double = 1.0
    var saturation: Double = 1.0
    var brightness: Double = 0.0   // CoreImage brightness is additive (-1...1)
    var hueRotateDegrees: Double = 0
    var sepia: Double = 0          // 0...1 intensity
    var grayscale: Bool = false
}

/// A film recipe: the full "look" recreated from a `recipes.jsx` entry.
struct FilmRecipe: Identifiable, Equatable {
    let id: String
    let name: String
    let brand: String
    let iso: String
    let color: Color
    let isBlackAndWhite: Bool

    let look: FilmBaseLook
    /// 0...1 — native grain weight for this stock (scaled by user grain settings).
    let grain: Double
    /// 0...1 — vignette strength.
    let vignette: Double
    /// Optional warm/red glow around highlights (CineStill-style halation).
    let halation: Color?

    let overlays: [FilmOverlay]

    static func == (lhs: FilmRecipe, rhs: FilmRecipe) -> Bool { lhs.id == rhs.id }
}

enum FilmLibrary {

    /// The full 13-stock library, ported directly from the design prototype's
    /// recipes.jsx — every CSS `filter(...)` string translated to the
    /// equivalent `FilmBaseLook` knobs (contrast/saturation/brightness/
    /// hue-rotate/sepia/grayscale), and every overlay/grain/vignette/halation
    /// value carried over verbatim.
    static let recipes: [FilmRecipe] = [
        FilmRecipe(
            id: "standard",
            name: "Standard",
            brand: "Digital",
            iso: "AUTO",
            color: Color(hex: "#8E8E93"),
            isBlackAndWhite: false,
            look: FilmBaseLook(contrast: 1.0, saturation: 1.02, brightness: 0.0),
            grain: 0.05,
            vignette: 0.04,
            halation: nil,
            overlays: []
        ),
        FilmRecipe(
            id: "portra400",
            name: "Portra 400",
            brand: "Kodak",
            iso: "400",
            color: Color(hex: "#E0A24A"),
            isBlackAndWhite: false,
            look: FilmBaseLook(contrast: 0.96, saturation: 1.06, brightness: 0.05, sepia: 0.10),
            grain: 0.30,
            vignette: 0.14,
            halation: nil,
            overlays: [
                FilmOverlay(color: Color(hex: "#ffd9a8"), blend: .softLight, opacity: 0.22),
                FilmOverlay(color: Color(hex: "#2a2620"), blend: .lighten,   opacity: 0.10),
            ]
        ),
        FilmRecipe(
            id: "gold200",
            name: "Gold 200",
            brand: "Kodak",
            iso: "200",
            color: Color(hex: "#F4A823"),
            isBlackAndWhite: false,
            look: FilmBaseLook(contrast: 1.06, saturation: 1.22, brightness: 0.03, hueRotateDegrees: -8, sepia: 0.20),
            grain: 0.28,
            vignette: 0.18,
            halation: nil,
            overlays: [
                FilmOverlay(color: Color(hex: "#ffbf5e"), blend: .softLight, opacity: 0.30),
                FilmOverlay(color: Color(hex: "#3a1f00"), blend: .multiply,  opacity: 0.08),
            ]
        ),
        FilmRecipe(
            id: "ektar100",
            name: "Ektar 100",
            brand: "Kodak",
            iso: "100",
            color: Color(hex: "#D8352A"),
            isBlackAndWhite: false,
            look: FilmBaseLook(contrast: 1.16, saturation: 1.34, brightness: 0.02),
            grain: 0.10,
            vignette: 0.16,
            halation: nil,
            overlays: [
                FilmOverlay(color: Color(hex: "#ff5a3c"), blend: .softLight, opacity: 0.12),
                FilmOverlay(color: Color(hex: "#0a2a5e"), blend: .softLight, opacity: 0.10),
            ]
        ),
        FilmRecipe(
            id: "classicchrome",
            name: "Classic Chrome",
            brand: "Fujifilm",
            iso: "—",
            color: Color(hex: "#3F8B8B"),
            isBlackAndWhite: false,
            look: FilmBaseLook(contrast: 1.10, saturation: 0.70, brightness: -0.02, sepia: 0.06),
            grain: 0.18,
            vignette: 0.22,
            halation: nil,
            overlays: [
                FilmOverlay(color: Color(hex: "#16324a"), blend: .softLight, opacity: 0.20),
                FilmOverlay(color: Color(hex: "#d9c9a8"), blend: .softLight, opacity: 0.10),
            ]
        ),
        FilmRecipe(
            id: "velvia50",
            name: "Velvia 50",
            brand: "Fujifilm",
            iso: "50",
            color: Color(hex: "#E2231A"),
            isBlackAndWhite: false,
            look: FilmBaseLook(contrast: 1.20, saturation: 1.55, brightness: 0.0),
            grain: 0.10,
            vignette: 0.24,
            halation: nil,
            overlays: [
                FilmOverlay(color: Color(hex: "#0b3d2e"), blend: .softLight, opacity: 0.14),
                FilmOverlay(color: Color(hex: "#3a0010"), blend: .softLight, opacity: 0.12),
            ]
        ),
        FilmRecipe(
            id: "superia400",
            name: "Superia 400",
            brand: "Fujifilm",
            iso: "400",
            color: Color(hex: "#4FAF2C"),
            isBlackAndWhite: false,
            look: FilmBaseLook(contrast: 1.06, saturation: 1.16, brightness: 0.01, hueRotateDegrees: -6),
            grain: 0.30,
            vignette: 0.18,
            halation: nil,
            overlays: [
                FilmOverlay(color: Color(hex: "#1f6b3a"), blend: .softLight, opacity: 0.16),
                FilmOverlay(color: Color(hex: "#2a2620"), blend: .lighten,   opacity: 0.07),
            ]
        ),
        FilmRecipe(
            id: "cinestill800t",
            name: "CineStill 800T",
            brand: "CineStill",
            iso: "800",
            color: Color(hex: "#2B6CB0"),
            isBlackAndWhite: false,
            look: FilmBaseLook(contrast: 1.06, saturation: 1.10, brightness: 0.0, hueRotateDegrees: 8),
            grain: 0.34,
            vignette: 0.20,
            halation: Color(hex: "#ff2d2d"),
            overlays: [
                FilmOverlay(color: Color(hex: "#0b2a55"), blend: .softLight, opacity: 0.26),
                FilmOverlay(color: Color(hex: "#2a2620"), blend: .lighten,   opacity: 0.08),
            ]
        ),
        FilmRecipe(
            id: "cinestill50d",
            name: "CineStill 50D",
            brand: "CineStill",
            iso: "50",
            color: Color(hex: "#1F9E8E"),
            isBlackAndWhite: false,
            look: FilmBaseLook(contrast: 1.08, saturation: 1.06, brightness: 0.02),
            grain: 0.12,
            vignette: 0.16,
            halation: Color(hex: "#ff5a3c"),
            overlays: [
                FilmOverlay(color: Color(hex: "#123a3a"), blend: .softLight, opacity: 0.14),
                FilmOverlay(color: Color(hex: "#ffcaa0"), blend: .softLight, opacity: 0.10),
            ]
        ),
        FilmRecipe(
            id: "hp5",
            name: "HP5 Plus",
            brand: "Ilford",
            iso: "400",
            color: Color(hex: "#9AA0A6"),
            isBlackAndWhite: true,
            look: FilmBaseLook(contrast: 1.18, saturation: 1.0, brightness: 0.03, grayscale: true),
            grain: 0.45,
            vignette: 0.22,
            halation: nil,
            overlays: [
                FilmOverlay(color: Color(hex: "#1c1c1c"), blend: .lighten, opacity: 0.10),
            ]
        ),
        FilmRecipe(
            id: "trix400",
            name: "Tri-X 400",
            brand: "Kodak",
            iso: "400",
            color: Color(hex: "#C9A227"),
            isBlackAndWhite: true,
            look: FilmBaseLook(contrast: 1.34, saturation: 1.0, brightness: -0.03, grayscale: true),
            grain: 0.52,
            vignette: 0.26,
            halation: nil,
            overlays: [
                FilmOverlay(color: Color(hex: "#000000"), blend: .multiply, opacity: 0.06),
            ]
        ),
        FilmRecipe(
            id: "polaroid600",
            name: "Polaroid 600",
            brand: "Instant",
            iso: "640",
            color: Color(hex: "#2BB3C0"),
            isBlackAndWhite: false,
            look: FilmBaseLook(contrast: 0.84, saturation: 0.92, brightness: 0.12, sepia: 0.14),
            grain: 0.22,
            vignette: 0.10,
            halation: nil,
            overlays: [
                FilmOverlay(color: Color(hex: "#9fe3d6"), blend: .softLight, opacity: 0.22),
                FilmOverlay(color: Color(hex: "#34323a"), blend: .lighten,   opacity: 0.20),
                FilmOverlay(color: Color(hex: "#ffe7c2"), blend: .softLight, opacity: 0.14),
            ]
        ),
        FilmRecipe(
            id: "lomochrome",
            name: "LomoChrome",
            brand: "Lomography",
            iso: "400",
            color: Color(hex: "#6FBF73"),
            isBlackAndWhite: false,
            look: FilmBaseLook(contrast: 1.30, saturation: 1.42, brightness: 0.0, hueRotateDegrees: -16),
            grain: 0.34,
            vignette: 0.40,
            halation: nil,
            overlays: [
                FilmOverlay(color: Color(hex: "#1f5e3a"), blend: .softLight, opacity: 0.26),
                FilmOverlay(color: Color(hex: "#3a0030"), blend: .softLight, opacity: 0.16),
            ]
        ),
    ]

    static var `default`: FilmRecipe { recipes[1] } // Portra 400, matching the prototype's default
}

extension Color {
    /// Convenience hex initializer so recipe data can be copied verbatim
    /// from the prototype's `#rrggbb` strings.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
