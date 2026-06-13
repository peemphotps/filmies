//
//  FilmieShot.swift
//  Filmies
//
//  SwiftData record of a single Filmies-captured photo — just enough metadata
//  to power the in-app gallery (sort by capture date, filter by film style)
//  without re-deriving anything from the Photos asset itself. The actual
//  image data lives in the Photos library (in the "Filmies" album); this is
//  a lightweight local index over it.
//
//  Per the agreed v2 scope, this store starts completely empty — we do not
//  backfill any pre-gallery test shots captured before this feature existed.
//

import Foundation
import SwiftData

@Model
final class FilmieShot {
    /// `PHAsset.localIdentifier` — the link back to the actual photo in the
    /// Photos library / "Filmies" album.
    var assetIdentifier: String

    /// `FilmRecipe.id` — which film look was active when this shot was taken.
    var recipeID: String

    /// When the shutter was pressed (used for newest-first/oldest-first sort).
    var capturedAt: Date

    init(assetIdentifier: String, recipeID: String, capturedAt: Date = .now) {
        self.assetIdentifier = assetIdentifier
        self.recipeID = recipeID
        self.capturedAt = capturedAt
    }
}
