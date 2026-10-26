import SwiftUI

// MARK: - Notes

enum NoteTarget: Codable, Equatable, Hashable {
    case player(Int)
    case commander(CommanderRef)
    case tokenGroup(Int)
    case effect(Int)
}

/// A note about a player, commander, token group or effect. Public notes are visible to both players.
/// Private notes stay hidden until their author reveals them, and hide again afterwards.
struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var target: NoteTarget
    var text: String
    var isPrivate: Bool
    var author: Int
    var date = Date()
}

// MARK: - Turn phases

enum TurnPhase: Int, Codable, CaseIterable, Identifiable {
    case upkeep, main1, combat, main2, end

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .upkeep: return "Upkeep"
        case .main1: return "Main"
        case .combat: return "Combat"
        case .main2: return "Main 2"
        case .end: return "End"
        }
    }
}

// MARK: - Reminders

enum ReminderTiming: String, Codable, CaseIterable, Identifiable {
    case upkeep, mainOne, combat, mainTwo, endStep
    case landEnters, creatureEnters, creatureDies, spellCast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upkeep: return "Upkeep"
        case .mainOne: return "Main phase"
        case .combat: return "Combat"
        case .mainTwo: return "Second main"
        case .endStep: return "End step"
        case .landEnters: return "Land enters"
        case .creatureEnters: return "Creature enters"
        case .creatureDies: return "Creature dies"
        case .spellCast: return "Spell cast"
        }
    }

    /// Wording used on the banner when this fires.
    var firedLabel: String {
        switch self {
        case .landEnters: return "Land entered"
        case .creatureEnters: return "Creature entered"
        case .creatureDies: return "Creature died"
        case .spellCast: return "Spell cast"
        default: return title
        }
    }

    var phase: TurnPhase? {
        switch self {
        case .upkeep: return .upkeep
        case .mainOne: return .main1
        case .combat: return .combat
        case .mainTwo: return .main2
        case .endStep: return .end
        default: return nil
        }
    }

    var isEvent: Bool { phase == nil }

    static func timing(for phase: TurnPhase) -> ReminderTiming {
        switch phase {
        case .upkeep: return .upkeep
        case .main1: return .mainOne
        case .combat: return .combat
        case .main2: return .mainTwo
        case .end: return .endStep
        }
    }

    /// The few timings shown first; the rest sit behind "More".
    static let common: [ReminderTiming] = [.upkeep, .combat, .endStep, .landEnters, .creatureEnters, .creatureDies, .spellCast]
    static let more: [ReminderTiming] = [.mainOne, .mainTwo]
}

enum ReminderScope: String, Codable, CaseIterable, Identifiable {
    case mine, theirs, any

    var id: String { rawValue }

    func title(isEvent: Bool) -> String {
        switch self {
        case .mine: return isEvent ? "My actions" : "My turn"
        case .theirs: return isEvent ? "Opponent’s actions" : "Opponent’s turn"
        case .any: return isEvent ? "Anyone’s actions" : "Every turn"
        }
    }
}

struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var owner: Int
    var timing: ReminderTiming
    var text: String
    var scope: ReminderScope = .mine
    var enabled = true

    /// "Upkeep · My turn: Draw a card"
    func summary(ownerName: String) -> String {
        "\(timing.title) · \(scope.title(isEvent: timing.isEvent)): \(text)"
    }
}

/// A group of reminders that fired together, shown as one small expandable banner.
struct ReminderOccurrence: Identifiable, Equatable {
    var id = UUID()
    var label: String
    var owner: Int
    var reminders: [Reminder]
    var done: Set<UUID> = []

    var pending: [Reminder] { reminders.filter { !done.contains($0.id) } }
}

/// A one-tap suggestion created from something that just happened, like gaining the monarch.
struct ReminderSuggestion: Identifiable, Equatable {
    var id = UUID()
    var owner: Int
    var question: String
    var reminder: Reminder
}

/// Reminders saved for reuse across games.
final class ReminderLibrary: ObservableObject {
    static let shared = ReminderLibrary()

    @Published private(set) var saved: [Reminder] = []
    private let url: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MTGTable", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("saved-reminders.json")
        if let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Reminder].self, from: data) {
            saved = list
        }
    }

    func contains(_ r: Reminder) -> Bool {
        saved.contains { $0.timing == r.timing && $0.text == r.text && $0.scope == r.scope }
    }

    func save(_ r: Reminder) {
        guard !contains(r) else { return }
        var copy = r
        copy.id = UUID()
        saved.append(copy)
        persist()
    }

    func remove(_ r: Reminder) {
        saved.removeAll { $0.timing == r.timing && $0.text == r.text && $0.scope == r.scope }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - Voltron calculator

enum VoltronKind: String, Codable, CaseIterable, Identifiable {
    case equipment, aura, counter, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equipment: return "Equipment"
        case .aura: return "Aura"
        case .counter: return "Counter"
        case .other: return "Other"
        }
    }
}

enum VoltronExpiry: Codable, Equatable {
    case permanent
    /// Ends once the turn with this number is over.
    case endOfTurn(Int)
    /// Ends when this player's next turn begins.
    case untilTurnStarts(Int)
}

struct VoltronMod: Codable, Equatable, Identifiable {
    var id: Int = 0
    var name: String
    var kind: VoltronKind = .other
    var power: Int = 0
    var toughness: Int = 0
    var keywords: [String] = []
    var expiry: VoltronExpiry = .permanent
    var enabled = true

    var effectText: String {
        var parts: [String] = []
        if power != 0 || toughness != 0 {
            parts.append("\(power >= 0 ? "+" : "")\(power)/\(toughness >= 0 ? "+" : "")\(toughness)")
        }
        parts.append(contentsOf: keywords)
        return parts.isEmpty ? "no stat change" : parts.joined(separator: ", ")
    }
}

struct VoltronCommander: Codable, Equatable {
    var basePower = 0
    var baseToughness = 0
    var baseKeywords: [String] = []
    var mods: [VoltronMod] = []
    var nextID = 1

    var active: [VoltronMod] { mods.filter { $0.enabled } }
    var power: Int { basePower + active.reduce(0) { $0 + $1.power } }
    var toughness: Int { baseToughness + active.reduce(0) { $0 + $1.toughness } }

    var keywords: [String] {
        var seen = Set<String>()
        return (baseKeywords + active.flatMap { $0.keywords }).filter { seen.insert($0.lowercased()).inserted }
    }

    func has(_ k: String) -> Bool { keywords.contains { $0.caseInsensitiveCompare(k) == .orderedSame } }

    /// Power the commander would attack with. Double strike counts twice.
    var attackingPower: Int { max(0, power) * (has("Double strike") ? 2 : 1) }
}

enum VoltronKeywords {
    static let all = ["Flying", "Trample", "Vigilance", "Double strike", "First strike", "Haste",
                      "Lifelink", "Deathtouch", "Menace", "Indestructible", "Hexproof"]
}

extension GameState {
    func voltron(_ ref: CommanderRef) -> VoltronCommander { voltron[ref.key] ?? VoltronCommander() }
}

enum VoltronOps {
    static func update(_ ref: CommanderRef, in s: inout GameState, _ change: (inout VoltronCommander) -> Void) {
        var v = s.voltron[ref.key] ?? VoltronCommander()
        change(&v)
        s.voltron[ref.key] = v
    }

    /// Temporary modifiers end at the right moment, using real turn changes.
    static func expire(newActive: Int, in s: inout GameState) {
        for key in Array(s.voltron.keys) {
            guard var v = s.voltron[key] else { continue }
            let before = v.mods.count
            v.mods.removeAll { mod in
                switch mod.expiry {
                case .permanent: return false
                case let .endOfTurn(serial): return s.turnSerial > serial
                case let .untilTurnStarts(p): return p == newActive
                }
            }
            if v.mods.count != before { s.voltron[key] = v }
        }
    }
}
