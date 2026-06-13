//
//  FilmDialView.swift
//  Filmies
//
//  The little 35mm film-box card (`FilmBoxView`) used to represent a recipe.
//  Originally this also held a scroll-carousel dial, but that was replaced by
//  a reliable tap-to-select grid (see FilmPickerSheet) after the carousel's
//  scroll gesture proved fragile; this file now just vends the reusable card.
//

import SwiftUI

/// A single 35mm film box — label band in the recipe's color, brand + ISO.
struct FilmBoxView: View {
    let recipe: FilmRecipe
    let isActive: Bool
    var scale: CGFloat = 1

    private let boxWidth: CGFloat = 46
    private let boxHeight: CGFloat = 62

    var body: some View {
        let w = boxWidth * scale
        let h = boxHeight * scale

        VStack(spacing: 1) {
            Text(recipe.brand == "Digital" ? "AUTO" : String(recipe.brand.prefix(7)))
                .font(.system(size: 8 * scale, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
            Text(recipe.iso)
                .font(.system(size: 15 * scale, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(width: w, height: h * 0.70 + 6 * scale, alignment: .center)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            VStack(spacing: 0) {
                recipe.color.opacity(isActive ? 1 : 0.82)
                    .frame(height: h * 0.30)
                Color.black.opacity(0.35)
                    .frame(height: 3 * scale)
                Color.clear
            }
        }
        .frame(width: w, height: h)
        .background(
            LinearGradient(colors: [Color(hex: "#26262b"), Color(hex: "#141417")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                .stroke(isActive ? recipe.color : .clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(isActive ? 0.5 : 0.4), radius: isActive ? 10 : 3, y: isActive ? 8 : 2)
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.15))
                .frame(width: 4 * scale, height: 4 * scale)
                .padding(3 * scale)
        }
        .animation(.easeOut(duration: 0.25), value: isActive)
    }
}
