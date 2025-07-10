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
    
    func translate(text: String, using language: CustomLanguage) -> String {
        var result = ""
        for character in text {
            let lowerChar = Character(character.lowercased())
            if let mapped = language.mapping[lowerChar] {
                result += mapped
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
                
                if let originalChar = reverseMapping[substring] {
                    result += originalChar
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
    @Published var isPremium: Bool = false
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
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(3)
        }
        .accentColor(.purple)
        .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
        .onAppear {
            setupTabBarAppearance()
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
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Language Selector
                if !languageManager.languages.isEmpty {
                    Picker("Select Language", selection: $languageManager.selectedLanguage) {
                        ForEach(languageManager.languages) { language in
                            Text(language.name).tag(language as CustomLanguage?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal)
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
                    NavigationLink(destination: LanguageDetailView(language: language)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(language.name)
                                .font(.headline)
                            Text("\(language.mapping.count) letters mapped")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
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
                                set: { letterMappings[letter] = $0.isEmpty ? nil : $0 }
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
            .alert("Language Created!", isPresented: $showSuccessAlert) {
                Button("OK") {
                    presentationMode.wrappedValue.dismiss()
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
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
        showSuccessAlert = true
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
        
        for (index, letter) in alphabet.enumerated() {
            let number = (index + 1) % 10 // Cycles 1-9, then 0
            letterMappings[letter] = "\(number)"
        }
    }
    
    private func generateEmojis() {
        let emojiSets = [
            "😀😃😄😁😆😅😂🤣😊😇",
            "🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯",
            "🍎🍊🍋🍌🍉🍇🍓🍈🍒🍑",
            "⚽🏀🏈⚾🎾🏐🏉🎱🏓🏸",
            "🌟⭐✨💫⚡🔥💥💢💨💤"
        ]
        
        let selectedSet = emojiSets.randomElement() ?? emojiSets[0]
        let emojis = Array(selectedSet)
        
        letterMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            let emojiIndex = index % emojis.count
            letterMappings[letter] = String(emojis[emojiIndex])
        }
    }
    
    private func generateSymbols() {
        let symbols = ["★", "♦", "♠", "♥", "♣", "◆", "◇", "◈", "○", "●", "◯", "◉", "△", "▲", "▽", "▼", "□", "■", "◦", "‣", "⁂", "※", "‼", "⁇", "⁈", "⁉"]
        
        letterMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            let symbolIndex = index % symbols.count
            letterMappings[letter] = symbols[symbolIndex]
        }
    }
    
    private func generateMixedStyle() {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
        let numbers = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let symbols = ["★", "♦", "♠", "♥", "◆", "●", "▲", "■"]
        let emojis = ["😊", "🔥", "⭐", "💎", "🎯", "🚀"]
        
        let allCharacters = letters + numbers + symbols + emojis
        let shuffledMix = allCharacters.shuffled()
        letterMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            let charIndex = index % shuffledMix.count
            letterMappings[letter] = shuffledMix[charIndex]
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
                                set: { tempMappings[letter] = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            Text(currentLanguage.mapping[letter] ?? "Not set")
                                .foregroundColor(currentLanguage.mapping[letter] == nil ? .gray : .primary)
                        }
                    }
                }
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
                if premiumManager.isPremium {
                    Button("Share") {
                        shareLanguage()
                    }
                    .foregroundColor(.blue)
                }
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
        var updatedLanguage = currentLanguage
        updatedLanguage.name = tempName
        updatedLanguage.mapping = tempMappings
        languageManager.updateLanguage(updatedLanguage)
        isEditing = false
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
        
        for (index, letter) in alphabet.enumerated() {
            let number = (index + 1) % 10 // Cycles 1-9, then 0
            tempMappings[letter] = "\(number)"
        }
    }
    
    private func generateEmojis() {
        let emojiSets = [
            "😀😃😄😁😆😅😂🤣😊😇",
            "🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯",
            "🍎🍊🍋🍌🍉🍇🍓🍈🍒🍑",
            "⚽🏀🏈⚾🎾🏐🏉🎱🏓🏸",
            "🌟⭐✨💫⚡🔥💥💢💨💤"
        ]
        
        let selectedSet = emojiSets.randomElement() ?? emojiSets[0]
        let emojis = Array(selectedSet)
        
        tempMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            let emojiIndex = index % emojis.count
            tempMappings[letter] = String(emojis[emojiIndex])
        }
    }
    
    private func generateSymbols() {
        let symbols = ["★", "♦", "♠", "♥", "♣", "◆", "◇", "◈", "○", "●", "◯", "◉", "△", "▲", "▽", "▼", "□", "■", "◦", "‣", "⁂", "※", "‼", "⁇", "⁈", "⁉"]
        
        tempMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            let symbolIndex = index % symbols.count
            tempMappings[letter] = symbols[symbolIndex]
        }
    }
    
    private func generateMixedStyle() {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
        let numbers = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let symbols = ["★", "♦", "♠", "♥", "◆", "●", "▲", "■"]
        let emojis = ["😊", "🔥", "⭐", "💎", "🎯", "🚀"]
        
        let allCharacters = letters + numbers + symbols + emojis
        let shuffledMix = allCharacters.shuffled()
        tempMappings.removeAll()
        
        for (index, letter) in alphabet.enumerated() {
            let charIndex = index % shuffledMix.count
            tempMappings[letter] = shuffledMix[charIndex]
        }
    }
}

// MARK: - Settings View
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
                    FeatureRow(icon: "square.and.arrow.up", title: "Share Languages", description: "Export and share your languages with friends")
                    FeatureRow(icon: "face.smiling", title: "Emoji Mode", description: "Use emojis and special characters in your codes")
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
