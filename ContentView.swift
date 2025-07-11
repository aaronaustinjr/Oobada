//
//  ContentView.swift
//  Oobada
//
//  Created by Tiare Austin on 7/9/25.
//

import SwiftUI
import Foundation
import MessageUI

// MARK: - Message Composer
struct MessageComposer: UIViewControllerRepresentable {
    @Binding var isShowing: Bool
    let message: String
    let onResult: (MessageComposeResult) -> Void
    
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = context.coordinator
        composer.body = message
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: MessageComposer
        
        init(_ parent: MessageComposer) {
            self.parent = parent
        }
        
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            parent.isShowing = false
            parent.onResult(result)
        }
    }
}
struct CustomLanguage: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var mapping: [Character: String]
    var numberMapping: [Character: String] // New: mapping for numbers 0-9
    var createdDate: Date
    
    init(name: String, mapping: [Character: String] = [:], numberMapping: [Character: String] = [:]) {
        self.id = UUID()
        self.name = name
        self.mapping = mapping
        self.numberMapping = numberMapping
        self.createdDate = Date()
    }
    
    // MARK: - Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CustomLanguage, rhs: CustomLanguage) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Codable conformance
    enum CodingKeys: String, CodingKey {
        case id, name, mapping, numberMapping, createdDate
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        
        // Handle Character keys in mapping dictionary
        let mappingData = try container.decode([String: String].self, forKey: .mapping)
        mapping = [:]
        for (key, value) in mappingData {
            if let character = key.first {
                mapping[character] = value
            }
        }
        
        // Handle Character keys in numberMapping dictionary (with default for backwards compatibility)
        let numberMappingData = try container.decodeIfPresent([String: String].self, forKey: .numberMapping) ?? [:]
        numberMapping = [:]
        for (key, value) in numberMappingData {
            if let character = key.first {
                numberMapping[character] = value
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdDate, forKey: .createdDate)
        
        // Convert Character keys to String keys for encoding
        let mappingData = mapping.reduce(into: [String: String]()) { result, pair in
            result[String(pair.key)] = pair.value
        }
        try container.encode(mappingData, forKey: .mapping)
        
        // Convert Character keys to String keys for numberMapping
        let numberMappingData = numberMapping.reduce(into: [String: String]()) { result, pair in
            result[String(pair.key)] = pair.value
        }
        try container.encode(numberMappingData, forKey: .numberMapping)
    }
}

// MARK: - Language Manager
class LanguageManager: ObservableObject {
    @Published var languages: [CustomLanguage] = []
    @Published var selectedLanguage: CustomLanguage?
    
    private let userDefaults = UserDefaults.standard
    private let languagesKey = "SavedLanguages"
    
    init() {
        loadLanguages()
        if languages.isEmpty {
            createDefaultLanguage()
        }
    }
    
    func createDefaultLanguage() {
        let defaultLanguage = CustomLanguage(name: "My First Language")
        languages.append(defaultLanguage)
        selectedLanguage = defaultLanguage
        saveLanguages()
    }
    
    func addLanguage(_ language: CustomLanguage) {
        languages.append(language)
        saveLanguages()
    }
    
    func updateLanguage(_ language: CustomLanguage) {
        if let index = languages.firstIndex(where: { $0.id == language.id }) {
            languages[index] = language
            if selectedLanguage?.id == language.id {
                selectedLanguage = language
            }
            saveLanguages()
        }
    }
    
    func deleteLanguage(_ language: CustomLanguage) {
        languages.removeAll { $0.id == language.id }
        if selectedLanguage?.id == language.id {
            selectedLanguage = languages.first
        }
        saveLanguages()
    }
    
    func getAccessibleLanguages(isPremium: Bool) -> [CustomLanguage] {
        if isPremium {
            return languages
        } else {
            // For free users, only return languages without premium features
            return languages.filter { language in
                // Check if this is the first language (always accessible for free users)
                let isFirstLanguage = languages.first?.id == language.id
                
                // Check if language has premium features (number mappings)
                let hasPremiumFeatures = !language.numberMapping.isEmpty
                
                // Free users can access: their first language OR languages without premium features
                return isFirstLanguage || !hasPremiumFeatures
            }
        }
    }
    
    func isLanguageAccessible(_ language: CustomLanguage, isPremium: Bool) -> Bool {
        if isPremium {
            return true
        } else {
            // Free users can access their first language regardless of features
            let isFirstLanguage = languages.first?.id == language.id
            
            // Or any language without premium features
            let hasPremiumFeatures = !language.numberMapping.isEmpty
            
            return isFirstLanguage || !hasPremiumFeatures
        }
    }
    
    func canUseLanguageFeatures(_ language: CustomLanguage, isPremium: Bool) -> Bool {
        if isPremium {
            return true
        } else {
            // Free users can only use the full features of their first language
            return languages.first?.id == language.id
        }
    }
    
    func handlePremiumStatusChange(isPremium: Bool) {
        if !isPremium {
            // If user loses premium, switch to first language if current selection is inaccessible
            if let selected = selectedLanguage,
               !isLanguageAccessible(selected, isPremium: isPremium) {
                selectedLanguage = languages.first
            }
        }
    }
    
    func translate(text: String, using language: CustomLanguage, isPremium: Bool) -> String {
        var result = ""
        for character in text {
            let lowerChar = Character(character.lowercased())
            
            // Check if it's a number (0-9) and if premium features are accessible
            if character.isNumber,
               canUseLanguageFeatures(language, isPremium: isPremium),
               let mapped = language.numberMapping[character] {
                result += mapped
            }
            // Check if it's a letter
            else if let mapped = language.mapping[lowerChar] {
                // If original character was uppercase, make the mapped result uppercase
                if character.isUppercase {
                    result += mapped.uppercased()
                } else {
                    result += mapped.lowercased()
                }
            } else {
                result += String(character)
            }
        }
        return result
    }
    
    func decrypt(text: String, using language: CustomLanguage, isPremium: Bool) -> String {
        var result = ""
        let reverseMapping = createReverseMapping(from: language.mapping)
        let reverseNumberMapping = createReverseNumberMapping(from: language.numberMapping)
        
        var i = text.startIndex
        while i < text.endIndex {
            var found = false
            
            // Try to find the longest matching cipher text
            for length in stride(from: 3, through: 1, by: -1) {
                let endIndex = text.index(i, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
                let substring = String(text[i..<endIndex])
                
                // Try exact match in number mapping first (only if premium features accessible)
                if canUseLanguageFeatures(language, isPremium: isPremium),
                   let originalChar = reverseNumberMapping[substring] {
                    result += originalChar
                    i = endIndex
                    found = true
                    break
                }
                
                // Try exact match in letter mapping
                if let originalChar = reverseMapping[substring] {
                    result += originalChar
                    i = endIndex
                    found = true
                    break
                }
                
                // Try case-insensitive match in letter mapping
                if let originalChar = reverseMapping[substring.lowercased()] {
                    // If the cipher was uppercase, make the result uppercase
                    if substring.first?.isUppercase == true {
                        result += originalChar.uppercased()
                    } else {
                        result += originalChar.lowercased()
                    }
                    i = endIndex
                    found = true
                    break
                }
            }
            
            if !found {
                result += String(text[i])
                i = text.index(after: i)
            }
        }
        
        return result
    }
    
    private func createReverseMapping(from mapping: [Character: String]) -> [String: String] {
        var reverseMapping: [String: String] = [:]
        for (key, value) in mapping {
            // Create reverse mappings for both cases
            reverseMapping[value.lowercased()] = String(key)
            reverseMapping[value.uppercased()] = String(key)
        }
        return reverseMapping
    }
    
    private func createReverseNumberMapping(from numberMapping: [Character: String]) -> [String: String] {
        var reverseMapping: [String: String] = [:]
        for (key, value) in numberMapping {
            // Numbers don't have case variations
            reverseMapping[value] = String(key)
        }
        return reverseMapping
    }
    
    func exportLanguage(_ language: CustomLanguage) -> String {
        guard let data = try? JSONEncoder().encode(language),
              let jsonString = String(data: data, encoding: .utf8) else {
            return ""
        }
        return jsonString.data(using: .utf8)?.base64EncodedString() ?? ""
    }
    
    func importLanguage(from encodedString: String) -> CustomLanguage? {
        guard let data = Data(base64Encoded: encodedString),
              let jsonString = String(data: data, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8),
              let language = try? JSONDecoder().decode(CustomLanguage.self, from: jsonData) else {
            return nil
        }
        
        // Check if language already exists
        if languages.contains(where: { $0.name == language.name }) {
            return nil // Language with same name already exists
        }
        
        return language
    }
    
    private func saveLanguages() {
        if let encoded = try? JSONEncoder().encode(languages) {
            userDefaults.set(encoded, forKey: languagesKey)
        }
    }
    
    private func loadLanguages() {
        if let data = userDefaults.data(forKey: languagesKey),
           let decoded = try? JSONDecoder().decode([CustomLanguage].self, from: data) {
            languages = decoded
            selectedLanguage = languages.first
        }
    }
}

// MARK: - Premium Manager
class PremiumManager: ObservableObject {
    @Published var isPremium: Bool = false {
        didSet {
            // Notify language manager when premium status changes
            NotificationCenter.default.post(
                name: NSNotification.Name("PremiumStatusChanged"),
                object: isPremium
            )
        }
    }
    @Published var showPaywall: Bool = false
    
    // Simulate premium features
    func purchasePremium() {
        isPremium = true
        showPaywall = false
    }
    
    func restorePurchases() {
        // Simulate restore
        isPremium = false
    }
}

// MARK: - Theme Manager
class ThemeManager: ObservableObject {
    @Published var isDarkMode: Bool = true // Changed from false to true
    
    private let userDefaults = UserDefaults.standard
    private let darkModeKey = "DarkModeEnabled"
    
    init() {
        // Check if user has previously set a preference
        if userDefaults.object(forKey: darkModeKey) != nil {
            // User has a saved preference, use it
            isDarkMode = userDefaults.bool(forKey: darkModeKey)
        } else {
            // No saved preference, default to dark mode
            isDarkMode = true
            // Save the default preference
            saveDarkModePreference()
        }
    }
    
    func saveDarkModePreference() {
        userDefaults.set(isDarkMode, forKey: darkModeKey)
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var premiumManager: PremiumManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var selectedTab = 0
    
    private let darkTabBarBackground = Color(red: 0.15, green: 0.15, blue: 0.2)
    
    var body: some View {
        ZStack {
            
            TabView(selection: $selectedTab) {
                TranslateView()
                    .tabItem {
                        Image(systemName: "textformat.abc")
                        Text("Translate")
                    }
                    .tag(0)
                
                LanguageListView()
                    .tabItem {
                        Image(systemName: "list.bullet")
                        Text("Languages")
                    }
                    .tag(1)
                
                CreateLanguageView()
                    .tabItem {
                        Image(systemName: "plus.circle")
                        Text("Create")
                    }
                    .tag(2)
                
                HowToView()
                    .tabItem {
                        Image(systemName: "questionmark.circle")
                        Text("How To")
                    }
                    .tag(3)
                
                SettingsView()
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
                    .tag(4)
            }
            .accentColor(.teal) // Changed from .purple
            .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
        }
        .onAppear {
            setupCustomTabBarAppearance()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToLanguagesTab"))) { _ in
            selectedTab = 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToTranslateTab"))) { _ in
            selectedTab = 0
        }
        .sheet(isPresented: $premiumManager.showPaywall) {
            PaywallView()
        }
    }
    
    private func setupCustomTabBarAppearance() {
        let tabBarAppearance = UITabBarAppearance()
        
        // Configure for different states
        tabBarAppearance.configureWithOpaqueBackground()
        
        // Set dark background color for tab bar
        tabBarAppearance.backgroundColor = UIColor(darkTabBarBackground)
        
        // Add subtle shadow
        tabBarAppearance.shadowColor = UIColor.black.withAlphaComponent(0.3)
        
        // Selected item color - bright teal for contrast
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor.systemTeal // Changed from UIColor.systemPurple
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor.systemTeal // Changed from UIColor.systemPurple
        ]
        
        // Normal item color - light gray for contrast against dark background
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor.lightGray
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.lightGray
        ]
        
        // Apply to all tab bar states
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        
        // Add subtle border
        UITabBar.appearance().layer.borderWidth = 0.5
        UITabBar.appearance().layer.borderColor = UIColor.black.withAlphaComponent(0.2).cgColor
    }
}

// MARK: - Translate View
struct TranslateView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var premiumManager: PremiumManager
    @State private var encryptInputText = ""
    @State private var decryptInputText = ""
    @State private var translatedText = ""
    @State private var showCopiedAlert = false
    @State private var showMessageComposer = false
    @State private var showMessageResult = false
    @State private var messageResultText = ""
    @State private var isDecryptMode = false
    
    private let freeCharacterLimit = 100
    private let darkHeaderBackground = Color(red: 0.15, green: 0.15, blue: 0.2)
    
    var accessibleLanguages: [CustomLanguage] {
        languageManager.getAccessibleLanguages(isPremium: premiumManager.isPremium)
    }
    
    var currentInputText: String {
        isDecryptMode ? decryptInputText : encryptInputText
    }
    
    // Gradient border for input box
    private var gradientBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: [.teal, .green]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
    }
    
    // Background color for translated text
    private var translatedTextBackground: Color {
        if isDecryptMode {
            return Color.mint.opacity(0.15)
        } else {
            return Color.teal.opacity(0.15)
        }
    }
    
    // Border color for translated text
    private var translatedTextBorder: Color {
        if isDecryptMode {
            return Color.mint.opacity(0.5)
        } else {
            return Color.teal.opacity(0.5)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Language Selector
                if !accessibleLanguages.isEmpty {
                    Picker("Select Language", selection: $languageManager.selectedLanguage) {
                        ForEach(accessibleLanguages) { language in
                            Text(language.name).tag(language as CustomLanguage?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal)
                    .onChange(of: languageManager.selectedLanguage) {
                        // Ensure selected language is accessible
                        if let selected = languageManager.selectedLanguage,
                           !languageManager.isLanguageAccessible(selected, isPremium: premiumManager.isPremium) {
                            languageManager.selectedLanguage = accessibleLanguages.first
                        }
                    }
                }
                
                // Mode Toggle
                VStack(spacing: 8) {
                    HStack {
                        Text("Mode")
                            .font(.headline)
                        Spacer()
                    }
                    
                    Picker("Translation Mode", selection: $isDecryptMode) {
                        Text("🔒 Encrypt").tag(false)
                        Text("🔓 Decrypt").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: isDecryptMode) {
                        updateTranslation()
                    }
                }
                .padding(.horizontal)
                
                // Input Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(isDecryptMode ? "Encrypted Text" : "Original Text")
                            .font(.headline)
                        Spacer()
                        
                        // Clear button and character count
                        HStack(spacing: 8) {
                            if !currentInputText.isEmpty {
                                Button("Clear") {
                                    if isDecryptMode {
                                        decryptInputText = ""
                                    } else {
                                        encryptInputText = ""
                                    }
                                    updateTranslation()
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                            
                            if !premiumManager.isPremium {
                                Text("\(currentInputText.count)/\(freeCharacterLimit)")
                                    .font(.caption)
                                    .foregroundColor(currentInputText.count > freeCharacterLimit ? .red : .gray)
                            }
                        }
                    }
                    
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: isDecryptMode ? $decryptInputText : $encryptInputText)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(gradientBorder)
                        
                        // Placeholder text
                        if currentInputText.isEmpty {
                            Text(isDecryptMode ? "Enter encrypted text to decrypt here" : "Enter text to be translated here")
                                .foregroundColor(.gray)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: encryptInputText) {
                        if !isDecryptMode {
                            if !premiumManager.isPremium && encryptInputText.count > freeCharacterLimit {
                                encryptInputText = String(encryptInputText.prefix(freeCharacterLimit))
                            }
                            updateTranslation()
                        }
                    }
                    .onChange(of: decryptInputText) {
                        if isDecryptMode {
                            if !premiumManager.isPremium && decryptInputText.count > freeCharacterLimit {
                                decryptInputText = String(decryptInputText.prefix(freeCharacterLimit))
                            }
                            updateTranslation()
                        }
                    }
                }
                .padding(.horizontal)
                
                // Translation Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(isDecryptMode ? "Decrypted Text" : "Translated Text")
                            .font(.headline)
                        Spacer()
                        
                        // Action buttons
                        HStack(spacing: 12) {
                            if premiumManager.isPremium && !translatedText.isEmpty && MFMessageComposeViewController.canSendText() {
                                Button("Send SMS") {
                                    showMessageComposer = true
                                }
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green)
                                .cornerRadius(6)
                            }
                            
                            Button("Copy") {
                                UIPasteboard.general.string = translatedText
                                showCopiedAlert = true
                            }
                            .disabled(translatedText.isEmpty)
                        }
                    }
                    
                    ScrollView {
                        Text(translatedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(translatedTextBackground)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 100)
                    .background(translatedTextBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(translatedTextBorder, lineWidth: 1)
                    )
                }
                .padding(.horizontal)
                
                // Premium Prompt
                if !premiumManager.isPremium {
                    VStack(spacing: 8) {
                        Text("Want longer messages, unlimited languages, number mapping, and SMS sending?")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        
                        Button("Upgrade to Premium") {
                            premiumManager.showPaywall = true
                        }
                        .buttonStyle(PremiumButtonStyle())
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Oobada")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.teal, .green]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        hideKeyboard()
                    }
                    .opacity(isKeyboardVisible ? 1 : 0)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .background(Color.clear) // Let the sky blue background show through
        .alert("Copied!", isPresented: $showCopiedAlert) {
            Button("OK") { }
        }
        .alert("Message Result", isPresented: $showMessageResult) {
            Button("OK") { }
        } message: {
            Text(messageResultText)
        }
        .sheet(isPresented: $showMessageComposer) {
            if MFMessageComposeViewController.canSendText() {
                MessageComposer(
                    isShowing: $showMessageComposer,
                    message: translatedText
                ) { result in
                    handleMessageResult(result)
                }
            }
        }
        .sheet(isPresented: $premiumManager.showPaywall) {
            PaywallView()
        }
        .onTapGesture {
            hideKeyboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PremiumStatusChanged"))) { notification in
            if let isPremium = notification.object as? Bool {
                languageManager.handlePremiumStatusChange(isPremium: isPremium)
            }
        }
    }
    
    private func updateTranslation() {
        guard let language = languageManager.selectedLanguage else {
            translatedText = ""
            return
        }
        
        let inputText = currentInputText
        
        if isDecryptMode {
            translatedText = languageManager.decrypt(text: inputText, using: language, isPremium: premiumManager.isPremium)
        } else {
            translatedText = languageManager.translate(text: inputText, using: language, isPremium: premiumManager.isPremium)
        }
    }
    
    private func handleMessageResult(_ result: MessageComposeResult) {
        switch result {
        case .sent:
            messageResultText = "Message sent successfully! 🎉"
        case .cancelled:
            messageResultText = "Message cancelled"
        case .failed:
            messageResultText = "Failed to send message. Please try again."
        @unknown default:
            messageResultText = "Unknown result"
        }
        showMessageResult = true
    }
    
    @State private var isKeyboardVisible = false
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Language List View
struct LanguageListView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var premiumManager: PremiumManager
    @State private var showImportAlert = false
    @State private var importText = ""
    @State private var showImportResult = false
    @State private var importResultMessage = ""
    
    var body: some View {
        NavigationView {
            List {
                ForEach(languageManager.languages) { language in
                    let isAccessible = languageManager.isLanguageAccessible(language, isPremium: premiumManager.isPremium)
                    let canUseAllFeatures = languageManager.canUseLanguageFeatures(language, isPremium: premiumManager.isPremium)
                    let hasPremiumFeatures = !language.numberMapping.isEmpty
                    
                    if isAccessible {
                        NavigationLink(destination: LanguageDetailView(language: language)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(language.name)
                                        .font(.headline)
                                    Spacer()
                                    
                                    // Show warning if language has premium features but user can't access them
                                    if hasPremiumFeatures && !canUseAllFeatures {
                                        HStack(spacing: 4) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                                .font(.caption)
                                            Image(systemName: "crown.fill")
                                                .foregroundColor(.yellow)
                                                .font(.caption)
                                        }
                                    }
                                }
                                
                                HStack {
                                    Text("\(language.mapping.count) letters")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    if !language.numberMapping.isEmpty {
                                        Text("• \(language.numberMapping.count) numbers")
                                            .font(.caption)
                                            .foregroundColor(canUseAllFeatures ? .gray : .orange)
                                        
                                        if !canUseAllFeatures {
                                            Text("(Premium)")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Button {
                            premiumManager.showPaywall = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(language.name)
                                            .font(.headline)
                                            .foregroundColor(.gray)
                                        Spacer()
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(.teal)
                                            .font(.caption)
                                    }
                                    HStack {
                                        Text("\(language.mapping.count) letters")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        if !language.numberMapping.isEmpty {
                                            Text("• \(language.numberMapping.count) numbers")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        Text("• Premium Required")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .onDelete(perform: deleteLanguages)
                
                if !premiumManager.isPremium && languageManager.languages.count >= 1 {
                    Button("Create More Languages") {
                        premiumManager.showPaywall = true
                    }
                    .foregroundColor(.teal)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("My Languages")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.teal, .green]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Import") {
                        showImportAlert = true
                    }
                    .foregroundColor(.blue)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if premiumManager.isPremium || languageManager.languages.count < 1 {
                        NavigationLink("Add", destination: CreateLanguageView())
                    }
                }
            }
            .alert("Import Language", isPresented: $showImportAlert) {
                TextField("Paste language key here", text: $importText)
                Button("Import") {
                    importLanguage()
                }
                Button("Cancel", role: .cancel) {
                    importText = ""
                }
            } message: {
                Text("Paste the language key you received from someone to import their cipher.")
            }
            .alert("Import Result", isPresented: $showImportResult) {
                Button("OK") { }
            } message: {
                Text(importResultMessage)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func deleteLanguages(offsets: IndexSet) {
        for index in offsets {
            let language = languageManager.languages[index]
            languageManager.deleteLanguage(language)
        }
    }
    
    private func importLanguage() {
        guard !importText.isEmpty else {
            importResultMessage = "Please paste a valid language key."
            showImportResult = true
            return
        }
        
        if let importedLanguage = languageManager.importLanguage(from: importText) {
            languageManager.addLanguage(importedLanguage)
            
            // Check if imported language has premium features
            let hasPremiumFeatures = !importedLanguage.numberMapping.isEmpty
            if hasPremiumFeatures && !premiumManager.isPremium {
                importResultMessage = "Language '\(importedLanguage.name)' imported successfully! 🎉\n\n⚠️ Note: This language contains premium features (number mappings). You can use letters only, or upgrade to Premium to unlock all features."
            } else {
                importResultMessage = "Language '\(importedLanguage.name)' imported successfully! 🎉"
            }
            importText = ""
        } else {
            importResultMessage = "Invalid language key or language already exists."
        }
        showImportResult = true
    }
}

// MARK: - Create Language View
struct CreateLanguageView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var premiumManager: PremiumManager
    @State private var languageName = ""
    @State private var letterMappings: [Character: String] = [:]
    @State private var numberMappings: [Character: String] = [:] // New: for number mappings
    @State private var showSuccessAlert = false
    @State private var showGenerateOptions = false
    @State private var showDuplicateAlert = false
    @State private var duplicateMessage = ""
    @Environment(\.presentationMode) var presentationMode
    
    private let alphabet = "abcdefghijklmnopqrstuvwxyz"
    private let numbers = "0123456789"
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Language Name")) {
                    TextField("Enter language name", text: $languageName)
                }
                
                Section(header:
                    HStack {
                        Text("Letter Mappings")
                        Spacer()
                        HStack(spacing: 8) {
                            Button("Clear All") {
                                letterMappings.removeAll()
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                            
                            Button("Generate for Me") {
                                showGenerateOptions = true
                            }
                            .font(.caption)
                            .foregroundColor(.teal)
                        }
                    }
                ) {
                    ForEach(Array(alphabet), id: \.self) { letter in
                        HStack {
                            Text(letter.uppercased())
                                .font(.headline)
                                .frame(width: 30)
                            
                            Image(systemName: "arrow.right")
                                .foregroundColor(.gray)
                            
                            TextField("Map to...", text: Binding(
                                get: { letterMappings[letter] ?? "" },
                                set: { newValue in
                                    validateAndSetLetterMapping(for: letter, value: newValue)
                                }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                }
                
                // Number Mappings Section (Premium Only)
                if premiumManager.isPremium {
                    Section(header:
                        HStack {
                            Text("Number Mappings")
                            Spacer()
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                            HStack(spacing: 8) {
                                Button("Clear Numbers") {
                                    numberMappings.removeAll()
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                        }
                    ) {
                        ForEach(Array(numbers), id: \.self) { number in
                            HStack {
                                Text(String(number))
                                    .font(.headline)
                                    .frame(width: 30)
                                
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.gray)
                                
                                TextField("Map to...", text: Binding(
                                    get: { numberMappings[number] ?? "" },
                                    set: { newValue in
                                        validateAndSetNumberMapping(for: number, value: newValue)
                                    }
                                ))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                        }
                    }
                }
                
                // Invisible section for tap-to-dismiss
                Section {
                    Color.clear
                        .frame(height: 20)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            hideKeyboard()
                        }
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Create Language")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.teal, .green]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // Clear all mappings
                        languageName = ""
                        letterMappings.removeAll()
                        numberMappings.removeAll()
                        
                        // Dismiss the create view
                        presentationMode.wrappedValue.dismiss()
                        
                        // Switch to Translate tab
                        NotificationCenter.default.post(name: NSNotification.Name("SwitchToTranslateTab"), object: nil)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveLanguage()
                    }
                    .disabled(languageName.isEmpty)
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            hideKeyboard()
                        }
                        .foregroundColor(.teal)
                        .fontWeight(.medium)
                    }
                }
            }
            .actionSheet(isPresented: $showGenerateOptions) {
                ActionSheet(
                    title: Text("Generate Mappings"),
                    message: Text("Choose a style for your language"),
                    buttons: [
                        .default(Text("🔀 Shuffled Letters")) {
                            generateShuffledLetters()
                        },
                        .default(Text("🔢 Letters & Numbers")) {
                            generateNumbers()
                        },
                        .default(Text("😀 Emojis")) {
                            generateEmojis()
                        },
                        .default(Text("⭐ Symbols")) {
                            generateSymbols()
                        },
                        .default(Text("🎯 Mixed Style")) {
                            generateMixedStyle()
                        },
                        .cancel(Text("Cancel"))
                    ]
                )
            }
            .alert("Duplicate Mapping", isPresented: $showDuplicateAlert) {
                Button("OK") { }
            } message: {
                Text(duplicateMessage)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func validateAndSetLetterMapping(for letter: Character, value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If empty, just remove the mapping
        if trimmedValue.isEmpty {
            letterMappings[letter] = nil
            return
        }
        
        // Check for duplicates in letter mappings (case-insensitive)
        for (existingLetter, existingValue) in letterMappings {
            if existingLetter != letter &&
               existingValue.lowercased() == trimmedValue.lowercased() {
                duplicateMessage = "'\(trimmedValue)' is already mapped to '\(existingLetter.uppercased())'. Each cipher character can only be used once."
                showDuplicateAlert = true
                return
            }
        }
        
        // Check for duplicates in number mappings (if premium)
        if premiumManager.isPremium {
            for (existingNumber, existingValue) in numberMappings {
                if existingValue.lowercased() == trimmedValue.lowercased() {
                    duplicateMessage = "'\(trimmedValue)' is already mapped to '\(existingNumber)'. Each cipher character can only be used once."
                    showDuplicateAlert = true
                    return
                }
            }
        }
        
        // If no duplicates, set the mapping
        letterMappings[letter] = trimmedValue
    }
    
    private func validateAndSetNumberMapping(for number: Character, value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If empty, just remove the mapping
        if trimmedValue.isEmpty {
            numberMappings[number] = nil
            return
        }
        
        // Check for duplicates in number mappings
        for (existingNumber, existingValue) in numberMappings {
            if existingNumber != number &&
               existingValue.lowercased() == trimmedValue.lowercased() {
                duplicateMessage = "'\(trimmedValue)' is already mapped to '\(existingNumber)'. Each cipher character can only be used once."
                showDuplicateAlert = true
                return
            }
        }
        
        // Check for duplicates in letter mappings
        for (existingLetter, existingValue) in letterMappings {
            if existingValue.lowercased() == trimmedValue.lowercased() {
                duplicateMessage = "'\(trimmedValue)' is already mapped to '\(existingLetter.uppercased())'. Each cipher character can only be used once."
                showDuplicateAlert = true
                return
            }
        }
        
        // If no duplicates, set the mapping
        numberMappings[number] = trimmedValue
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func saveLanguage() {
        guard !languageName.isEmpty else { return }
        
        if !premiumManager.isPremium && languageManager.languages.count >= 1 {
            premiumManager.showPaywall = true
            return
        }
        
        let newLanguage = CustomLanguage(name: languageName, mapping: letterMappings, numberMapping: numberMappings)
        languageManager.addLanguage(newLanguage)
        languageManager.selectedLanguage = newLanguage
        
        // Dismiss and redirect to Languages tab
        presentationMode.wrappedValue.dismiss()
        
        // Post notification to switch to Languages tab
        NotificationCenter.default.post(name: NSNotification.Name("SwitchToLanguagesTab"), object: nil)
    }
    
    // MARK: - Generation Functions
    private func generateShuffledLetters() {
        letterMappings.removeAll()
        numberMappings.removeAll()
        
        let vowels = ["a", "e", "i", "o", "u"]
        let consonants = ["b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "q", "r", "s", "t", "v", "w", "x", "y", "z"]
        
        // Create derangements (no letter maps to itself)
        let vowelMappings = createDerangement(from: vowels)
        let consonantMappings = createDerangement(from: consonants)
        
        for letter in alphabet {
            if vowels.contains(String(letter)) {
                // Map vowels to deranged vowels
                let vowelIndex = vowels.firstIndex(of: String(letter))!
                letterMappings[letter] = vowelMappings[vowelIndex].uppercased()
            } else {
                // Map consonants to deranged consonants
                let consonantIndex = consonants.firstIndex(of: String(letter))!
                letterMappings[letter] = consonantMappings[consonantIndex].uppercased()
            }
        }
        
        // Generate number mappings if premium
        if premiumManager.isPremium {
            let numberArray = Array(numbers)
            let shuffledNumbers = numberArray.shuffled()
            
            for (index, number) in numberArray.enumerated() {
                // Map each number to a different number
                var mappedNumber = shuffledNumbers[index]
                // Ensure no self-mapping
                var attempts = 0
                while mappedNumber == number && attempts < 10 {
                    numberMappings[number] = String(numberArray.randomElement() ?? number)
                    mappedNumber = Character(numberMappings[number] ?? String(number))
                    attempts += 1
                }
                if mappedNumber != number {
                    numberMappings[number] = String(mappedNumber)
                }
            }
        }
    }
    
    private func generateNumbers() {
        letterMappings.removeAll()
        numberMappings.removeAll()
        
        // Separate vowels and consonants for mapping
        let vowels = ["a", "e", "i", "o", "u"]
        let consonants = ["b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "q", "r", "s", "t", "v", "w", "x", "y", "z"]
        
        // Vowels map to different vowels (no self-mapping)
        let vowelCipherLetters = ["A", "E", "I", "O", "U"]
        let vowelMappings = createDerangement(from: vowelCipherLetters)
        
        // Consonants map to letters Q-Z + numbers 0-9 (10 letters + 10 numbers = 20 characters)
        // Note: Using Q-Z to avoid overlap with vowel mappings A-P
        var consonantPool: [String] = []
        
        // Letters Q-Z (10 letters) - avoiding overlap with vowels A,E,I,O,U
        for i in 81...90 { // Q through Z
            consonantPool.append(String(Character(UnicodeScalar(i)!)))
        }
        
        // Numbers 0-9 (10 numbers)
        for i in 0...9 {
            consonantPool.append(String(i))
        }
        
        // We have 21 consonants but only 20 pool characters
        // Add one more letter from the remaining letters (P is safe since vowels use A,E,I,O,U)
        consonantPool.append("P")
        
        // Shuffle consonant pool (no self-mapping possible since consonants don't map to letters)
        let shuffledConsonantPool = consonantPool.shuffled()
        
        for letter in alphabet {
            if vowels.contains(String(letter)) {
                // Map vowels to deranged vowel letters
                let vowelIndex = vowels.firstIndex(of: String(letter))!
                letterMappings[letter] = vowelMappings[vowelIndex]
            } else {
                // Map consonants to shuffled alphanumeric characters
                let consonantIndex = consonants.firstIndex(of: String(letter))!
                letterMappings[letter] = shuffledConsonantPool[consonantIndex]
            }
        }
        
        // Generate number mappings if premium
        if premiumManager.isPremium {
            // Map numbers to letters not used by letter mappings
            let usedChars = Set(letterMappings.values.map { $0.lowercased() })
            let availableLetters = ["B", "C", "D", "F", "G", "H", "J", "K", "L", "M"]
                .filter { !usedChars.contains($0.lowercased()) }
                .shuffled()
            
            for (index, number) in numbers.enumerated() {
                if index < availableLetters.count {
                    numberMappings[number] = availableLetters[index]
                }
            }
        }
    }
    
    // Create a derangement (permutation where no element appears in its original position)
    private func createDerangement(from array: [String]) -> [String] {
        var result = array.shuffled()
        var attempts = 0
        let maxAttempts = 100
        
        // Keep shuffling until no element is in its original position
        while hasFixedPoints(original: array, permutation: result) && attempts < maxAttempts {
            result = array.shuffled()
            attempts += 1
        }
        
        // If we can't find a perfect derangement, manually fix any remaining fixed points
        if hasFixedPoints(original: array, permutation: result) {
            result = fixFixedPoints(original: array, permutation: result)
        }
        
        return result
    }
    
    // Check if any element is in its original position
    private func hasFixedPoints(original: [String], permutation: [String]) -> Bool {
        for i in 0..<original.count {
            if original[i] == permutation[i] {
                return true
            }
        }
        return false
    }
    
    // Fix any remaining fixed points by swapping
    private func fixFixedPoints(original: [String], permutation: [String]) -> [String] {
        var result = permutation
        
        for i in 0..<original.count {
            if original[i] == result[i] {
                // Find another position to swap with
                for j in 0..<result.count {
                    if i != j && original[j] != result[i] && original[i] != result[j] {
                        // Swap positions i and j
                        let temp = result[i]
                        result[i] = result[j]
                        result[j] = temp
                        break
                    }
                }
            }
        }
        
        return result
    }
    
    private func generateEmojis() {
        // Carefully curated collections with exactly 26 unique emojis each
        let emojiCollections = [
            // Faces - 26 unique face emojis
            ["😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚", "☺️", "😋", "😛", "😝", "😜", "🤪"],
            // Animals - 26 unique animal emojis
            ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🐤", "🐣", "🐥", "🦆", "🦅", "🦉", "🦇", "🐺"],
            // Food - 26 unique food emojis
            ["🍎", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🍆", "🥑", "🥦", "🥒", "🌶️", "🌽", "🥕", "🧄", "🧅", "🥔"],
            // Sports - 26 unique sport/activity emojis
            ["⚽", "🏀", "🏈", "⚾", "🥎", "🎾", "🏐", "🏉", "🎱", "🪀", "🏓", "🏸", "🏑", "🏒", "🥍", "🏏", "🪃", "🥅", "⛳", "🪁", "🏹", "🎣", "🤿", "🥊", "🥋", "🎽"],
            // Objects - 26 unique object emojis
            ["⌚", "📱", "💻", "⌨️", "🖥️", "🖨️", "🖱️", "🖲️", "🕹️", "💽", "💾", "💿", "📀", "📼", "📷", "📸", "📹", "🎥", "📽️", "🎞️", "📞", "☎️", "📟", "📠", "📺", "📻"]
        ]
        
        // Pick a random collection (all guaranteed to have exactly 26 unique emojis)
        let selectedCollection = emojiCollections.randomElement() ?? emojiCollections[0]
        
        // Shuffle the selected collection
        let shuffledEmojis = selectedCollection.shuffled()
        
        letterMappings.removeAll()
        numberMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            letterMappings[letter] = shuffledEmojis[index]
        }
        
        // Generate number mappings if premium
        if premiumManager.isPremium {
            let numberEmojis = ["🔥", "⭐", "💎", "🌟", "✨", "💫", "⚡", "🌈", "☀️", "🌙"]
            let shuffledNumberEmojis = numberEmojis.shuffled()
            
            for (index, number) in numbers.enumerated() {
                numberMappings[number] = shuffledNumberEmojis[index]
            }
        }
    }
    
    private func generateSymbols() {
        // Exactly 26 unique symbols - carefully selected to avoid duplicates
        let symbols = [
            "★", "☆", "♦", "♠", "♥", "♣", "◆", "◇", "◈", "○", "●", "◯", "◉", "△", "▲", "▽", "▼",
            "□", "■", "◦", "‣", "⁂", "※", "‼", "⁇", "⁈"
        ]
        
        // Verify we have exactly 26 symbols, then shuffle
        let shuffledSymbols = symbols.shuffled()
        letterMappings.removeAll()
        numberMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            letterMappings[letter] = shuffledSymbols[index]
        }
        
        // Generate number mappings if premium
        if premiumManager.isPremium {
            let numberSymbols = ["#", "@", "&", "%", "$", "!", "?", "+", "-", "="]
            let shuffledNumberSymbols = numberSymbols.shuffled()
            
            for (index, number) in numbers.enumerated() {
                numberMappings[number] = shuffledNumberSymbols[index]
            }
        }
    }
    
    private func generateMixedStyle() {
        // Create a pool of diverse characters
        let letters = ["A", "B", "C", "D", "E", "F"]  // 6 letters
        let numbers = ["0", "1", "2", "3", "4", "5"]  // 6 numbers
        let symbols = ["★", "♦", "♠", "♥", "◆", "●", "▲", "■", "◦", "△", "◇", "◈", "○", "□"]  // 14 symbols
        
        // Combine all (6 + 6 + 14 = 26 unique characters)
        let allCharacters = letters + numbers + symbols
        
        // Shuffle the combined pool
        let shuffledMix = allCharacters.shuffled()
        letterMappings.removeAll()
        numberMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            letterMappings[letter] = shuffledMix[index]
        }
        
        // Generate number mappings if premium
        if premiumManager.isPremium {
            let mixedNumberChars = ["🎯", "🎲", "🎪", "🎨", "🎭", "🎪", "🎸", "🎵", "🎬", "🎮"]
            let shuffledMixedNumbers = mixedNumberChars.shuffled()
            
            for (index, number) in self.numbers.enumerated() {
                numberMappings[number] = shuffledMixedNumbers[index]
            }
        }
    }
}

// MARK: - Language Detail View
struct LanguageDetailView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var premiumManager: PremiumManager
    let originalLanguage: CustomLanguage
    @State private var isEditing = false
    @State private var tempName: String
    @State private var tempMappings: [Character: String]
    @State private var tempNumberMappings: [Character: String] // New: temp number mappings
    @State private var showGenerateOptions = false
    @State private var showDeleteAlert = false
    @State private var showReshareAlert = false
    @State private var showDuplicateAlert = false
    @State private var duplicateMessage = ""
    @Environment(\.presentationMode) var presentationMode
    
    init(language: CustomLanguage) {
        self.originalLanguage = language
        self._tempName = State(initialValue: language.name)
        self._tempMappings = State(initialValue: language.mapping)
        self._tempNumberMappings = State(initialValue: language.numberMapping)
    }
    
    private let alphabet = "abcdefghijklmnopqrstuvwxyz"
    private let numbers = "0123456789"
    
    // Get the current language from the manager
    private var currentLanguage: CustomLanguage {
        languageManager.languages.first { $0.id == originalLanguage.id } ?? originalLanguage
    }
    
    var body: some View {
        Form {
            Section(header: Text("Language Name")) {
                if isEditing {
                    TextField("Language name", text: $tempName)
                } else {
                    Text(currentLanguage.name)
                }
            }
            
            Section(header:
                HStack {
                    Text("Letter Mappings")
                    Spacer()
                    if isEditing {
                        HStack(spacing: 8) {
                            Button("Clear All") {
                                tempMappings.removeAll()
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                            
                            Button("Generate for Me") {
                                showGenerateOptions = true
                            }
                            .font(.caption)
                            .foregroundColor(.teal) // Changed from .purple
                        }
                    }
                }
            ) {
                ForEach(Array(alphabet), id: \.self) { letter in
                    HStack {
                        Text(letter.uppercased())
                            .font(.headline)
                            .frame(width: 30)
                        
                        Image(systemName: "arrow.right")
                            .foregroundColor(.gray)
                        
                        if isEditing {
                            TextField("Map to...", text: Binding(
                                get: { tempMappings[letter] ?? "" },
                                set: { newValue in
                                    validateAndSetLetterMapping(for: letter, value: newValue)
                                }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            Text(currentLanguage.mapping[letter] ?? "Not set")
                                .foregroundColor(currentLanguage.mapping[letter] == nil ? .gray : .primary)
                        }
                    }
                }
            }
            
            // Number Mappings Section (Premium Only)
            if premiumManager.isPremium {
                Section(header:
                    HStack {
                        Text("Number Mappings")
                        Spacer()
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        if isEditing {
                            Button("Clear Numbers") {
                                tempNumberMappings.removeAll()
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                    }
                ) {
                    ForEach(Array(numbers), id: \.self) { number in
                        HStack {
                            Text(String(number))
                                .font(.headline)
                                .frame(width: 30)
                            
                            Image(systemName: "arrow.right")
                                .foregroundColor(.gray)
                            
                            if isEditing {
                                TextField("Map to...", text: Binding(
                                    get: { tempNumberMappings[number] ?? "" },
                                    set: { newValue in
                                        validateAndSetNumberMapping(for: number, value: newValue)
                                    }
                                ))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            } else {
                                Text(currentLanguage.numberMapping[number] ?? "Not set")
                                    .foregroundColor(currentLanguage.numberMapping[number] == nil ? .gray : .primary)
                            }
                        }
                    }
                }
            }
            
            // Delete Section
            Section {
                Button("Delete Language") {
                    showDeleteAlert = true
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            // Invisible section for tap-to-dismiss (only when editing)
            if isEditing {
                Section {
                    Color.clear
                        .frame(height: 30)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            hideKeyboard()
                        }
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Language Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Share") {
                    shareLanguage()
                }
                .foregroundColor(.blue)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                if isEditing {
                    Button("Save") {
                        saveChanges()
                    }
                } else {
                    Button("Edit") {
                        startEditing()
                    }
                }
            }
            
            if isEditing {
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            hideKeyboard()
                        }
                        .foregroundColor(.teal) // Changed from .purple
                        .fontWeight(.medium)
                    }
                }
            }
        }
        .actionSheet(isPresented: $showGenerateOptions) {
            ActionSheet(
                title: Text("Generate Mappings"),
                message: Text("Choose a style for your language"),
                buttons: [
                    .default(Text("🔀 Shuffled Letters")) {
                        generateShuffledLetters()
                    },
                    .default(Text("🔢 Numbers")) {
                        generateNumbers()
                    },
                    .default(Text("😀 Emojis")) {
                        generateEmojis()
                    },
                    .default(Text("⭐ Symbols")) {
                        generateSymbols()
                    },
                    .default(Text("🎯 Mixed Style")) {
                        generateMixedStyle()
                    },
                    .cancel(Text("Cancel"))
                ]
            )
        }
        .alert("Delete Language", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteLanguage()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete '\(currentLanguage.name)'? This action cannot be undone.")
        }
        .alert("Language Updated", isPresented: $showReshareAlert) {
            Button("OK") { }
        } message: {
            Text("⚠️ Important: You've changed this language. If you've shared it with others, you'll need to share the updated version for them to decrypt your new messages correctly.")
        }
        .alert("Duplicate Mapping", isPresented: $showDuplicateAlert) {
            Button("OK") { }
        } message: {
            Text(duplicateMessage)
        }
    }
    
    private func validateAndSetLetterMapping(for letter: Character, value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If empty, just remove the mapping
        if trimmedValue.isEmpty {
            tempMappings[letter] = nil
            return
        }
        
        // Check for duplicates in letter mappings (case-insensitive)
        for (existingLetter, existingValue) in tempMappings {
            if existingLetter != letter &&
               existingValue.lowercased() == trimmedValue.lowercased() {
                duplicateMessage = "'\(trimmedValue)' is already mapped to '\(existingLetter.uppercased())'. Each cipher character can only be used once."
                showDuplicateAlert = true
                return
            }
        }
        
        // Check for duplicates in number mappings (if premium)
        if premiumManager.isPremium {
            for (existingNumber, existingValue) in tempNumberMappings {
                if existingValue.lowercased() == trimmedValue.lowercased() {
                    duplicateMessage = "'\(trimmedValue)' is already mapped to '\(existingNumber)'. Each cipher character can only be used once."
                    showDuplicateAlert = true
                    return
                }
            }
        }
        
        // If no duplicates, set the mapping
        tempMappings[letter] = trimmedValue
    }
    
    private func validateAndSetNumberMapping(for number: Character, value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If empty, just remove the mapping
        if trimmedValue.isEmpty {
            tempNumberMappings[number] = nil
            return
        }
        
        // Check for duplicates in number mappings
        for (existingNumber, existingValue) in tempNumberMappings {
            if existingNumber != number &&
               existingValue.lowercased() == trimmedValue.lowercased() {
                duplicateMessage = "'\(trimmedValue)' is already mapped to '\(existingNumber)'. Each cipher character can only be used once."
                showDuplicateAlert = true
                return
            }
        }
        
        // Check for duplicates in letter mappings
        for (existingLetter, existingValue) in tempMappings {
            if existingValue.lowercased() == trimmedValue.lowercased() {
                duplicateMessage = "'\(trimmedValue)' is already mapped to '\(existingLetter.uppercased())'. Each cipher character can only be used once."
                showDuplicateAlert = true
                return
            }
        }
        
        // If no duplicates, set the mapping
        tempNumberMappings[number] = trimmedValue
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func shareLanguage() {
        let exportedString = languageManager.exportLanguage(currentLanguage)
        let activityVC = UIActivityViewController(activityItems: [exportedString], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
    
    private func startEditing() {
        // Reset temp values to current language state when starting to edit
        tempName = currentLanguage.name
        tempMappings = currentLanguage.mapping
        tempNumberMappings = currentLanguage.numberMapping
        isEditing = true
    }
    
    private func saveChanges() {
        // Check if anything actually changed
        let hasChanges = tempName != currentLanguage.name ||
                        tempMappings != currentLanguage.mapping ||
                        tempNumberMappings != currentLanguage.numberMapping
        
        var updatedLanguage = currentLanguage
        updatedLanguage.name = tempName
        updatedLanguage.mapping = tempMappings
        updatedLanguage.numberMapping = tempNumberMappings
        languageManager.updateLanguage(updatedLanguage)
        isEditing = false
        
        // Show reshare alert if there were changes
        if hasChanges {
            showReshareAlert = true
        }
    }
    
    private func deleteLanguage() {
        languageManager.deleteLanguage(currentLanguage)
        presentationMode.wrappedValue.dismiss()
    }
    
    // MARK: - Generation Functions
    private func generateShuffledLetters() {
        let shuffledAlphabet = Array(alphabet).shuffled()
        tempMappings.removeAll()
        tempNumberMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            tempMappings[letter] = String(shuffledAlphabet[index]).uppercased()
        }
        
        // Generate number mappings if premium
        if premiumManager.isPremium {
            let numberArray = Array(numbers)
            let shuffledNumbers = numberArray.shuffled()
            
            for (index, number) in numberArray.enumerated() {
                var mappedNumber = shuffledNumbers[index]
                // Ensure no self-mapping
                var attempts = 0
                while mappedNumber == number && attempts < 10 {
                    mappedNumber = numberArray.randomElement() ?? number
                    attempts += 1
                }
                if mappedNumber != number {
                    tempNumberMappings[number] = String(mappedNumber)
                }
            }
        }
    }
    
    private func generateNumbers() {
        tempMappings.removeAll()
        tempNumberMappings.removeAll()
        
        // Create 26 unique alphanumeric combinations
        var alphanumeric: [String] = []
        
        // Letters A-P (16 letters)
        for i in 65...80 {
            alphanumeric.append(String(Character(UnicodeScalar(i)!)))
        }
        
        // Numbers 0-9 (10 numbers)
        for i in 0...9 {
            alphanumeric.append(String(i))
        }
        
        // Total: 16 letters + 10 numbers = 26 unique characters
        // Shuffle to randomize assignment
        alphanumeric.shuffle()
        
        for (index, letter) in alphabet.enumerated() {
            tempMappings[letter] = alphanumeric[index]
        }
        
        // Generate number mappings if premium
        if premiumManager.isPremium {
            let availableLetters = ["Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
            let shuffledLetters = availableLetters.shuffled()
            
            for (index, number) in numbers.enumerated() {
                if index < shuffledLetters.count {
                    tempNumberMappings[number] = shuffledLetters[index]
                }
            }
        }
    }
    
    private func generateEmojis() {
        let emojiCollections = [
            ["😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚", "☺️", "😋", "😛", "😝", "😜", "🤪"],
            ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🐤", "🐣", "🐥", "🦆", "🦅", "🦉", "🦇", "🐺"],
            ["🍎", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🍆", "🥑", "🥦", "🥒", "🌶️", "🌽", "🥕", "🥔", "🍠", "🥖", "🥨"],
            ["⚽", "🏀", "🏈", "⚾", "🎾", "🏐", "🏉", "🎱", "🏓", "🏸", "🏑", "🏒", "🥍", "🏏", "⛳", "🏹", "🎣", "🥊", "🥋", "🎽", "⛷️", "🏂", "🏄", "🚣", "🏊", "⛹️"],
            ["🌟", "⭐", "✨", "💫", "⚡", "🔥", "💥", "💢", "💨", "💤", "💦", "💧", "🌈", "☀️", "🌤️", "⛅", "🌦️", "🌧️", "⛈️", "🌩️", "🌨️", "❄️", "☃️", "⛄", "🌬️", "💨"]
        ]
        
        // Pick a random collection and shuffle it
        let selectedCollection = emojiCollections.randomElement() ?? emojiCollections[0]
        let shuffledEmojis = selectedCollection.shuffled()
        
        tempMappings.removeAll()
        tempNumberMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            tempMappings[letter] = shuffledEmojis[index]
        }
        
        // Generate number mappings if premium
        if premiumManager.isPremium {
            let numberEmojis = ["🔥", "⭐", "💎", "🌟", "✨", "💫", "⚡", "🌈", "☀️", "🌙"]
            let shuffledNumberEmojis = numberEmojis.shuffled()
            
            for (index, number) in numbers.enumerated() {
                tempNumberMappings[number] = shuffledNumberEmojis[index]
            }
        }
    }
    
    private func generateSymbols() {
        let symbols = [
            "★", "☆", "♦", "♠", "♥", "♣", "◆", "◇", "◈", "○", "●", "◯", "◉", "△", "▲", "▽", "▼",
            "□", "■", "◦", "‣", "⁂", "※", "‼", "⁇", "⁈"
        ]
        
        let shuffledSymbols = symbols.shuffled()
        tempMappings.removeAll()
        tempNumberMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            tempMappings[letter] = shuffledSymbols[index]
        }
        
        // Generate number mappings if premium
        if premiumManager.isPremium {
            let numberSymbols = ["#", "@", "&", "%", "$", "!", "?", "+", "-", "="]
            let shuffledNumberSymbols = numberSymbols.shuffled()
            
            for (index, number) in numbers.enumerated() {
                tempNumberMappings[number] = shuffledNumberSymbols[index]
            }
        }
    }
    
    private func generateMixedStyle() {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
        let numbers = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        let symbols = ["★", "♦", "♠", "♥", "◆", "●"]
        let emojis = ["😊", "🔥", "⭐", "💎"]
        
        let allCharacters = letters + numbers + symbols + emojis
        let shuffledMix = allCharacters.shuffled()
        tempMappings.removeAll()
        tempNumberMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            tempMappings[letter] = shuffledMix[index]
        }
        
        // Generate number mappings if premium
        if premiumManager.isPremium {
            let mixedNumberChars = ["🎯", "🎲", "🎪", "🎨", "🎭", "🎸", "🎵", "🎬", "🎮", "🚀"]
            let shuffledMixedNumbers = mixedNumberChars.shuffled()
            
            for (index, number) in self.numbers.enumerated() {
                tempNumberMappings[number] = shuffledMixedNumbers[index]
            }
        }
    }
}

// MARK: - How To View
struct HowToView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var premiumManager: PremiumManager
    @State private var selectedStep: Int? = nil
    
    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 20) {
                    // Hero Section
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: [.teal.opacity(0.8), .green.opacity(0.6)]), // Changed from [.purple.opacity(0.8), .blue.opacity(0.6)]
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "sparkles")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 8) {
                            Text("Welcome to Oobada!")
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            Text("Create secret languages and share encrypted messages with friends")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                    
                    // Quick Start Cards
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Quick Start Guide")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        
                        VStack(spacing: 12) {
                            StepCard(
                                stepNumber: 1,
                                icon: "plus.circle.fill",
                                iconColor: .green,
                                title: "Create Your Language",
                                description: "Design your cipher with custom mappings",
                                isExpanded: selectedStep == 1,
                                steps: [
                                    "Navigate to the 'Create' tab",
                                    "Enter a unique name for your language",
                                    "Map each letter A-Z to new characters",
                                    premiumManager.isPremium ? "Map numbers 0-9 to characters (Premium)" : "Upgrade to Premium to map numbers 0-9",
                                    "Use 'Generate for Me' for instant creation",
                                    "Save your masterpiece"
                                ]
                            ) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedStep = selectedStep == 1 ? nil : 1
                                }
                            }
                            
                            StepCard(
                                stepNumber: 2,
                                icon: "square.and.arrow.up.fill",
                                iconColor: .teal, // Changed from .purple
                                title: "Share Language Key",
                                description: "Let friends decrypt your messages",
                                isExpanded: selectedStep == 2,
                                steps: [
                                    "Open 'Languages' tab",
                                    "Tap your language name",
                                    "Hit 'Share' in top-left corner",
                                    "Send via text, email, or AirDrop"
                                ]
                            ) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedStep = selectedStep == 2 ? nil : 2
                                }
                            }
                            
                            StepCard(
                                stepNumber: 3,
                                icon: "square.and.arrow.down.fill",
                                iconColor: .orange,
                                title: "Import Friend's Key",
                                description: "Add languages shared with you",
                                isExpanded: selectedStep == 3,
                                steps: [
                                    "Visit the 'Languages' tab",
                                    "Tap 'Import' button",
                                    "Paste the received language key",
                                    "Confirm import - it's now ready!"
                                ]
                            ) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedStep = selectedStep == 3 ? nil : 3
                                }
                            }
                            
                            StepCard(
                                stepNumber: 4,
                                icon: "lock.fill",
                                iconColor: .blue,
                                title: "Encrypt Messages",
                                description: "Transform text into secret code",
                                isExpanded: selectedStep == 4,
                                steps: [
                                    "Go to the 'Translate' tab",
                                    "Select your language from dropdown",
                                    "Choose '🔒 Encrypt' mode",
                                    "Type your secret message (letters and numbers!)",
                                    "Copy the encrypted result"
                                ]
                            ) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedStep = selectedStep == 4 ? nil : 4
                                }
                            }
                            
                            StepCard(
                                stepNumber: 5,
                                icon: "lock.open.fill",
                                iconColor: .green,
                                title: "Decrypt Messages",
                                description: "Reveal hidden messages",
                                isExpanded: selectedStep == 5,
                                steps: [
                                    "Return to 'Translate' tab",
                                    "Select the matching language",
                                    "Switch to '🔓 Decrypt' mode",
                                    "Paste encrypted message",
                                    "Read the revealed secret!"
                                ]
                            ) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedStep = selectedStep == 5 ? nil : 5
                                }
                            }
                        }
                    }
                    
                    // Pro Tips Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                                .font(.title3)
                            Text("Pro Tips")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        
                        LazyVStack(spacing: 8) {
                            ProTipRow(
                                icon: "wand.and.stars",
                                tip: "Use 'Generate for Me' for instant, creative language styles"
                            )
                            ProTipRow(
                                icon: "arrow.triangle.2.circlepath",
                                tip: "Both users need the same language key to communicate"
                            )
                            ProTipRow(
                                icon: "crown.fill",
                                tip: "Premium unlocks unlimited languages, number mapping, and SMS sending"
                            )
                            ProTipRow(
                                icon: "123.rectangle",
                                tip: "Premium users can map numbers 0-9 to any characters (e.g., 3 → L)"
                            )
                            ProTipRow(
                                icon: "exclamationmark.triangle.fill",
                                tip: "Reshare updated languages after making changes"
                            )
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 10)
                    
                    // Example Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                            Text("Examples")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        
                        VStack(spacing: 16) {
                            ExampleCard(
                                title: "Simple Letter Mapping",
                                mapping: "H→C, E→A, Y→T",
                                original: "HEY",
                                encrypted: "CAT"
                            )
                            .padding(.horizontal, 20)
                            
                            if premiumManager.isPremium {
                                ExampleCard(
                                    title: "Premium: Letters + Numbers",
                                    mapping: "A→🔥, R→4, O→$, N→♠, 3→L, 0→X",
                                    original: "AARON30",
                                    encrypted: "🔥🔥4$♠LX"
                                )
                                .padding(.horizontal, 20)
                            } else {
                                Button {
                                    premiumManager.showPaywall = true
                                } label: {
                                    VStack(spacing: 12) {
                                        HStack {
                                            Image(systemName: "crown.fill")
                                                .foregroundColor(.yellow)
                                            Text("Premium Feature")
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                            Spacer()
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Number Mapping Example:")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            
                                            Text("Map: A→🔥, R→4, 3→L, 0→X")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(.teal)
                                            
                                            Text("AARON30 → 🔥🔥4$♠LX")
                                                .font(.system(.caption, design: .monospaced))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.green.opacity(0.1))
                                                .cornerRadius(6)
                                        }
                                        
                                        Text("Tap to unlock number mapping!")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.secondarySystemBackground))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.yellow.opacity(0.3), lineWidth: 2)
                                            )
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.horizontal, 20)
                            }
                            
                            ExampleCard(
                                title: "Complex: Emojis & Symbols",
                                mapping: "H→😊, I→★, space→•",
                                original: "HI THERE",
                                encrypted: "😊★•⭐😊4🔥"
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - Step Card Component
struct StepCard: View {
    let stepNumber: Int
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isExpanded: Bool
    let steps: [String]
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 16) {
                    // Step number badge
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 50, height: 50)
                        
                        VStack(spacing: 2) {
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(iconColor)
                            
                            Text("\(stepNumber)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(iconColor)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(20)
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .padding(.horizontal, 20)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(iconColor.opacity(0.2))
                                        .frame(width: 24, height: 24)
                                    
                                    Text("\(index + 1)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(iconColor)
                                }
                                
                                Text(step)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(iconColor.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Pro Tip Row
struct ProTipRow: View {
    let icon: String
    let tip: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.teal) // Changed from .purple
                .frame(width: 20)
            
            Text(tip)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Example Card
struct ExampleCard: View {
    let title: String
    let mapping: String
    let original: String
    let encrypted: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mapping:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text(mapping)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.teal) // Changed from .purple
                    Spacer()
                }
                
                HStack {
                    Text("Original:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text(original)
                        .font(.system(.subheadline, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    Spacer()
                }
                
                HStack {
                    Text("Encrypted:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text(encrypted)
                        .font(.system(.subheadline, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Helper Views
struct InstructionSection: View {
    let icon: String
    let iconColor: Color
    let title: String
    let steps: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.title2)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(steps, id: \.self) { step in
                    HStack(alignment: .top, spacing: 8) {
                        if step.hasPrefix("  •") {
                            Text("    •")
                                .foregroundColor(.secondary)
                        } else if !step.contains(":") {
                            Text("•")
                                .foregroundColor(.secondary)
                        } else {
                            Text("")
                        }
                        
                        Text(step.replacingOccurrences(of: "  • ", with: ""))
                            .font(.body)
                    }
                }
            }
            .padding(.leading, 8)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

struct TipRow: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("💡")
                .font(.caption)
            Text(text)
                .font(.body)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var premiumManager: PremiumManager
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Appearance")) {
                    HStack {
                        Image(systemName: themeManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                            .foregroundColor(themeManager.isDarkMode ? .blue : .orange)
                        Text("Dark Mode")
                        Spacer()
                        Toggle("", isOn: $themeManager.isDarkMode)
                            .onChange(of: themeManager.isDarkMode) {
                                themeManager.saveDarkModePreference()
                            }
                    }
                }
                
                Section(header: Text("Premium")) {
                    if premiumManager.isPremium {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Premium Active")
                        }
                        
                        Button("Disable Premium (Testing)") {
                            premiumManager.isPremium = false
                        }
                        .foregroundColor(.red)
                    } else {
                        Button("Upgrade to Premium") {
                            premiumManager.showPaywall = true
                        }
                        .foregroundColor(.teal)
                        
                        Button("Enable Premium (Testing)") {
                            premiumManager.isPremium = true
                        }
                        .foregroundColor(.green)
                    }
                    
                    Button("Restore Purchases") {
                        premiumManager.restorePurchases()
                    }
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                    
                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.teal, .green]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}


// MARK: - Paywall View
struct PaywallView: View {
    @EnvironmentObject var premiumManager: PremiumManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    VStack(spacing: 10) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.yellow)
                        
                        Text("Unlock Premium")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Get unlimited languages and features")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    VStack(alignment: .leading, spacing: 20) {
                        FeatureRow(icon: "infinity", title: "Unlimited Languages", description: "Create as many secret languages as you want")
                        FeatureRow(icon: "textformat.size.larger", title: "Longer Messages", description: "Translate up to 500+ characters at once")
                        FeatureRow(icon: "123.rectangle", title: "Number Mapping", description: "Map numbers 0-9 to any characters (e.g., 3 → L)")
                        FeatureRow(icon: "message.fill", title: "Send SMS", description: "Send translated messages directly via text message")
                        FeatureRow(icon: "face.smiling", title: "Emoji Mode", description: "Use emojis and special characters in your codes")
                        FeatureRow(icon: "wand.and.stars", title: "Advanced Generation", description: "More generation styles and customization options")
                    }
                    .padding(.horizontal, 20)
                    
                    VStack(spacing: 15) {
                        Button("Start Free Trial") {
                            premiumManager.purchasePremium()
                        }
                        .buttonStyle(PremiumButtonStyle())
                        
                        Text("$1.99/month or $9.99/year")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text("Cancel anytime")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.teal) // Changed from .purple
                .frame(width: 30, height: 30, alignment: .top)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Premium Button Style
struct PremiumButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [.teal, .green]), // Changed from [.purple, .blue]
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Adaptive Layout Extensions
struct DeviceSize {
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    static var isCompact: Bool {
        UIScreen.main.bounds.width < 400
    }
}
