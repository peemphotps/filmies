//
//  CameraScreen.swift
//  Filmies
//
//  The main camera screen — full-bleed live filtered viewfinder, top control
//  bar, film badge + frame counter, fine-adjust panel (exposure + grain
//  chips), film dial picker, and shutter row. Native port of camera.jsx's
//  CameraApp, minus the prototype's fake IOSDevice chrome (we use the real
//  device's safe areas) and the demo-scene fallback (a real camera app always
//  has camera access).
//

import SwiftUI
import SwiftData

struct CameraScreen: View {
    @State private var viewModel = CameraViewModel()
    @State private var flashFlash = false
    @State private var pressed = false
    @State private var galleryOpen = false
    @State private var filmPickerOpen = false

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isAuthorized {
                liveCameraContent
            } else {
                PermissionPromptView(retry: { Task { await viewModel.start() } })
            }
        }
        .task {
            viewModel.attachModelContext(modelContext)
            await viewModel.start()
        }
        .onDisappear { viewModel.stop() }
        .fullScreenCover(isPresented: $galleryOpen) {
            GalleryView()
        }
        .sheet(isPresented: $filmPickerOpen) {
            FilmPickerSheet(recipes: viewModel.recipes,
                            selectedIndex: viewModel.recipeIndex,
                            onSelect: viewModel.selectRecipe)
        }
        .alert("Filmies", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.lastError ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.lastError != nil }, set: { _ in })
    }

    // MARK: - Live camera

    private var liveCameraContent: some View {
        GeometryReader { geo in
            ZStack {
                // Viewfinder fills the frame. Isolated into its own view so
                // that the ~30fps `previewImage` stream re-renders ONLY this
                // layer — not the whole CameraScreen. Previously the entire
                // screen body (including the film dial) re-evaluated on every
                // camera frame, which fought the dial's scroll gesture and
                // made it snap back / refuse to move.
                LivePreviewLayer(viewModel: viewModel)
                    .ignoresSafeArea()

                // Capture flash
                Color.white
                    .opacity(flashFlash ? 0.85 : 0)
                    .animation(flashFlash ? nil : .easeOut(duration: 0.32), value: flashFlash)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 12) {
                    topBar
                    ratioChips
                    Spacer()
                }
                .padding(.top, geo.safeAreaInsets.top + 8)

                VStack(spacing: 0) {
                    Spacer()
                    badgesRow
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                .padding(.top, geo.safeAreaInsets.top + 8)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, geo.safeAreaInsets.top + 60)

                // (The film name now lives in the bottom selector pill, so the
                // old top-left film badge was removed — it overlapped the new
                // aspect-ratio chips.)

                // Fine-adjust panel
                VStack {
                    Spacer()
                    if viewModel.adjustOpen {
                        adjustPanel
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, bottomZoneHeight)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.adjustOpen)

                // Bottom zone — dial + shutter row
                VStack {
                    Spacer()
                    bottomZone(geo: geo)
                }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            GlassIconButton(systemName: viewModel.flashOn ? "bolt.fill" : "bolt.slash",
                            isActive: viewModel.flashOn) {
                viewModel.flashOn.toggle()
            }
            Spacer()
            HStack(spacing: 10) {
                GlassIconButton(systemName: "slider.horizontal.3", isActive: viewModel.adjustOpen) {
                    withAnimation { viewModel.toggleAdjust() }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Aspect-ratio chips

    private var ratioChips: some View {
        HStack(spacing: 6) {
            ForEach(AspectRatio.allCases) { ratio in
                let isOn = viewModel.aspectRatio == ratio
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { viewModel.aspectRatio = ratio }
                } label: {
                    Text(ratio.label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isOn ? Color(hex: "#161618") : .white.opacity(0.85))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(isOn ? Color.white : .black.opacity(0.32),
                                    in: Capsule())
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Badges

    private var badgesRow: some View { EmptyView() } // reserved (kept structure simple; badges placed above)

    // MARK: - Fine-adjust panel

    private var adjustPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("EXPOSURE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 70, alignment: .leading)
                Slider(value: Binding(
                    get: { viewModel.exposure },
                    set: { viewModel.exposure = $0 }
                ), in: -1...1, step: 0.05)
                .tint(viewModel.currentRecipe.color)
                Text(String(format: "%+.1f", viewModel.exposure))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 42, alignment: .trailing)
            }

            chipRow(label: "STRENGTH",
                    options: CameraViewModel.GrainStrength.allCases,
                    selection: viewModel.grainStrength,
                    title: { $0.rawValue }) { viewModel.grainStrength = $0 }

            chipRow(label: "GRAIN",
                    options: CameraViewModel.GrainSize.allCases,
                    selection: viewModel.grainSize,
                    title: { $0.rawValue }) { viewModel.grainSize = $0 }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.black.opacity(0.6))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func chipRow<T: Hashable>(
        label: String,
        options: [T],
        selection: T,
        title: @escaping (T) -> String,
        onChange: @escaping (T) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 70, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { opt in
                    let isOn = opt == selection
                    Button {
                        onChange(opt)
                    } label: {
                        Text(title(opt))
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(isOn ? Color(hex: "#161618") : .white.opacity(0.82))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(isOn ? viewModel.currentRecipe.color : .white.opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Bottom zone

    private let bottomZoneHeight: CGFloat = 234

    private func bottomZone(geo: GeometryProxy) -> some View {
        VStack(spacing: 12) {
            filmSelectorButton
                .frame(height: 76)

            // Lens pill (0.5× ⇄ 1×) — only on the back camera, only on
            // devices that actually have an ultra-wide lens.
            if !viewModel.isFrontCamera && viewModel.supportsUltraWide {
                lensPill
            }

            HStack {
                recentThumb
                Spacer()
                shutterButton
                Spacer()
                GlassIconButton(systemName: "arrow.triangle.2.circlepath.camera", size: 50) {
                    viewModel.flipCamera()
                }
            }
            .padding(.horizontal, 32)
        }
        .padding(.bottom, max(geo.safeAreaInsets.bottom, 16) + 14)
        .frame(height: bottomZoneHeight, alignment: .bottom)
    }

    private var lensPill: some View {
        HStack(spacing: 4) {
            ForEach(CameraLens.allCases) { lens in
                let isOn = viewModel.lens == lens
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { viewModel.lens = lens }
                } label: {
                    Text(lens.label)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(isOn ? Color(hex: "#161618") : .white.opacity(0.85))
                        .frame(width: 42, height: 30)
                        .background(isOn ? Color.white : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.black.opacity(0.32), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var filmSelectorButton: some View {
        Button { filmPickerOpen = true } label: {
            HStack(spacing: 11) {
                FilmBoxView(recipe: viewModel.currentRecipe, isActive: true, scale: 0.78)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentRecipe.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text(viewModel.currentRecipe.brand == "Digital"
                         ? "Tap to choose film"
                         : "\(viewModel.currentRecipe.brand) · ISO \(viewModel.currentRecipe.iso)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.32), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var recentThumb: some View {
        Button { galleryOpen = true } label: {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
                .overlay {
                    RecentShotThumbnail()
                }
                .overlay {
                    if viewModel.isSaving {
                        ZStack {
                            Color.black.opacity(0.35)
                            ProgressView().tint(.white)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var shutterButton: some View {
        Button {
            pressed = true
            flashFlash = true
            viewModel.capture()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { pressed = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { flashFlash = false }
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 3)
                Circle()
                    .fill(.white)
                    .padding(pressed ? 8 : 5)
                    .animation(.easeOut(duration: 0.12), value: pressed)
            }
            .frame(width: 74, height: 74)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Live preview layer (isolated re-render)

/// Wraps the high-frequency filtered camera preview in its own view so that
/// reading `viewModel.previewImage` (which changes ~30×/sec) only invalidates
/// THIS view under SwiftUI's Observation tracking — keeping the rest of the
/// camera screen (notably the scrollable film dial) stable between frames.
private struct LivePreviewLayer: View {
    let viewModel: CameraViewModel
    var body: some View {
        FilteredPreviewView(image: viewModel.previewImage)
    }
}

// MARK: - Reusable glass button

struct GlassIconButton: View {
    let systemName: String
    var isActive: Bool = false
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(isActive ? Color(hex: "#1c1c1c") : .white)
                .frame(width: size, height: size)
                .background(
                    isActive ? Color(red: 1, green: 0.84, blue: 0.04).opacity(0.92)
                             : Color(white: 0.16).opacity(0.55),
                    in: Circle()
                )
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

// MARK: - Permission prompt

struct PermissionPromptView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
            VStack(spacing: 6) {
                Text("Camera access needed")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                Text("Filmies needs your camera to show a live, film-look viewfinder and capture photos.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                retry()
            } label: {
                Text("Open Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(32)
    }
}

#Preview {
    CameraScreen()
}
