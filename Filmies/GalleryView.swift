//
//  GalleryView.swift
//  Filmies
//
//  The in-app photo gallery — a full-screen swipeable viewer with a
//  filmstrip, backed by the SwiftData `FilmieShot` index (which mirrors
//  what's in the Photos library's "Filmies" album). Per the agreed v2 scope:
//
//   • View-only — no in-app delete (manage/delete via the system Photos app).
//   • Sort: simple newest-first ⇄ oldest-first toggle.
//   • Filter: single-select film-style chips ("All" + one per recipe).
//   • Both sort and filter always reset to defaults ("All", newest-first)
//     each time the gallery is opened — no persisted state.
//   • Starts fresh — pre-gallery test shots are not backfilled, so only
//     shots captured from this point forward appear here.
//

import SwiftUI
import SwiftData
import Photos

// MARK: - Gallery

struct GalleryView: View {
    @Environment(\.dismiss) private var dismiss

    /// All recorded shots, newest first at the data layer; we re-sort/filter
    /// in-memory below so the toggle/chips can change live without re-querying.
    @Query(sort: \FilmieShot.capturedAt, order: .reverse) private var allShots: [FilmieShot]

    // Always reset to "All / newest-first" on open — no persisted state.
    @State private var newestFirst = true
    @State private var selectedRecipeID: String? = nil   // nil == "All"
    @State private var selection: PersistentIdentifier?

    private var visibleShots: [FilmieShot] {
        let filtered = selectedRecipeID == nil
            ? allShots
            : allShots.filter { $0.recipeID == selectedRecipeID }
        return newestFirst ? filtered : filtered.reversed()
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if visibleShots.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    header
                    filterChips
                    pager
                    filmstrip
                }
            }

            VStack {
                HStack {
                    closeButton
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
        }
        .onAppear {
            // (Re-)establish default selection each time the gallery opens.
            selection = visibleShots.first?.persistentModelID
        }
        .onChange(of: selectedRecipeID) { _, _ in
            selection = visibleShots.first?.persistentModelID
        }
        .onChange(of: newestFirst) { _, _ in
            selection = visibleShots.first?.persistentModelID
        }
    }

    // MARK: - Chrome

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(white: 0.16).opacity(0.7), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack {
            Text("Filmies")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            sortToggle
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 6)
    }

    private var sortToggle: some View {
        Button { newestFirst.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: newestFirst ? "arrow.down" : "arrow.up")
                Text(newestFirst ? "Newest" : "Oldest")
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", isOn: selectedRecipeID == nil, color: .white) {
                    selectedRecipeID = nil
                }
                ForEach(FilmLibrary.recipes) { recipe in
                    filterChip(title: recipe.name, isOn: selectedRecipeID == recipe.id, color: recipe.color) {
                        selectedRecipeID = recipe.id
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func filterChip(title: String, isOn: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(isOn ? Color(hex: "#161618") : .white.opacity(0.82))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isOn ? Color.white : .white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pager (full-screen swipe)

    private var pager: some View {
        TabView(selection: $selection) {
            ForEach(visibleShots, id: \.persistentModelID) { shot in
                ShotDetailView(shot: shot)
                    .tag(Optional(shot.persistentModelID))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: .infinity)
    }

    // MARK: - Filmstrip

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleShots, id: \.persistentModelID) { shot in
                        FilmstripThumb(shot: shot, isSelected: shot.persistentModelID == selection)
                            .id(shot.persistentModelID)
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.2)) { selection = shot.persistentModelID }
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: selection) { _, newValue in
                guard let newValue else { return }
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
        .frame(height: 64)
        .padding(.bottom, 24)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.35))
            VStack(spacing: 5) {
                Text(allShots.isEmpty ? "No shots yet" : "No shots with this film")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                Text(allShots.isEmpty
                     ? "Photos you capture in Filmies will show up here, organized by film style and capture date."
                     : "Try a different film style, or switch back to “All”.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }
            if !allShots.isEmpty {
                Button("Show all films") { selectedRecipeID = nil }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.white, in: Capsule())
            }
        }
    }
}

// MARK: - Detail page

private struct ShotDetailView: View {
    let shot: FilmieShot
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            captionBadge
                .padding(.bottom, 4)
        }
        .task(id: shot.assetIdentifier) {
            image = await PhotoAssetLoader.shared.fullImage(forAssetIdentifier: shot.assetIdentifier)
        }
    }

    private var recipe: FilmRecipe? {
        FilmLibrary.recipes.first { $0.id == shot.recipeID }
    }

    private var captionBadge: some View {
        HStack(spacing: 8) {
            if let recipe {
                Circle().fill(recipe.color).frame(width: 8, height: 8)
                Text(recipe.name)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("·")
                .foregroundStyle(.white.opacity(0.4))
            Text(shot.capturedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.32), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Filmstrip thumbnail

private struct FilmstripThumb: View {
    let shot: FilmieShot
    let isSelected: Bool
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.06)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.white : .white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        )
        .task(id: shot.assetIdentifier) {
            thumbnail = await PhotoAssetLoader.shared.thumbnail(forAssetIdentifier: shot.assetIdentifier, targetSize: CGSize(width: 120, height: 120))
        }
    }
}

// MARK: - Recent thumbnail (camera screen button)

/// Shows the most recently captured Filmies shot as a small thumbnail —
/// replaces the old static placeholder icon on the camera screen's
/// "recent" button.
struct RecentShotThumbnail: View {
    @Query(sort: \FilmieShot.capturedAt, order: .reverse) private var shots: [FilmieShot]
    @State private var thumbnail: UIImage?
    @State private var loadedIdentifier: String?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "square.stack")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .task(id: shots.first?.assetIdentifier) {
            guard let identifier = shots.first?.assetIdentifier, identifier != loadedIdentifier else { return }
            loadedIdentifier = identifier
            thumbnail = await PhotoAssetLoader.shared.thumbnail(forAssetIdentifier: identifier, targetSize: CGSize(width: 100, height: 100))
        }
    }
}

// MARK: - Photo asset loading

/// Thin async wrapper around `PHImageManager` for fetching images by
/// `PHAsset.localIdentifier` — shared so the gallery's many thumbnails and
/// the camera screen's recent-shot badge all go through the same cache-aware
/// manager instance.
actor PhotoAssetLoader {
    static let shared = PhotoAssetLoader()

    private let manager = PHCachingImageManager()

    func thumbnail(forAssetIdentifier identifier: String, targetSize: CGSize) async -> UIImage? {
        await image(forAssetIdentifier: identifier, targetSize: targetSize, contentMode: .aspectFill, deliveryMode: .opportunistic)
    }

    func fullImage(forAssetIdentifier identifier: String) async -> UIImage? {
        await image(forAssetIdentifier: identifier, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, deliveryMode: .highQualityFormat)
    }

    private func image(forAssetIdentifier identifier: String, targetSize: CGSize, contentMode: PHImageContentMode, deliveryMode: PHImageRequestOptionsDeliveryMode) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = deliveryMode

        return await withCheckedContinuation { continuation in
            var didResume = false
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, options: options) { image, info in
                // `opportunistic`/progressive delivery can call back more than
                // once (low-res then high-res); only resume the continuation
                // the first time, but let later (better) images replace the UI
                // via subsequent calls being ignored is acceptable for thumbs.
                guard !didResume else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if image != nil && (!isDegraded || deliveryMode == .opportunistic) {
                    didResume = true
                    continuation.resume(returning: image)
                } else if image == nil {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
