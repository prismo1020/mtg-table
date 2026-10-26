import SwiftUI

/// Token presets (bundled, with art), recently used tokens, and a Scryfall token search.
final class TokenLibrary: ObservableObject {
    static let shared = TokenLibrary()

    @Published private(set) var presets: [TokenTemplate] = []
    @Published private(set) var recents: [TokenTemplate] = []

    private let recentsURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MTGTable", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        recentsURL = dir.appendingPathComponent("recent-tokens.json")
        load()
    }

    private struct RawPreset: Decodable {
        let name: String
        let types: String
        let power: Int?
        let toughness: Int?
        let colors: [String]
        let keywords: [String]
        let art: String?
        let normal: String?
    }

    private func load() {
        if let url = Bundle.main.url(forResource: "tokens", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let raw = try? JSONDecoder().decode([RawPreset].self, from: data) {
            presets = raw.map {
                TokenTemplate(name: $0.name, types: $0.types, power: $0.power, toughness: $0.toughness,
                              colors: Identity.sorted($0.colors.compactMap { ManaColor(rawValue: $0) }),
                              keywords: $0.keywords, art: $0.art, normal: $0.normal)
            }
        }
        if let data = try? Data(contentsOf: recentsURL),
           let saved = try? JSONDecoder().decode([TokenTemplate].self, from: data) {
            recents = saved
        }
    }

    func remember(_ t: TokenTemplate) {
        recents.removeAll { $0.id == t.id }
        recents.insert(t, at: 0)
        if recents.count > 16 { recents = Array(recents.prefix(16)) }
        if let data = try? JSONEncoder().encode(recents) { try? data.write(to: recentsURL, options: .atomic) }
    }

    // MARK: Scryfall search

    private struct Uris: Decodable { let normal: String?; let art_crop: String? }
    private struct Face: Decodable {
        let colors: [String]?
        let image_uris: Uris?
    }
    private struct Card: Decodable {
        let name: String
        let type_line: String?
        let power: String?
        let toughness: String?
        let colors: [String]?
        let keywords: [String]?
        let image_uris: Uris?
        let card_faces: [Face]?
    }
    private struct Page: Decodable { let data: [Card] }

    /// Searches Scryfall for token cards whose name contains `text`.
    func search(_ text: String) async throws -> [TokenTemplate] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var components = URLComponents(string: "https://api.scryfall.com/cards/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "t:token lang:en name:\"\(q)\""),
            URLQueryItem(name: "unique", value: "cards"),
            URLQueryItem(name: "order", value: "name"),
        ]
        guard let url = components.url else { return [] }
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
        guard let http = response as? HTTPURLResponse else { throw ScryfallError.network }
        if http.statusCode == 404 { return [] }
        guard http.statusCode == 200, let page = try? JSONDecoder().decode(Page.self, from: data) else {
            throw ScryfallError.notFound
        }
        var seen = Set<String>()
        var out: [TokenTemplate] = []
        for c in page.data {
            let uris = c.image_uris ?? c.card_faces?.first?.image_uris
            let colors = c.colors ?? c.card_faces?.first?.colors ?? []
            let t = TokenTemplate(
                name: c.name, types: c.type_line ?? "Token",
                power: c.power.flatMap { Int($0) }, toughness: c.toughness.flatMap { Int($0) },
                colors: Identity.sorted(colors.compactMap { ManaColor(rawValue: $0) }),
                keywords: c.keywords ?? [], art: uris?.art_crop, normal: uris?.normal)
            if seen.insert(t.id).inserted { out.append(t) }
            if out.count >= 30 { break }
        }
        return out
    }
}

/// Common keywords offered on the token panels.
enum TokenKeywords {
    static let common = ["Flying", "Haste", "Vigilance", "Trample", "Deathtouch", "Lifelink",
                         "First strike", "Double strike", "Menace", "Reach", "Defender",
                         "Hexproof", "Indestructible"]
    static let counters = ["+1/+1", "-1/-1", "Shield", "Stun", "Finality", "Charge", "Time"]
}
