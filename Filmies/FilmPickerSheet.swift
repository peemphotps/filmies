//
//  FilmPickerSheet.swift
//  Filmies
//
//  The film picker — replaces the old scroll-carousel dial (which fought the
//  scroll gesture) with a simple, reliable tap-to-select grid presented as a
//  bottom sheet. Every recipe in `FilmLibrary.recipes` is shown as a tappable
//  card; the active one is highlighted. Selecting applies the film instantly
//  and dismisses. Adding a new film in the future is zero-UI-work: append it
//  to `FilmLibrary.recipes` and it appears here automatically.
//

import SwiftUI

struct FilmPickerSheet: View {
    let recipes: [FilmRecipe]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(recipes.indices, id: \.self) { i in
                        card(for: i)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Film")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
    }

    private func card(for i: Int) -> some View {
        let recipe = recipes[i]
        let isActive = i == selectedIndex
        return Button {
            onSelect(i)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                FilmBoxView(recipe: recipe, isActive: isActive, scale: 1.15)
                Text(recipe.name)
                    .font(.system(size: 12.5, weight: isActive ? .bold : .semibold))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? recipe.color.opacity(0.14) : .white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? recipe.color : .white.opacity(0.08),
                            lineWidth: isActive ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
