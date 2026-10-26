import SwiftUI

// MARK: - Colors

enum ManaColor: String, Codable, CaseIterable, Identifiable {
    case white = "W", blue = "U", black = "B", red = "R", green = "G"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .white: return Color(red: 0.91, green: 0.87, blue: 0.74)
        case .blue: return Color(red: 0.16, green: 0.38, blue: 0.72)
        case .black: return Color(red: 0.17, green: 0.15, blue: 0.20)
        case .red: return Color(red: 0.76, green: 0.22, blue: 0.18)
        case .green: return Color(red: 0.17, green: 0.52, blue: 0.30)
        }
    }
}

enum Identity {
    static let colorless = Color(red: 0.36, green: 0.38, blue: 0.43)

    static func sorted(_ colors: [ManaColor]) -> [ManaColor] {
        ManaColor.allCases.filter { colors.contains($0) }
    }

    static func background(for colors: [ManaColor]) -> LinearGradient {
        let list = sorted(colors)
        switch list.count {
        case 0:
            return LinearGradient(colors: [colorless], startPoint: .top, endPoint: .bottom)
        case 1:
            return LinearGradient(colors: [list[0].color], startPoint: .top, endPoint: .bottom)
        default:
            let stops = list.map { $0 == .white ? Color(red: 0.70, green: 0.65, blue: 0.48) : $0.color }
            return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    static func accent(for colors: [ManaColor]) -> Color {
        let list = sorted(colors)
        if list.count == 1 { return list[0].color }
        if list.isEmpty { return colorless }
        return Color(red: 0.84, green: 0.68, blue: 0.25)
    }

    static func prefersDarkText(for colors: [ManaColor]) -> Bool {
        colors.count == 1 && colors[0] == .white
    }

    static func label(for colors: [ManaColor]) -> String {
        let list = sorted(colors)
        return list.isEmpty ? "C" : list.map { $0.rawValue }.joined()
    }
}

// MARK: - Setup

struct CommanderInfo: Codable, Hashable {
    var name: String = ""
    var colors: [ManaColor] = []

    /// "Krenko, Mob Boss" -> "Krenko"
    var shortName: String {
        let full = name.trimmingCharacters(in: .whitespaces)
        if let comma = full.firstIndex(of: ",") {
            let head = full[..<comma].trimmingCharacters(in: .whitespaces)
            if !head.isEmpty { return head }
        }
        return full
    }
}

struct PlayerSetup: Codable, Equatable {
    var name: String
    var commanders: [CommanderInfo] = []
    /// Used for the panel color when the player has no commander.
    var colors: [ManaColor] = []

    var effectiveColors: [ManaColor] {
        let fromCommanders = Set(commanders.flatMap { $0.colors })
        if !commanders.isEmpty && !fromCommanders.isEmpty {
            return Identity.sorted(Array(fromCommanders))
        }
        return colors
    }
}

struct FormatPreset: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var startingLife: Int
    /// Commanders per player (0 = no commander).
    var commanderSlots: Int
    var trackTax: Bool
    var trackCommanderDamage: Bool
    var note: String = ""

    static let defaults: [FormatPreset] = [
        FormatPreset(id: "commander", name: "Commander", startingLife: 40, commanderSlots: 2,
                     trackTax: true, trackCommanderDamage: true),
        FormatPreset(id: "standard", name: "Standard", startingLife: 20, commanderSlots: 0,
                     trackTax: false, trackCommanderDamage: false),
        FormatPreset(id: "brawl2", name: "Brawl (2 players)", startingLife: 25, commanderSlots: 1,
                     trackTax: true, trackCommanderDamage: true),
        FormatPreset(id: "brawl-multi", name: "Brawl (multiplayer)", startingLife: 30, commanderSlots: 1,
                     trackTax: true, trackCommanderDamage: true,
                     note: "For when multiplayer layouts are added."),
        FormatPreset(id: "oathbreaker", name: "Oathbreaker", startingLife: 20, commanderSlots: 1,
                     trackTax: true, trackCommanderDamage: true),
        FormatPreset(id: "custom", name: "Custom", startingLife: 20, commanderSlots: 0,
                     trackTax: false, trackCommanderDamage: false),
    ]
}

struct GameSettings: Codable, Equatable {
    var formatName: String
    var startingLife: Int
    var commanderSlots: Int
    var trackTax: Bool
    var trackCommanderDamage: Bool
    var startingPlayer: Int
    var timer: TimerSettings? = nil
    var showArt: Bool? = nil

    var hasCommanders: Bool { commanderSlots > 0 }
    var timerSettings: TimerSettings { timer ?? TimerSettings() }
    var artOn: Bool { (showArt ?? false) && hasCommanders }
}

// MARK: - Counters

enum CounterKind: String, Codable, CaseIterable, Identifiable {
    case poison, energy, experience, rad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .poison: return "Poison"
        case .energy: return "Energy"
        case .experience: return "Experience"
        case .rad: return "Rad"
        }
    }

    /// SF Symbol name for this counter.
    var icon: String {
        switch self {
        case .poison: return "drop.fill"
        case .energy: return "bolt.fill"
        case .experience: return "star.fill"
        case .rad: return "atom"
        }
    }

}

// MARK: - Game state (derived by replaying the action log)

struct CommanderRef: Codable, Hashable {
    var player: Int
    var index: Int
    var key: String { "\(player)-\(index)" }
}

let poisonLethal = 10
let commanderDamageLethal = 21

struct GameState: Codable, Equatable {
    var life: [Int]
    var counters: [[String: Int]]            // [player][CounterKind.rawValue]
    var casts: [[Int]]                       // [player][commander] casts from the command zone
    var commanderDamage: [[String: Int]]     // [victim][CommanderRef.key]
    var monarch: Int?
    var initiative: Int?

    var active: Int
    var turnSerial: Int                      // total number of player turns that have begun
    var turnsTaken: [Int]                    // per-player turn numbers
    var round: Int
    var extraTurns: [Int]                    // queued extra turns, in order
    var skipNext: [Bool]                     // regular turn will be skipped
    var regularThisRound: [Bool]
    var lastRegular: Int

    // Tokens
    var tokens: [TokenGroup]
    var nextTokenID: Int
    /// Counts token arrivals and turn starts, so "arrived after the turn began" can be decided exactly.
    var seq: Int
    var turnStartSeq: [Int]
    var autoUntap: Bool
    var effects: [TokenEffect]
    var nextEffectID: Int
    var voltron: [String: VoltronCommander]

    static func initial(settings: GameSettings) -> GameState {
        let start = settings.startingPlayer
        var taken = [0, 0]
        taken[start] = 1
        var reg = [false, false]
        reg[start] = true
        return GameState(
            life: [settings.startingLife, settings.startingLife],
            counters: [[:], [:]],
            casts: [[0, 0], [0, 0]],
            commanderDamage: [[:], [:]],
            monarch: nil, initiative: nil,
            active: start, turnSerial: 1, turnsTaken: taken, round: 1,
            extraTurns: [], skipNext: [false, false],
            regularThisRound: reg, lastRegular: start,
            tokens: [], nextTokenID: 1, seq: 0, turnStartSeq: [0, 0], autoUntap: true,
            effects: [], nextEffectID: 1, voltron: [:])
    }

    func count(_ player: Int, _ kind: CounterKind) -> Int {
        counters[player][kind.rawValue] ?? 0
    }

    func damage(to victim: Int, from ref: CommanderRef) -> Int {
        commanderDamage[victim][ref.key] ?? 0
    }

    /// Mana added to the next command-zone cast.
    func nextTax(player: Int, commander: Int) -> Int {
        2 * casts[player][commander]
    }
}

// MARK: - Actions

enum Action: Codable, Equatable {
    case life(player: Int, delta: Int)
    case setLife(player: Int, to: Int)
    case counter(player: Int, kind: CounterKind, delta: Int)
    case setCounter(player: Int, kind: CounterKind, to: Int)
    case cast(player: Int, commander: Int, delta: Int)
    case commanderDamage(victim: Int, sourcePlayer: Int, sourceCommander: Int, delta: Int)
    case setMonarch(player: Int?)
    case setInitiative(player: Int?)
    case nextTurn
    case extraTurn(player: Int)
    case skipNextTurn(player: Int, on: Bool)
    case setActive(player: Int)
    case createTokens(owner: Int, template: TokenTemplate, quantity: Int)
    case tokenAdd(group: Int, count: Int)
    case tokenRemove(group: Int, count: Int)
    case tokenModify(group: Int, count: Int, mod: TokenMod)
    case tokenEdit(group: Int, power: Int, toughness: Int)
    case mergeTokens(owner: Int)
    case setAutoUntap(Bool)
    case addEffect(TokenEffect)
    case updateEffect(TokenEffect)
    case removeEffect(id: Int)
    case setEffectEnabled(id: Int, enabled: Bool)
    case voltronBase(CommanderRef, power: Int, toughness: Int)
    case voltronKeyword(CommanderRef, String, Bool)
    case voltronAddMod(CommanderRef, VoltronMod)
    case voltronSetMod(CommanderRef, id: Int, enabled: Bool)
    case voltronRemoveMod(CommanderRef, id: Int)
}

enum Reducer {
    static func apply(_ action: Action, to s: inout GameState) {
        switch action {
        case let .life(p, d):
            s.life[p] += d
        case let .setLife(p, v):
            s.life[p] = v
        case let .counter(p, kind, d):
            s.counters[p][kind.rawValue] = max(0, (s.counters[p][kind.rawValue] ?? 0) + d)
        case let .setCounter(p, kind, v):
            s.counters[p][kind.rawValue] = max(0, v)
        case let .cast(p, c, d):
            s.casts[p][c] = max(0, s.casts[p][c] + d)
        case let .commanderDamage(victim, sp, sc, d):
            let key = CommanderRef(player: sp, index: sc).key
            s.commanderDamage[victim][key] = max(0, (s.commanderDamage[victim][key] ?? 0) + d)
        case let .setMonarch(p):
            s.monarch = p
        case let .setInitiative(p):
            s.initiative = p
        case .nextTurn:
            advanceTurn(&s)
        case let .extraTurn(p):
            s.extraTurns.append(p)
        case let .skipNextTurn(p, on):
            s.skipNext[p] = on
        case let .setActive(p):
            s.active = p
        case let .createTokens(owner, template, quantity):
            TokenOps.create(owner: owner, template: template, quantity: quantity, in: &s)
        case let .tokenAdd(group, count):
            TokenOps.add(group: group, count: count, in: &s)
        case let .tokenRemove(group, count):
            TokenOps.remove(group: group, count: count, in: &s)
        case let .tokenModify(group, count, mod):
            TokenOps.modify(group: group, count: count, mod: mod, in: &s)
        case let .tokenEdit(group, power, toughness):
            TokenOps.edit(group: group, power: power, toughness: toughness, in: &s)
        case let .mergeTokens(owner):
            TokenOps.mergeAll(owner, in: &s)
        case let .setAutoUntap(v):
            s.autoUntap = v
        case var .addEffect(e):
            e.id = s.nextEffectID
            s.nextEffectID += 1
            s.effects.append(e)
        case let .updateEffect(e):
            if let i = s.effects.firstIndex(where: { $0.id == e.id }) { s.effects[i] = e }
        case let .removeEffect(id):
            s.effects.removeAll { $0.id == id }
        case let .setEffectEnabled(id, enabled):
            if let i = s.effects.firstIndex(where: { $0.id == id }) { s.effects[i].enabled = enabled }
        case let .voltronBase(ref, p, t):
            VoltronOps.update(ref, in: &s) { $0.basePower = p; $0.baseToughness = t }
        case let .voltronKeyword(ref, k, on):
            VoltronOps.update(ref, in: &s) { v in
                v.baseKeywords.removeAll { $0.caseInsensitiveCompare(k) == .orderedSame }
                if on { v.baseKeywords.append(k) }
            }
        case var .voltronAddMod(ref, mod):
            VoltronOps.update(ref, in: &s) { v in
                mod.id = v.nextID
                v.nextID += 1
                v.mods.append(mod)
            }
        case let .voltronSetMod(ref, id, enabled):
            VoltronOps.update(ref, in: &s) { v in
                if let i = v.mods.firstIndex(where: { $0.id == id }) { v.mods[i].enabled = enabled }
            }
        case let .voltronRemoveMod(ref, id):
            VoltronOps.update(ref, in: &s) { $0.mods.removeAll { $0.id == id } }
        }
    }

    /// A regular turn begins for `p`. A round ends once both players have had a regular turn.
    private static func markRegular(_ p: Int, in s: inout GameState) {
        if s.regularThisRound[p] {
            s.round += 1
            s.regularThisRound = [false, false]
        }
        s.regularThisRound[p] = true
        s.lastRegular = p
    }

    private static func advanceTurn(_ s: inout GameState) {
        var next: Int
        if !s.extraTurns.isEmpty {
            // Extra turns never start a new round.
            next = s.extraTurns.removeFirst()
        } else {
            next = 1 - s.lastRegular
            var guardCount = 0
            while s.skipNext[next] && guardCount < 4 {
                s.skipNext[next] = false
                markRegular(next, in: &s)       // a skipped turn still counts toward the round
                next = 1 - next
                guardCount += 1
            }
            markRegular(next, in: &s)
        }
        s.active = next
        s.turnSerial += 1
        s.turnsTaken[next] += 1
        TokenOps.turnBegan(for: next, in: &s)
        VoltronOps.expire(newActive: next, in: &s)
    }
}

// MARK: - Log and results

struct LogEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var turn: Int
    var group: UUID
    var action: Action
    var text: String
}

enum Outcome: String, Codable, CaseIterable {
    case win, draw, concession, unfinished

    var title: String {
        switch self {
        case .win: return "Win"
        case .draw: return "Draw"
        case .concession: return "Concession"
        case .unfinished: return "Unfinished"
        }
    }
}

struct GameResult: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var formatName: String
    var players: [PlayerSetup]
    var startingPlayer: Int
    var winner: Int?
    var outcome: Outcome
    var durationSeconds: Int
    var totalTurns: Int
    var rounds: Int
    var finalLife: [Int]
    var playerSeconds: [Int]? = nil
}
