import SwiftUI
import UIKit
import CryptoKit

// MARK: - Card data

struct CardFace: Codable, Equatable {
    var name: String
    var art: String      // "bundle:file.jpg" or an https URL
    var normal: String
}

struct CardData: Codable, Equatable {
    var name: String
    var colors: [String]
    var faces: [CardFace]

    var manaColors: [ManaColor] { Identity.sorted(colors.compactMap { ManaColor(rawValue: $0) }) }
}

/// A commander the picker can suggest.
struct LibraryEntry: Codable, Identifiable, Equatable {
    var name: String
    var colors: [ManaColor]
    var id: String { name.lowercased() }
}

// MARK: - Store

/// Finds card information and images: bundled first, then the on-device cache, then Scryfall.
/// Everything fetched is kept on the device so the game works without internet afterwards.
final class CardStore: ObservableObject {
    static let shared = CardStore()

    /// Commanders offered as suggestions when typing a commander name.
    @Published private(set) var library: [LibraryEntry] = []

    private var cards: [String: CardData] = [:]       // by lowercased name
    private var bundledKeys = Set<String>()
    private var extras: [LibraryEntry] = []
    private var imageMemory = NSCache<NSString, UIImage>()
    private let dir: URL
    private let imageDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MTGTable", isDirectory: true)
        dir = base
        imageDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CardImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        load()
    }

    private var cardsURL: URL { dir.appendingPathComponent("cards.json") }
    private var extrasURL: URL { dir.appendingPathComponent("library.json") }

    private func load() {
        // Bundled commanders
        if let url = Bundle.main.url(forResource: "commanders", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([CardData].self, from: data) {
            for c in list {
                cards[c.name.lowercased()] = c
                bundledKeys.insert(c.name.lowercased())
            }
        }
        // Cards fetched earlier
        if let data = try? Data(contentsOf: cardsURL),
           let saved = try? JSONDecoder().decode([String: CardData].self, from: data) {
            for (k, v) in saved where cards[k] == nil { cards[k] = v }
        }
        if let data = try? Data(contentsOf: extrasURL),
           let saved = try? JSONDecoder().decode([LibraryEntry].self, from: data) {
            extras = saved
        }
        rebuildLibrary()
    }

    private func rebuildLibrary() {
        var seen = Set<String>()
        var entries: [LibraryEntry] = []
        if let url = Bundle.main.url(forResource: "commanders", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([CardData].self, from: data) {
            for c in list where seen.insert(c.name.lowercased()).inserted {
                entries.append(LibraryEntry(name: c.name, colors: c.manaColors))
            }
        }
        for e in extras where seen.insert(e.id).inserted { entries.append(e) }
        library = entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func persist() {
        let userCards = cards.filter { !bundledKeys.contains($0.key) }
        if let data = try? JSONEncoder().encode(userCards) { try? data.write(to: cardsURL, options: .atomic) }
        if let data = try? JSONEncoder().encode(extras) { try? data.write(to: extrasURL, options: .atomic) }
    }

    /// Remember a commander so it shows up in the picker next time.
    func remember(name: String, colors: [ManaColor]) {
        let entry = LibraryEntry(name: name, colors: colors)
        guard !library.contains(where: { $0.id == entry.id }) else { return }
        extras.append(entry)
        rebuildLibrary()
        persist()
    }

    /// Library entries matching what the user has typed.
    func suggestions(for text: String, limit: Int = 8) -> [LibraryEntry] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let starts = library.filter { $0.name.lowercased().hasPrefix(q) }
        let contains = library.filter { !$0.name.lowercased().hasPrefix(q) && $0.name.lowercased().contains(q) }
        return Array((starts + contains).prefix(limit))
    }

    func exactMatch(_ text: String) -> LibraryEntry? {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        return library.first { $0.id == q }
    }

    // MARK: Cards

    /// Cached card data, if we have it (no network).
    func cachedCard(named name: String) -> CardData? {
        cards[name.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// Card data from the cache, or fetched from Scryfall and cached.
    func card(named name: String) async -> CardData? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let hit = cards[key] { return hit }
        var found = try? await fetch(query: name, exact: true)
        if found == nil { found = try? await fetch(query: name, exact: false) }
        guard let fetched = found else { return nil }
        await MainActor.run {
            cards[key] = fetched
            cards[fetched.name.lowercased()] = fetched
            persist()
        }
        return fetched
    }

    /// Looks up a card by fuzzy name (used by Auto-fill) and remembers it.
    func lookup(_ query: String) async throws -> CardData {
        do {
            guard let card = try await fetch(query: query, exact: false) else { throw ScryfallError.notFound }
            await MainActor.run {
                cards[card.name.lowercased()] = card
                cards[query.trimmingCharacters(in: .whitespaces).lowercased()] = card
                remember(name: card.name, colors: card.manaColors)
                persist()
            }
            return card
        } catch let e as ScryfallError {
            throw e
        } catch {
            throw ScryfallError.network
        }
    }

    private func fetch(query: String, exact: Bool) async throws -> CardData? {
        var components = URLComponents(string: "https://api.scryfall.com/cards/named")!
        components.queryItems = [URLQueryItem(name: exact ? "exact" : "fuzzy", value: query)]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("MTGTable/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ScryfallError.network
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return Self.parse(data)
    }

    private struct Uris: Decodable { let normal: String?; let art_crop: String? }
    private struct RawFace: Decodable { let name: String; let image_uris: Uris? }
    private struct Raw: Decodable {
        let name: String
        let color_identity: [String]
        let image_uris: Uris?
        let card_faces: [RawFace]?
    }

    private static func parse(_ data: Data) -> CardData? {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        var faces: [CardFace] = []
        if let uris = raw.image_uris, let n = uris.normal, let a = uris.art_crop {
            faces = [CardFace(name: raw.name, art: a, normal: n)]
        } else if let rawFaces = raw.card_faces {
            for f in rawFaces {
                if let n = f.image_uris?.normal, let a = f.image_uris?.art_crop {
                    faces.append(CardFace(name: f.name, art: a, normal: n))
                }
            }
        }
        return CardData(name: raw.name, colors: raw.color_identity, faces: faces)
    }

    // MARK: Images

    /// An image from the app bundle, the on-device cache, or the network (then cached).
    func image(_ ref: String) async -> UIImage? {
        if let cached = imageMemory.object(forKey: ref as NSString) { return cached }
        var result: UIImage?
        if ref.hasPrefix("bundle:") {
            let file = String(ref.dropFirst("bundle:".count))
            let ns = file as NSString
            if let url = Bundle.main.url(forResource: ns.deletingPathExtension, withExtension: ns.pathExtension),
               let data = try? Data(contentsOf: url) {
                result = UIImage(data: data)
            }
        } else if let url = URL(string: ref) {
            let file = imageDir.appendingPathComponent(Self.hash(ref) + ".jpg")
            if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
                result = img
            } else {
                var request = URLRequest(url: url)
                request.setValue("MTGTable/1.0", forHTTPHeaderField: "User-Agent")
                request.setValue("*/*", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 15
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   (response as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: data) {
                    try? data.write(to: file, options: .atomic)
                    result = img
                }
            }
        }
        if let result { imageMemory.setObject(result, forKey: ref as NSString) }
        return result
    }

    private static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Views

/// Loads a card image asynchronously from the store.
struct StoreImage<Placeholder: View>: View {
    let ref: String?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: Placeholder

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: ref) {
            image = nil
            guard let ref else { return }
            image = await CardStore.shared.image(ref)
        }
    }
}
