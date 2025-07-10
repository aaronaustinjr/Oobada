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
    var createdDate: Date
    
    init(name: String, mapping: [Character: String] = [:]) {
        self.id = UUID()
        self.name = name
        self.mapping = mapping
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
        case id, name, mapping, createdDate
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
            // For free users, only return the first language
            return Array(languages.prefix(1))
        }
    }
    
    func isLanguageAccessible(_ language: CustomLanguage, isPremium: Bool) -> Bool {
        if isPremium {
            return true
        } else {
            // Free users can only access their first language
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
    
    func translate(text: String, using language: CustomLanguage) -> String {
        var result = ""
        for character in text {
            let lowerChar = Character(character.lowercased())
            if let mapped = language.mapping[lowerChar] {
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
    
    func decrypt(text: String, using language: CustomLanguage) -> String {
        var result = ""
        let reverseMapping = createReverseMapping(from: language.mapping)
        
        var i = text.startIndex
        while i < text.endIndex {
            var found = false
            
            // Try to find the longest matching cipher text
            for length in stride(from: 3, through: 1, by: -1) {
                let endIndex = text.index(i, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
                let substring = String(text[i..<endIndex])
                
                // Try exact match first
                if let originalChar = reverseMapping[substring] {
                    result += originalChar
                    i = endIndex
                    found = true
                    break
                }
                
                // Try case-insensitive match
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
    @Published var isDarkMode: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let darkModeKey = "DarkModeEnabled"
    
    init() {
        isDarkMode = userDefaults.bool(forKey: darkModeKey)
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
    
    var body: some View {
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
        .accentColor(.purple)
        .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
        .onAppear {
            setupTabBarAppearance()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToLanguagesTab"))) { _ in
            selectedTab = 1
        }
        .sheet(isPresented: $premiumManager.showPaywall) {
            PaywallView()
        }
    }
    
    private func setupTabBarAppearance() {
        let tabBarAppearance = UITabBarAppearance()
        
        // Configure for different states
        tabBarAppearance.configureWithOpaqueBackground()
        
        // Set background color based on theme
        if themeManager.isDarkMode {
            tabBarAppearance.backgroundColor = UIColor.systemGray6
        } else {
            tabBarAppearance.backgroundColor = UIColor.systemBackground
        }
        
        // Add subtle shadow
        tabBarAppearance.shadowColor = UIColor.systemGray4
        
        // Selected item color
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor.systemPurple
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor.systemPurple
        ]
        
        // Normal item color
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor.systemGray
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.systemGray
        ]
        
        // Apply to all tab bar states
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        
        // Add subtle border
        UITabBar.appearance().layer.borderWidth = 0.5
        UITabBar.appearance().layer.borderColor = UIColor.systemGray4.cgColor
    }
}

// MARK: - Translate View
struct TranslateView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var premiumManager: PremiumManager
    @State private var inputText = ""
    @State private var translatedText = ""
    @State private var showCopiedAlert = false
    @State private var showMessageComposer = false
    @State private var showMessageResult = false
    @State private var messageResultText = ""
    @State private var isDecryptMode = false
    
    private let freeCharacterLimit = 100
    
    var accessibleLanguages: [CustomLanguage] {
        languageManager.getAccessibleLanguages(isPremium: premiumManager.isPremium)
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
                            if !inputText.isEmpty {
                                Button("Clear") {
                                    inputText = ""
                                    updateTranslation()
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                            
                            if !premiumManager.isPremium {
                                Text("\(inputText.count)/\(freeCharacterLimit)")
                                    .font(.caption)
                                    .foregroundColor(inputText.count > freeCharacterLimit ? .red : .gray)
                            }
                        }
                    }
                    
                    TextEditor(text: $inputText)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            // Placeholder text
                            Group {
                                if inputText.isEmpty {
                                    Text(isDecryptMode ? "Enter encrypted text to decrypt here" : "Enter text to be translated here")
                                        .foregroundColor(.gray)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                }
                            }
                        )
                        .onChange(of: inputText) {
                            if !premiumManager.isPremium && inputText.count > freeCharacterLimit {
                                inputText = String(inputText.prefix(freeCharacterLimit))
                            }
                            updateTranslation()
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
                            .padding(8)
                            .background(isDecryptMode ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                            .cornerRadius(8)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 100)
                }
                .padding(.horizontal)
                
                // Premium Prompt
                if !premiumManager.isPremium {
                    VStack(spacing: 8) {
                        Text("Want longer messages, unlimited languages, and SMS sending?")
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
            .navigationTitle("Oobada")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        hideKeyboard()
                    }
                    .opacity(isKeyboardVisible ? 1 : 0)
                }
            }
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
            .onTapGesture {
                hideKeyboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PremiumStatusChanged"))) { notification in
                if let isPremium = notification.object as? Bool {
                    languageManager.handlePremiumStatusChange(isPremium: isPremium)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func updateTranslation() {
        guard let language = languageManager.selectedLanguage else {
            translatedText = ""
            return
        }
        
        if isDecryptMode {
            translatedText = languageManager.decrypt(text: inputText, using: language)
        } else {
            translatedText = languageManager.translate(text: inputText, using: language)
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
                    
                    if isAccessible {
                        NavigationLink(destination: LanguageDetailView(language: language)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(language.name)
                                    .font(.headline)
                                Text("\(language.mapping.count) letters mapped")
                                    .font(.caption)
                                    .foregroundColor(.gray)
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
                                            .foregroundColor(.purple)
                                            .font(.caption)
                                    }
                                    Text("\(language.mapping.count) letters mapped • Premium Required")
                                        .font(.caption)
                                        .foregroundColor(.gray)
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
                    .foregroundColor(.purple)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("My Languages")
            .toolbar {
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
            importResultMessage = "Language '\(importedLanguage.name)' imported successfully! 🎉"
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
    @State private var showSuccessAlert = false
    @State private var showGenerateOptions = false
    @State private var showDuplicateAlert = false
    @State private var duplicateMessage = ""
    @Environment(\.presentationMode) var presentationMode
    
    private let alphabet = "abcdefghijklmnopqrstuvwxyz"
    
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
                        Button("Generate for Me") {
                            showGenerateOptions = true
                        }
                        .font(.caption)
                        .foregroundColor(.purple)
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
                                    validateAndSetMapping(for: letter, value: newValue)
                                }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
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
            .navigationTitle("Create Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
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
                        .foregroundColor(.purple)
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
            .alert("Duplicate Mapping", isPresented: $showDuplicateAlert) {
                Button("OK") { }
            } message: {
                Text(duplicateMessage)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func validateAndSetMapping(for letter: Character, value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If empty, just remove the mapping
        if trimmedValue.isEmpty {
            letterMappings[letter] = nil
            return
        }
        
        // Check for duplicates (case-insensitive)
        for (existingLetter, existingValue) in letterMappings {
            if existingLetter != letter &&
               existingValue.lowercased() == trimmedValue.lowercased() {
                duplicateMessage = "'\(trimmedValue)' is already mapped to '\(existingLetter.uppercased())'. Each cipher character can only be used once."
                showDuplicateAlert = true
                return
            }
        }
        
        // If no duplicates, set the mapping
        letterMappings[letter] = trimmedValue
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
        
        let newLanguage = CustomLanguage(name: languageName, mapping: letterMappings)
        languageManager.addLanguage(newLanguage)
        languageManager.selectedLanguage = newLanguage
        
        // Dismiss and redirect to Languages tab
        presentationMode.wrappedValue.dismiss()
        
        // Post notification to switch to Languages tab
        NotificationCenter.default.post(name: NSNotification.Name("SwitchToLanguagesTab"), object: nil)
    }
    
    // MARK: - Generation Functions
    private func generateShuffledLetters() {
        let shuffledAlphabet = Array(alphabet).shuffled()
        letterMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            letterMappings[letter] = String(shuffledAlphabet[index]).uppercased()
        }
    }
    
    private func generateNumbers() {
        letterMappings.removeAll()
        
        // Create 26 unique number combinations
        var numbers: [String] = []
        
        // Single digits 0-9 (10 numbers)
        for i in 0...9 {
            numbers.append(String(i))
        }
        
        // Two-digit numbers 10-25 (16 more numbers)
        for i in 10...25 {
            numbers.append(String(i))
        }
        
        // Shuffle to randomize assignment
        numbers.shuffle()
        
        for (index, letter) in alphabet.enumerated() {
            letterMappings[letter] = numbers[index]
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
        
        letterMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            letterMappings[letter] = shuffledEmojis[index]
        }
    }
    
    private func generateSymbols() {
        let symbols = [
            "★", "☆", "♦", "♠", "♥", "♣", "◆", "◇", "◈", "○", "●", "◯", "◉", "△", "▲", "▽", "▼",
            "□", "■", "◦", "‣", "⁂", "※", "‼", "⁇", "⁈"
        ]
        
        let shuffledSymbols = symbols.shuffled()
        letterMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            letterMappings[letter] = shuffledSymbols[index]
        }
    }
    
    private func generateMixedStyle() {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
        let numbers = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        let symbols = ["★", "♦", "♠", "♥", "◆", "●"]
        let emojis = ["😊", "🔥", "⭐", "💎"]
        
        let allCharacters = letters + numbers + symbols + emojis
        let shuffledMix = allCharacters.shuffled()
        letterMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            letterMappings[letter] = shuffledMix[index]
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
    }
    
    private let alphabet = "abcdefghijklmnopqrstuvwxyz"
    
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
                        Button("Generate for Me") {
                            showGenerateOptions = true
                        }
                        .font(.caption)
                        .foregroundColor(.purple)
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
                                    validateAndSetMapping(for: letter, value: newValue)
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
                        .foregroundColor(.purple)
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
    
    private func validateAndSetMapping(for letter: Character, value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If empty, just remove the mapping
        if trimmedValue.isEmpty {
            tempMappings[letter] = nil
            return
        }
        
        // Check for duplicates (case-insensitive)
        for (existingLetter, existingValue) in tempMappings {
            if existingLetter != letter &&
               existingValue.lowercased() == trimmedValue.lowercased() {
                duplicateMessage = "'\(trimmedValue)' is already mapped to '\(existingLetter.uppercased())'. Each cipher character can only be used once."
                showDuplicateAlert = true
                return
            }
        }
        
        // If no duplicates, set the mapping
        tempMappings[letter] = trimmedValue
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
        isEditing = true
    }
    
    private func saveChanges() {
        // Check if anything actually changed
        let hasChanges = tempName != currentLanguage.name || tempMappings != currentLanguage.mapping
        
        var updatedLanguage = currentLanguage
        updatedLanguage.name = tempName
        updatedLanguage.mapping = tempMappings
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
        
        for (index, letter) in alphabet.enumerated() {
            tempMappings[letter] = String(shuffledAlphabet[index]).uppercased()
        }
    }
    
    private func generateNumbers() {
        tempMappings.removeAll()
        
        // Create 26 unique number combinations
        var numbers: [String] = []
        
        // Single digits 0-9 (10 numbers)
        for i in 0...9 {
            numbers.append(String(i))
        }
        
        // Two-digit numbers 10-25 (16 more numbers)
        for i in 10...25 {
            numbers.append(String(i))
        }
        
        // Shuffle to randomize assignment
        numbers.shuffle()
        
        for (index, letter) in alphabet.enumerated() {
            tempMappings[letter] = numbers[index]
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
        
        for (index, letter) in alphabet.enumerated() {
            tempMappings[letter] = shuffledEmojis[index]
        }
    }
    
    private func generateSymbols() {
        let symbols = [
            "★", "☆", "♦", "♠", "♥", "♣", "◆", "◇", "◈", "○", "●", "◯", "◉", "△", "▲", "▽", "▼",
            "□", "■", "◦", "‣", "⁂", "※", "‼", "⁇", "⁈"
        ]
        
        let shuffledSymbols = symbols.shuffled()
        tempMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            tempMappings[letter] = shuffledSymbols[index]
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
        
        for (index, letter) in alphabet.enumerated() {
            tempMappings[letter] = shuffledMix[index]
        }
    }
}

// MARK: - How To View
struct HowToView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Welcome Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "hand.wave.fill")
                                .foregroundColor(.yellow)
                                .font(.title2)
                            Text("Welcome to Oobada!")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        Text("Create your own secret languages and share encrypted messages with friends! Here's how to get started:")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    // Step-by-step guides
                    InstructionSection(
                        icon: "plus.circle.fill",
                        iconColor: .green,
                        title: "1. Create Your First Language",
                        steps: [
                            "Go to the 'Create' tab",
                            "Enter a name for your language (e.g., 'Secret Code')",
                            "Map each letter A-Z to something new:",
                            "  • Manually: Type custom characters for each letter",
                            "  • Automatically: Tap 'Generate for Me' for instant mapping",
                            "Tap 'Save' when finished"
                        ]
                    )
                    
                    InstructionSection(
                        icon: "textformat.abc.dottedunderline",
                        iconColor: .blue,
                        title: "2. Encrypt Messages",
                        steps: [
                            "Go to the 'Translate' tab",
                            "Select your language from the dropdown",
                            "Make sure '🔒 Encrypt' mode is selected",
                            "Type your message in 'Original Text'",
                            "Your encrypted message appears in 'Translated Text'",
                            "Tap 'Copy' to share it anywhere!"
                        ]
                    )
                    
                    InstructionSection(
                        icon: "square.and.arrow.up.fill",
                        iconColor: .purple,
                        title: "3. Share Your Language Key",
                        steps: [
                            "Go to 'Languages' tab and tap your language",
                            "Tap 'Share' in the top-left corner",
                            "Send the language key to your friend via:",
                            "  • Text message",
                            "  • Email",
                            "  • AirDrop",
                            "  • Any messaging app"
                        ]
                    )
                    
                    InstructionSection(
                        icon: "square.and.arrow.down.fill",
                        iconColor: .orange,
                        title: "4. Import a Friend's Language",
                        steps: [
                            "Go to the 'Languages' tab",
                            "Tap 'Import' in the top-left corner",
                            "Paste the language key your friend sent you",
                            "Tap 'Import' - the language is now in your app!"
                        ]
                    )
                    
                    InstructionSection(
                        icon: "lock.open.fill",
                        iconColor: .green,
                        title: "5. Decrypt Messages",
                        steps: [
                            "Go to the 'Translate' tab",
                            "Select the same language used to encrypt",
                            "Switch to '🔓 Decrypt' mode",
                            "Paste the encrypted message in 'Encrypted Text'",
                            "The original message appears in 'Decrypted Text'!"
                        ]
                    )
                    
                    // Tips Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                                .font(.title2)
                            Text("Pro Tips")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            TipRow(text: "Use 'Generate for Me' for quick, fun language creation")
                            TipRow(text: "Try different styles: Shuffled Letters, Emojis, Symbols, etc.")
                            TipRow(text: "Both you and your friend need the same language to communicate")
                            TipRow(text: "If you edit a language, reshare it with your contacts")
                            TipRow(text: "Premium users can create unlimited languages and send SMS")
                            TipRow(text: "Free users get 1 language and 100 character limit")
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Example Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            Text("Example")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("If you map: a→e, b→x, c→z")
                                .font(.body)
                            Text("Then 'Hello' becomes 'eexxa' and 'HELLO' becomes 'EEXXA'")
                                .font(.body)
                            Text("Both uppercase and lowercase letters use the same mapping")
                                .font(.body)
                            Text("Your friend imports your language and can decrypt both cases")
                                .font(.body)
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("How To Use Oobada")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
                        .foregroundColor(.purple)
                        
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
            .navigationTitle("Settings")
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
                
                VStack(alignment: .leading, spacing: 15) {
                    FeatureRow(icon: "infinity", title: "Unlimited Languages", description: "Create as many secret languages as you want")
                    FeatureRow(icon: "textformat.size.larger", title: "Longer Messages", description: "Translate up to 500+ characters at once")
                    FeatureRow(icon: "message.fill", title: "Send SMS", description: "Send translated messages directly via text message")
                    FeatureRow(icon: "face.smiling", title: "Emoji Mode", description: "Use emojis and special characters in your codes")
                    FeatureRow(icon: "wand.and.stars", title: "Advanced Generation", description: "More generation styles and customization options")
                }
                
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
                
                Spacer()
            }
            .padding()
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
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.purple)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
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
                    gradient: Gradient(colors: [.purple, .blue]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Adaptive Layout Extensions
extension View {
    @ViewBuilder
    func adaptiveStack<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            HStack(content: content)
        } else {
            VStack(content: content)
        }
    }
}

// MARK: - Device Size Helper
struct DeviceSize {
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    static var isCompact: Bool {
        UIScreen.main.bounds.width < 400
    }
}
