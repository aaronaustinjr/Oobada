//
//  OobadaApp.swift
//  Oobada
//
//  Created by Tiare Austin on 7/9/25.
//

import SwiftUI

@main
struct OobadaApp: App {
    @StateObject private var languageManager = LanguageManager()
    @StateObject private var premiumManager = PremiumManager()
    @StateObject private var themeManager = ThemeManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(languageManager)
                .environmentObject(premiumManager)
                .environmentObject(themeManager)
        }
    }
}
