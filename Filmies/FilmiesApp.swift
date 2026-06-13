//
//  FilmiesApp.swift
//  Filmies
//
//  Created by Warunkan Konnantaphat on 7/6/2569 BE.
//

import SwiftUI
import SwiftData

@main
struct FilmiesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: FilmieShot.self)
    }
}
