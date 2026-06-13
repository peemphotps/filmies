# Filmies 🎞️

A native iOS film camera built in SwiftUI. Filmies shows a **live, film-look
viewfinder** — what you see is exactly what gets captured — with a library of
classic film stocks, analog framing formats, and an in-app gallery.

The look isn't a post-process filter slapped on after the shot: every camera
frame is run through a CoreImage/Metal pipeline in real time, and the capture
path reuses that same pipeline, so the preview is truly WYSIWYG.

## Features

### Film recipes
- **13 film stocks** ported from the design prototype — Standard, Portra 400,
  Gold 200, Ektar 100, Classic Chrome, Velvia 50, Superia 400, CineStill 800T,
  CineStill 50D, HP5 Plus, Tri-X 400, Polaroid 600, LomoChrome.
- Each recipe is a base look (contrast / saturation / brightness / hue / sepia /
  grayscale) + tint overlays with blend modes + grain + vignette, plus halation
  for the CineStill stocks.
- Tap-to-select bottom-sheet picker showing every film as a card — scales
  automatically as recipes are added.

### Live viewfinder & capture
- Real-time CoreImage filter chain rendered to a Metal-backed view.
- Manual **exposure** nudge and **grain** controls (strength: Off / Low / High,
  size: Small / Medium / Large).
- Capture bakes the exact on-screen look into a full-resolution photo.

### Framing
- **Aspect ratios:** Full, 1:1, 4:3, 16:9, and a vertical **XPan** (24:65)
  panoramic. The viewfinder letterboxes to show the true framing.
- **Lenses:** 0.5× ultra-wide / 1× toggle on the back camera (when available).
- Orientation locked to portrait for stable framing.

### Gallery
- In-app gallery backed by **SwiftData**, indexing each shot's asset, film
  recipe, and capture date.
- Captures are filed into a dedicated **"Filmies" album** in the Photos library.
- Full-screen swipeable viewer with a filmstrip, **sort** (newest ⇄ oldest) and
  **filter by film style**.

### Remembers where you left off
Camera facing, lens, film recipe, exposure, grain, and aspect ratio all persist
across launches via `@AppStorage`. Filmies reopens exactly as you left it
(defaulting to the back 1× camera on first launch).

## Architecture

Lightweight MVVM with Swift's `@Observable`:

| File | Role |
|------|------|
| `CameraService.swift` | Owns the `AVCaptureSession`, pulls frames, runs the pipeline, bakes & saves captures, manages lens/rotation. |
| `FilmFilterPipeline.swift` | The CoreImage filter chain (shared by live preview and capture). |
| `FilteredPreviewView.swift` | Metal-backed view that renders filtered `CIImage`s. |
| `CameraViewModel.swift` | User-facing state + persisted settings, syncs the look to the service. |
| `CameraScreen.swift` | Main camera UI — viewfinder, ratio chips, lens pill, film selector, shutter. |
| `FilmRecipe.swift` | The 13-stock film library data model. |
| `FilmPickerSheet.swift` | Tap-to-select film grid sheet. |
| `CaptureFormat.swift` | Aspect-ratio cropping + lens definitions. |
| `GalleryView.swift` | SwiftData-backed gallery, viewer, sort & filter. |
| `FilmieShot.swift` | SwiftData `@Model` indexing each captured shot. |

`design/` holds the original browser prototype (`.jsx` / HTML) this was built
from — reference only, not part of the build.

## Building

Open `Filmies.xcodeproj` in Xcode, select your team for signing, and run on a
physical device (the live camera requires real hardware).

- **Minimum:** iOS 17.0
- **Frameworks:** SwiftUI, AVFoundation, CoreImage, Metal, Photos, SwiftData

## Permissions

- **Camera** — for the live viewfinder and capture.
- **Photos (read/write)** — to save shots into the Filmies album and show them
  in the in-app gallery.

---

🤖 Built with [Claude Code](https://claude.com/claude-code)
