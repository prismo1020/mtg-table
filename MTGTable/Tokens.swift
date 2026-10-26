import SwiftUI

// MARK: - Templates (what a token is, before it is on the battlefield)

struct TokenTemplate: Codable, Equatable, Identifiable {
    var name: String
    var types: String
    var power: Int?
    var toughness: Int?
    var colors: [ManaColor]
    var keywords: [String]
    var art: String?
    var normal: String?

    var id: String {
        "\(name)|\(types)|\(power ?? -1)/\(toughness ?? -1)|\(colors.map(\.rawValue).joined())|\(keywords.sorted().joined(separator: ","))"
    }

    var isCreature: Bool { types.lowercased().contains("creature") || power != nil }

    var statsText: String {
        guard isCreature else {
            let t = types.replacingOccurrences(of: "Token ", with: "")
            return t.components(separatedBy: " — ").first ?? t
        }
        return "\(power ?? 0)/\(toughness ?? 0)"
    }
}

// MARK: - Effects (anthems and other persistent bonuses)

enum EffectScope: String, Codable, CaseIterable {
    case mine, theirs, both

    func title(of controller: String, other: String) -> String {
        switch self {
        case .mine: return "\(controller)’s tokens"
        case .theirs: return "\(other)’s tokens"
        case .both: return "Everyone’s tokens"
        }
    }
}

enum EffectFilter: Codable, Equatable {
    case allCreatures
    case types([String])
    case groups([Int])
}

/// A named bonus such as an anthem. It is never stored on tokens: stats are always worked out from the
/// current effects, so editing, disabling or removing an effect updates every token immediately.
struct TokenEffect: Codable, Equatable, Identifiable {
    var id: Int = 0
    var name: String
    var power: Int = 0
    var toughness: Int = 0
    var keywords: [String] = []
    var controller: Int
    var scope: EffectScope = .mine
    var filter: EffectFilter = .allCreatures
    var enabled: Bool = true

    func matches(_ g: TokenGroup) -> Bool {
        guard enabled, g.isCreature else { return false }
        switch scope {
        case .mine: if g.owner != controller { return false }
        case .theirs: if g.owner == controller { return false }
        case .both: break
        }
        switch filter {
        case .allCreatures:
            return true
        case let .types(list):
            let have = g.types.lowercased()
            return list.contains { have.contains($0.lowercased()) }
        case let .groups(ids):
            return ids.contains(g.id)
        }
    }

    /// "+1/+1, Flying"
    var effectText: String {
        var parts: [String] = []
        if power != 0 || toughness != 0 {
            parts.append("\(power >= 0 ? "+" : "")\(power)/\(toughness >= 0 ? "+" : "")\(toughness)")
        }
        parts.append(contentsOf: keywords)
        return parts.isEmpty ? "No effect set" : parts.joined(separator: ", ")
    }

    func targetText(controllerName: String, otherName: String) -> String {
        let who = scope.title(of: controllerName, other: otherName)
        switch filter {
        case .allCreatures: return "All creature tokens · \(who)"
        case let .types(list): return "\(list.joined(separator: ", ")) · \(who)"
        case let .groups(ids): return "\(ids.count) selected group\(ids.count == 1 ? "" : "s") · \(who)"
        }
    }
}

extension GameState {
    func effects(affecting g: TokenGroup) -> [TokenEffect] { effects.filter { $0.matches(g) } }

    /// Current power: base, counters and the token's own bonus, plus every effect that applies.
    func power(_ g: TokenGroup) -> Int { g.power + effects(affecting: g).reduce(0) { $0 + $1.power } }

    func toughness(_ g: TokenGroup) -> Int { g.toughness + effects(affecting: g).reduce(0) { $0 + $1.toughness } }

    func keywords(_ g: TokenGroup) -> [String] {
        var seen = Set<String>()
        let granted = effects(affecting: g).flatMap { $0.keywords }
        return (g.allKeywords + granted).filter { seen.insert($0.lowercased()).inserted }
    }

    func hasKeyword(_ g: TokenGroup, _ k: String) -> Bool {
        keywords(g).contains { $0.caseInsensitiveCompare(k) == .orderedSame }
    }

    /// Effect bonuses only (kept apart from counters and the token's own modifiers).
    func isModified(_ g: TokenGroup) -> Bool {
        g.bonusPower != 0 || g.bonusToughness != 0 || !g.counters.isEmpty || !effects(affecting: g).isEmpty
    }
}

// MARK: - A group of identical tokens

/// Tokens that are identical in every tracked way (characteristics, counters, state) live in one group.
/// Tapping 2 of 5 tokens splits the group; matching groups merge back together.
struct TokenGroup: Codable, Equatable, Identifiable {
    var id: Int
    var owner: Int
    var name: String
    var types: String
    var isCreature: Bool
    var basePower: Int
    var baseToughness: Int
    var colors: [ManaColor]
    var keywords: [String]
    var art: String?
    var normal: String?
    var quantity: Int
    var tapped: Bool = false
    var counters: [String: Int] = [:]
    var bonusPower: Int = 0
    var bonusToughness: Int = 0
    var grantedKeywords: [String] = []
    var cantAttack: Bool = false
    var noUntap: Bool = false
    /// Log position (`GameState.seq`) at which these tokens arrived under their controller's control.
    var enteredSeq: Int

    var power: Int { basePower + counter("+1/+1") - counter("-1/-1") + bonusPower }
    var toughness: Int { baseToughness + counter("+1/+1") - counter("-1/-1") + bonusToughness }

    func counter(_ name: String) -> Int { counters[name] ?? 0 }

    var allKeywords: [String] {
        var seen = Set<String>()
        return (keywords + grantedKeywords).filter { seen.insert($0.lowercased()).inserted }
    }

    func has(_ keyword: String) -> Bool {
        allKeywords.contains { $0.caseInsensitiveCompare(keyword) == .orderedSame }
    }

    var template: TokenTemplate {
        TokenTemplate(name: name, types: types, power: isCreature ? basePower : nil,
                      toughness: isCreature ? baseToughness : nil, colors: colors,
                      keywords: keywords, art: art, normal: normal)
    }
}

// MARK: - Summoning sickness and attack availability

enum TokenRules {
    /// A creature has summoning sickness if it arrived after its controller's current/latest turn began.
    static func isSick(_ g: TokenGroup, _ s: GameState) -> Bool {
        g.isCreature && g.enteredSeq > s.turnStartSeq[g.owner]
    }

    /// Everything currently stopping this group from attacking (empty means it can attack).
    static func attackBlockers(_ g: TokenGroup, _ s: GameState) -> [String] {
        guard g.isCreature else { return ["Not a creature"] }
        var out: [String] = []
        if g.tapped { out.append("Tapped") }
        if isSick(g, s) && !s.hasKeyword(g, "Haste") { out.append("Summoning sick") }
        if g.cantAttack { out.append("Can’t attack") }
        if s.hasKeyword(g, "Defender") { out.append("Defender") }
        return out
    }

    /// Tokens that match in every way (including whether they are summoning sick) can share a group.
    static func signature(_ g: TokenGroup, _ s: GameState) -> String {
        let counters = g.counters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        return [
            "\(g.owner)", g.name, g.types, "\(g.isCreature)", "\(g.basePower)/\(g.baseToughness)",
            g.colors.map(\.rawValue).joined(), g.keywords.sorted().joined(separator: ","),
            g.grantedKeywords.sorted().joined(separator: ","), counters,
            "\(g.bonusPower)/\(g.bonusToughness)", "\(g.tapped)", "\(g.cantAttack)", "\(g.noUntap)",
            "\(isSick(g, s))", g.art ?? "",
            s.effects.filter { if case let .groups(ids) = $0.filter { return ids.contains(g.id) } else { return false } }
                .map { "\($0.id)" }.joined(separator: ","),
        ].joined(separator: "|")
    }
}

// MARK: - Modifications

enum TokenMod: Codable, Equatable {
    case tapped(Bool)
    case counter(String, Int)
    case bonus(power: Int, toughness: Int)
    case keyword(String, Bool)
    case sick(Bool)
    case cantAttack(Bool)
    case noUntap(Bool)
    case controller(Int)
}

enum TokenOps {
    // MARK: Creating and removing

    static func create(owner: Int, template t: TokenTemplate, quantity: Int, inheritEffectsFrom: Int? = nil,
                       in s: inout GameState) {
        guard quantity > 0 else { return }
        s.seq += 1
        let g = TokenGroup(id: s.nextTokenID, owner: owner, name: t.name, types: t.types,
                           isCreature: t.isCreature, basePower: t.power ?? 0, baseToughness: t.toughness ?? 0,
                           colors: t.colors, keywords: t.keywords, art: t.art, normal: t.normal,
                           quantity: quantity, enteredSeq: s.seq)
        s.nextTokenID += 1
        s.tokens.append(g)
        if let from = inheritEffectsFrom { copyEffectMembership(from: from, to: g.id, in: &s) }
        mergeAll(owner, in: &s)
    }

    /// Effects aimed at specific groups follow a group when it splits or gets more tokens.
    static func copyEffectMembership(from old: Int, to new: Int, in s: inout GameState) {
        for i in s.effects.indices {
            if case var .groups(ids) = s.effects[i].filter, ids.contains(old), !ids.contains(new) {
                ids.append(new)
                s.effects[i].filter = .groups(ids)
            }
        }
    }

    /// More tokens like an existing group (fresh ones: untapped, no counters, summoning sick).
    static func add(group id: Int, count: Int, in s: inout GameState) {
        guard let g = s.tokens.first(where: { $0.id == id }) else { return }
        create(owner: g.owner, template: g.template, quantity: count, inheritEffectsFrom: id, in: &s)
    }

    static func remove(group id: Int, count: Int, in s: inout GameState) {
        guard let i = s.tokens.firstIndex(where: { $0.id == id }) else { return }
        let owner = s.tokens[i].owner
        s.tokens[i].quantity -= count
        if s.tokens[i].quantity <= 0 { s.tokens.remove(at: i) }
        mergeAll(owner, in: &s)
    }

    // MARK: Changing a quantity of a group (splits when needed)

    static func modify(group id: Int, count: Int, mod: TokenMod, in s: inout GameState) {
        guard let i = s.tokens.firstIndex(where: { $0.id == id }) else { return }
        let n = max(1, min(count, s.tokens[i].quantity))
        var target = i
        if n < s.tokens[i].quantity {
            var part = s.tokens[i]
            s.tokens[i].quantity -= n
            part.quantity = n
            part.id = s.nextTokenID
            s.nextTokenID += 1
            s.tokens.insert(part, at: i + 1)
            copyEffectMembership(from: id, to: part.id, in: &s)
            target = i + 1
        }
        let oldOwner = s.tokens[target].owner
        switch mod {
        case let .tapped(v):
            s.tokens[target].tapped = v
        case let .counter(name, delta):
            let value = max(0, s.tokens[target].counter(name) + delta)
            if value == 0 { s.tokens[target].counters.removeValue(forKey: name) }
            else { s.tokens[target].counters[name] = value }
        case let .bonus(p, t):
            s.tokens[target].bonusPower += p
            s.tokens[target].bonusToughness += t
        case let .keyword(k, on):
            if on {
                if !s.tokens[target].has(k) { s.tokens[target].grantedKeywords.append(k) }
            } else {
                s.tokens[target].grantedKeywords.removeAll { $0.caseInsensitiveCompare(k) == .orderedSame }
                s.tokens[target].keywords.removeAll { $0.caseInsensitiveCompare(k) == .orderedSame }
            }
        case let .sick(on):
            if on {
                s.seq += 1
                s.tokens[target].enteredSeq = s.seq
            } else {
                s.tokens[target].enteredSeq = s.turnStartSeq[s.tokens[target].owner]
            }
        case let .cantAttack(v):
            s.tokens[target].cantAttack = v
        case let .noUntap(v):
            s.tokens[target].noUntap = v
        case let .controller(p):
            s.seq += 1
            s.tokens[target].owner = p
            s.tokens[target].enteredSeq = s.seq     // new controller: summoning sick again
        }
        mergeAll(oldOwner, in: &s)
        mergeAll(1 - oldOwner, in: &s)
    }

    static func edit(group id: Int, power: Int, toughness: Int, in s: inout GameState) {
        guard let i = s.tokens.firstIndex(where: { $0.id == id }) else { return }
        s.tokens[i].basePower = power
        s.tokens[i].baseToughness = toughness
        mergeAll(s.tokens[i].owner, in: &s)
    }

    // MARK: Merging

    static func mergeAll(_ owner: Int, in s: inout GameState) {
        var i = 0
        while i < s.tokens.count {
            guard s.tokens[i].owner == owner else { i += 1; continue }
            let sig = TokenRules.signature(s.tokens[i], s)
            var j = i + 1
            while j < s.tokens.count {
                if s.tokens[j].owner == owner && TokenRules.signature(s.tokens[j], s) == sig {
                    s.tokens[i].quantity += s.tokens[j].quantity
                    s.tokens[i].enteredSeq = max(s.tokens[i].enteredSeq, s.tokens[j].enteredSeq)
                    s.tokens.remove(at: j)
                } else {
                    j += 1
                }
            }
            i += 1
        }
    }

    // MARK: Turn changes

    /// A turn really began for `p`: clear their summoning sickness (through `turnStartSeq`)
    /// and untap their tokens, except those marked "doesn't untap".
    static func turnBegan(for p: Int, in s: inout GameState) {
        s.seq += 1
        s.turnStartSeq[p] = s.seq
        if s.autoUntap {
            for i in s.tokens.indices where s.tokens[i].owner == p && s.tokens[i].tapped && !s.tokens[i].noUntap {
                s.tokens[i].tapped = false
            }
        }
        mergeAll(p, in: &s)
    }
}

// MARK: - Convenience for the UI

extension GameState {
    func tokens(of owner: Int) -> [TokenGroup] { tokens.filter { $0.owner == owner } }

    func tokenCount(of owner: Int) -> Int { tokens(of: owner).reduce(0) { $0 + $1.quantity } }

    /// Creature tokens that can attack right now.
    func attackReady(of owner: Int) -> Int {
        tokens(of: owner).filter { TokenRules.attackBlockers($0, self).isEmpty }.reduce(0) { $0 + $1.quantity }
    }

    func creatureCount(of owner: Int) -> Int {
        tokens(of: owner).filter { $0.isCreature }.reduce(0) { $0 + $1.quantity }
    }
}
