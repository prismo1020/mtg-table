import SwiftUI

struct SavedGame: Codable {
    var settings: GameSettings
    var players: [PlayerSetup]
    var entries: [LogEntry]
    var cursor: Int
    var startedAt: Date
    var clock: ClockState? = nil
    var notes: [Note]? = nil
    var reminders: [Reminder]? = nil
}

/// One game in progress. Every change is an `Action` recorded in a log; the current
/// state is the result of replaying the log up to `cursor`, so undo/redo are exact.
final class Game: ObservableObject {
    let settings: GameSettings
    let players: [PlayerSetup]
    let startedAt: Date

    @Published private(set) var entries: [LogEntry]
    @Published private(set) var cursor: Int
    @Published private(set) var state: GameState
    @Published var notes: [Note] = []
    @Published var reminders: [Reminder] = []
    @Published private(set) var phase: TurnPhase = .upkeep
    @Published var occurrences: [ReminderOccurrence] = []
    @Published var suggestion: ReminderSuggestion?
    private var phaseSerial = 1

    private let initial: GameState
    let clock: ClockModel
    var onChange: (() -> Void)? {
        didSet { clock.onChange = { [weak self] in self?.onChange?() } }
    }

    init(settings: GameSettings, players: [PlayerSetup]) {
        self.settings = settings
        self.players = players
        self.startedAt = Date()
        self.entries = []
        self.cursor = 0
        self.initial = GameState.initial(settings: settings)
        self.state = initial
        self.clock = ClockModel(settings: settings.timerSettings, active: initial.active, turnSerial: initial.turnSerial)
        self.clock.names = players.map { $0.name }
    }

    init(saved: SavedGame) {
        self.settings = saved.settings
        self.players = saved.players
        self.startedAt = saved.startedAt
        self.entries = saved.entries
        self.cursor = min(saved.cursor, saved.entries.count)
        self.notes = saved.notes ?? []
        self.reminders = saved.reminders ?? []
        self.initial = GameState.initial(settings: saved.settings)
        self.state = initial
        if let c = saved.clock {
            self.clock = ClockModel(restoring: c, settings: saved.settings.timerSettings)
        } else {
            self.clock = ClockModel(settings: saved.settings.timerSettings, active: initial.active, turnSerial: initial.turnSerial)
        }
        self.clock.names = saved.players.map { $0.name }
        recompute()
        clock.sync(active: state.active, turnSerial: state.turnSerial)
    }

    var saved: SavedGame {
        SavedGame(settings: settings, players: players, entries: entries, cursor: cursor,
                  startedAt: startedAt, clock: clock.snapshot(), notes: notes, reminders: reminders)
    }

    // MARK: Names

    /// The name shown in history lines and banners: the commander if there is one, otherwise the player.
    func name(_ p: Int) -> String {
        if settings.hasCommanders, let c = players[p].commanders.first, !c.shortName.isEmpty {
            return c.shortName
        }
        return players[p].name
    }

    func commanderName(_ ref: CommanderRef) -> String {
        let list = players[ref.player].commanders
        guard list.indices.contains(ref.index), !list[ref.index].shortName.isEmpty else { return "Commander" }
        return list[ref.index].shortName
    }

    // MARK: Recording

    /// Records one user action. Everything passed together is undone together.
    func record(_ actions: [Action]) {
        guard !actions.isEmpty else { return }
        if cursor < entries.count { entries.removeSubrange(cursor...) }
        let group = UUID()
        for action in actions {
            let before = state
            var after = state
            Reducer.apply(action, to: &after)
            if before == after { continue }
            entries.append(LogEntry(date: Date(), turn: before.turnSerial, group: group,
                                    action: action, text: describe(action, before: before, after: after)))
            state = after
            cursor += 1
        }
        clock.sync(active: state.active, turnSerial: state.turnSerial)
        turnMayHaveChanged(fire: true)
        onChange?()
    }

    func record(_ action: Action) { record([action]) }

    var canUndo: Bool { cursor > 0 }
    var canRedo: Bool { cursor < entries.count }

    func undo() {
        guard cursor > 0 else { return }
        let group = entries[cursor - 1].group
        while cursor > 0 && entries[cursor - 1].group == group { cursor -= 1 }
        recompute()
        clock.sync(active: state.active, turnSerial: state.turnSerial)
        turnMayHaveChanged(fire: false)
        onChange?()
    }

    func redo() {
        guard cursor < entries.count else { return }
        let group = entries[cursor].group
        while cursor < entries.count && entries[cursor].group == group { cursor += 1 }
        recompute()
        clock.sync(active: state.active, turnSerial: state.turnSerial)
        turnMayHaveChanged(fire: false)
        onChange?()
    }

    private func recompute() {
        var s = initial
        for e in entries[0..<cursor] { Reducer.apply(e.action, to: &s) }
        state = s
    }

    // MARK: History text

    private func describe(_ a: Action, before: GameState, after: GameState) -> String {
        switch a {
        case let .life(p, d):
            let verb = d < 0 ? "lost" : "gained"
            return "\(name(p)) \(verb) \(abs(d)) life: \(before.life[p]) → \(after.life[p])"
        case let .setLife(p, _):
            return "\(name(p))’s life set: \(before.life[p]) → \(after.life[p])"
        case let .counter(p, k, d):
            let verb = d < 0 ? "lost" : "gained"
            return "\(name(p)) \(verb) \(abs(d)) \(k.title.lowercased()) counter\(abs(d) == 1 ? "" : "s"): \(before.count(p, k)) → \(after.count(p, k))"
        case let .setCounter(p, k, _):
            return "\(name(p))’s \(k.title.lowercased()) set: \(before.count(p, k)) → \(after.count(p, k))"
        case let .cast(p, c, d):
            let who = commanderName(CommanderRef(player: p, index: c))
            if d > 0 {
                return "\(who) cast from the command zone (cast #\(after.casts[p][c])); next tax +\(after.nextTax(player: p, commander: c))"
            }
            return "\(who) cast count corrected: \(before.casts[p][c]) → \(after.casts[p][c])"
        case let .commanderDamage(v, sp, sc, d):
            let src = commanderName(CommanderRef(player: sp, index: sc))
            let key = CommanderRef(player: sp, index: sc)
            let verb = d < 0 ? "removed" : "took"
            return "\(name(v)) \(verb) \(abs(d)) commander damage \(d < 0 ? "from" : "from") \(src): \(before.damage(to: v, from: key)) → \(after.damage(to: v, from: key))"
        case let .setMonarch(p):
            if let p { return "\(name(p)) became the monarch" }
            return "The monarch marker was cleared"
        case let .setInitiative(p):
            if let p { return "\(name(p)) took the initiative" }
            return "The initiative marker was cleared"
        case .nextTurn:
            return "Turn \(after.turnSerial) begins: \(name(after.active)) (round \(after.round))"
        case let .extraTurn(p):
            return "\(name(p)) will take an extra turn"
        case let .skipNextTurn(p, on):
            return on ? "\(name(p))’s next turn will be skipped" : "\(name(p))’s skipped turn was cancelled"
        case let .setActive(p):
            return "Active player corrected to \(name(p))"
        case let .createTokens(owner, t, q):
            let pt = t.isCreature ? " \(t.power ?? 0)/\(t.toughness ?? 0)" : ""
            return "\(name(owner)) created \(q) \(t.name) token\(q == 1 ? "" : "s")\(pt)"
        case let .tokenAdd(id, c):
            let n = before.tokens.first { $0.id == id }
            return "\(n.map { name($0.owner) } ?? "A player") added \(c) more \(n?.name ?? "") token\(c == 1 ? "" : "s")"
        case let .tokenRemove(id, c):
            let n = before.tokens.first { $0.id == id }
            return "\(n.map { name($0.owner) } ?? "A player") lost \(c) \(n?.name ?? "") token\(c == 1 ? "" : "s")"
        case let .tokenEdit(id, p, t):
            let n = before.tokens.first { $0.id == id }
            return "\(n?.name ?? "Token") base stats corrected to \(p)/\(t)"
        case let .tokenModify(id, c, mod):
            guard let g = before.tokens.first(where: { $0.id == id }) else { return "Token change" }
            let n = min(c, g.quantity)
            let who = "\(n) of \(g.quantity) \(g.name)\(g.quantity == 1 ? "" : "s")"
            switch mod {
            case let .tapped(v): return "\(v ? "Tapped" : "Untapped") \(who)"
            case let .counter(k, d): return "\(d > 0 ? "Added" : "Removed") \(abs(d)) \(k) counter\(abs(d) == 1 ? "" : "s") \(d > 0 ? "to" : "from") \(who)"
            case let .bonus(p, t): return "\(who) get \(p >= 0 ? "+" : "")\(p)/\(t >= 0 ? "+" : "")\(t)"
            case let .keyword(k, on): return "\(who) \(on ? "gain" : "lose") \(k)"
            case let .sick(on): return "\(who) \(on ? "marked summoning sick" : "no longer summoning sick")"
            case let .cantAttack(v): return "\(who) \(v ? "can’t attack" : "can attack again")"
            case let .noUntap(v): return "\(who) \(v ? "won’t untap" : "will untap normally")"
            case let .controller(p): return "\(name(p)) gained control of \(who)"
            }
        case let .mergeTokens(o):
            return "Merged matching token groups for \(name(o))"
        case let .setAutoUntap(v):
            return v ? "Tokens now untap automatically each turn" : "Automatic token untapping turned off"
        case let .addEffect(e):
            return "Effect added: \(e.name) (\(e.effectText))"
        case let .updateEffect(e):
            return "Effect changed: \(e.name) (\(e.effectText))"
        case let .removeEffect(id):
            return "Effect removed: \(before.effects.first { $0.id == id }?.name ?? "effect")"
        case let .setEffectEnabled(id, on):
            let n = before.effects.first { $0.id == id }?.name ?? "effect"
            return on ? "Effect turned on: \(n)" : "Effect turned off: \(n)"
        case let .voltronBase(ref, p, t):
            return "\(commanderName(ref)) base stats set to \(p)/\(t)"
        case let .voltronKeyword(ref, k, on):
            return "\(commanderName(ref)) \(on ? "has" : "no longer has") \(k) (calculator)"
        case let .voltronAddMod(ref, mod):
            return "\(commanderName(ref)) modifier added: \(mod.name) (\(mod.effectText))"
        case let .voltronSetMod(ref, id, on):
            let n = before.voltron(ref).mods.first { $0.id == id }?.name ?? "modifier"
            return "\(commanderName(ref)) modifier \(on ? "on" : "off"): \(n)"
        case let .voltronRemoveMod(ref, id):
            let n = before.voltron(ref).mods.first { $0.id == id }?.name ?? "modifier"
            return "\(commanderName(ref)) modifier removed: \(n)"
        }
    }

    // MARK: Notes

    func addNote(_ target: NoteTarget, text: String, isPrivate: Bool, author: Int) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        notes.append(Note(target: target, text: t, isPrivate: isPrivate, author: author))
        onChange?()
    }

    func removeNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        onChange?()
    }

    func updateNote(_ id: UUID, text: String, isPrivate: Bool) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].text = text
        notes[i].isPrivate = isPrivate
        onChange?()
    }

    /// Plain-language name for what a note is attached to.
    func noteTargetName(_ t: NoteTarget) -> String {
        switch t {
        case let .player(p): return players[p].name
        case let .commander(ref): return commanderName(ref)
        case let .tokenGroup(id):
            if let g = state.tokens.first(where: { $0.id == id }) { return "\(g.name) tokens" }
            return "A token group (gone)"
        case let .effect(id):
            return state.effects.first(where: { $0.id == id })?.name ?? "An effect (gone)"
        }
    }

    // MARK: Phases and reminders

    private func turnMayHaveChanged(fire: Bool) {
        guard state.turnSerial != phaseSerial else { return }
        phaseSerial = state.turnSerial
        phase = .upkeep
        occurrences.removeAll()
        if fire { fireReminders(ReminderTiming.timing(for: .upkeep), by: state.active) }
    }

    func setPhase(_ p: TurnPhase) {
        phase = p
        fireReminders(ReminderTiming.timing(for: p), by: state.active)
        onChange?()
    }

    /// Looks for reminders that match and shows them as one banner per player.
    /// `actor` is the active player for phases, or the player who did something for events.
    func fireReminders(_ timing: ReminderTiming, by actor: Int) {
        let matching = reminders.filter { r in
            guard r.enabled, r.timing == timing else { return false }
            switch r.scope {
            case .mine: return actor == r.owner
            case .theirs: return actor != r.owner
            case .any: return true
            }
        }
        guard !matching.isEmpty else { return }
        for owner in 0..<2 {
            let mine = matching.filter { $0.owner == owner }
            guard !mine.isEmpty else { continue }
            occurrences.removeAll { $0.owner == owner && $0.label == timing.firedLabel }
            occurrences.append(ReminderOccurrence(label: timing.firedLabel, owner: owner, reminders: mine))
        }
    }

    func addReminder(_ r: Reminder) {
        reminders.append(r)
        onChange?()
    }

    func removeReminder(_ id: UUID) {
        reminders.removeAll { $0.id == id }
        for i in occurrences.indices { occurrences[i].reminders.removeAll { $0.id == id } }
        occurrences.removeAll { $0.reminders.isEmpty }
        onChange?()
    }

    func setReminderEnabled(_ id: UUID, _ on: Bool) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[i].enabled = on
        onChange?()
    }

    func acknowledge(_ reminderID: UUID, in occurrenceID: UUID) {
        guard let i = occurrences.firstIndex(where: { $0.id == occurrenceID }) else { return }
        occurrences[i].done.insert(reminderID)
        if occurrences[i].pending.isEmpty { occurrences.remove(at: i) }
    }

    func dismissOccurrence(_ id: UUID) { occurrences.removeAll { $0.id == id } }

    func acceptSuggestion() {
        if let s = suggestion { addReminder(s.reminder) }
        suggestion = nil
    }

    func declineSuggestion() { suggestion = nil }

    /// Offers a reminder based on something that just happened (like gaining the monarch).
    private func suggestAfterMarker(monarchTo p: Int?, initiativeTo q: Int?) {
        func exists(_ owner: Int, _ text: String) -> Bool {
            reminders.contains { $0.owner == owner && $0.text == text }
        }
        if let p {
            let text = "Draw a card (monarch)"
            if !exists(p, text) {
                suggestion = ReminderSuggestion(owner: p, question: "\(players[p].name) is the monarch. Remind them to draw at their end step?",
                                                reminder: Reminder(owner: p, timing: .endStep, text: text, scope: .mine))
            }
        } else if let q {
            let text = "Venture into the Undercity (initiative)"
            if !exists(q, text) {
                suggestion = ReminderSuggestion(owner: q, question: "\(players[q].name) has the initiative. Remind them to venture at their upkeep?",
                                                reminder: Reminder(owner: q, timing: .upkeep, text: text, scope: .mine))
            }
        }
    }

    // MARK: Convenience for UI

    func changeLife(_ p: Int, by delta: Int) { record(.life(player: p, delta: delta)) }

    func setLife(_ p: Int, to value: Int) { record(.setLife(player: p, to: value)) }

    func changeCounter(_ p: Int, _ kind: CounterKind, by delta: Int) {
        record(.counter(player: p, kind: kind, delta: delta))
    }

    func setCounter(_ p: Int, _ kind: CounterKind, to value: Int) {
        record(.setCounter(player: p, kind: kind, to: value))
    }

    func cast(_ p: Int, commander c: Int, by delta: Int = 1) {
        record(.cast(player: p, commander: c, delta: delta))
    }

    /// Commander combat damage. Optionally lowers life in the same action (one undo step).
    func commanderDamage(victim: Int, from ref: CommanderRef, by delta: Int, alsoLoseLife: Bool) {
        var actions: [Action] = [.commanderDamage(victim: victim, sourcePlayer: ref.player,
                                                   sourceCommander: ref.index, delta: delta)]
        if alsoLoseLife { actions.append(.life(player: victim, delta: -delta)) }
        record(actions)
    }

    func toggleMonarch(_ p: Int) {
        record(.setMonarch(player: state.monarch == p ? nil : p))
        if state.monarch == p { suggestAfterMarker(monarchTo: p, initiativeTo: nil) }
    }

    func toggleInitiative(_ p: Int) {
        record(.setInitiative(player: state.initiative == p ? nil : p))
        if state.initiative == p { suggestAfterMarker(monarchTo: nil, initiativeTo: p) }
    }

    func nextTurn() { record(.nextTurn) }

    // Tokens
    func createTokens(_ owner: Int, _ template: TokenTemplate, quantity: Int) {
        record(.createTokens(owner: owner, template: template, quantity: quantity))
        TokenLibrary.shared.remember(template)
    }
    func tokenModify(_ group: Int, count: Int, _ mod: TokenMod) { record(.tokenModify(group: group, count: count, mod: mod)) }

    /// Commanders that can deal commander damage to `victim`: the opponent's, plus
    /// the victim's own if control has changed hands.
    func commanderRefs(opponentOf victim: Int, includeOwn: Bool) -> [CommanderRef] {
        var refs: [CommanderRef] = []
        for p in [1 - victim, victim] where p == 1 - victim || includeOwn {
            for (i, c) in players[p].commanders.enumerated() where !c.name.isEmpty {
                refs.append(CommanderRef(player: p, index: i))
            }
        }
        return refs
    }

    var elapsedSeconds: Int { Int(clock.liveGame()) }
}

// MARK: - App model

/// Holds the game in progress, finished results and format presets, and saves them locally.
final class AppModel: ObservableObject {
    /// One shared model, so Siri and Shortcuts act on the same game the screen shows.
    static let shared = AppModel()

    @Published var game: Game?
    @Published var celebration: CelebrationInfo?
    @Published var results: [GameResult] = []
    @Published var presets: [FormatPreset] = FormatPreset.defaults {
        didSet { savePresets() }
    }

    private let dir: URL
    private var activeURL: URL { dir.appendingPathComponent("active-game.json") }
    private var resultsURL: URL { dir.appendingPathComponent("results.json") }
    private var presetsURL: URL { dir.appendingPathComponent("presets.json") }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("MTGTable", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
        // Testing only: `-demo` starts a ready-made Commander game in the simulator.
        if ProcessInfo.processInfo.arguments.contains("-demo"), game == nil {
            let args = ProcessInfo.processInfo.arguments
            var timer = TimerSettings()
            timer.mode = args.contains("-demoChess") ? .chess : (args.contains("-demoTurn") ? .turn : .off)
            var settings = GameSettings(formatName: "Commander", startingLife: 40, commanderSlots: 2,
                                        trackTax: true, trackCommanderDamage: true, startingPlayer: 0)
            settings.timer = timer
            settings.showArt = args.contains("-demoArt")
            let players = [
                PlayerSetup(name: "Danielle", commanders: [
                    CommanderInfo(name: "Zimone, Mystery Unraveler", colors: [.green, .blue])]),
                PlayerSetup(name: "Husband", commanders: [
                    CommanderInfo(name: "Sauron, the Dark Lord", colors: [.blue, .black, .red]),
                    CommanderInfo(name: "Frodo, Sauron’s Bane", colors: [.white, .black])]),
            ]
            start(settings: settings, players: players)
            if args.contains("-demoTokens"), let game = game { Self.seedDemoTokens(game) }
            if args.contains("-demoSiri") {
                Task { @MainActor in
                    var m = SetMonarchIntent(); m.player = PlayerEntity(id: 0, name: "Danielle")
                    _ = try? await m.perform()
                    var l = LoseLifeIntent(); l.player = PlayerEntity(id: 1, name: "Husband"); l.amount = 7
                    _ = try? await l.perform()
                    _ = try? await NextTurnIntent().perform()
                }
            }
            if args.contains("-demoWin") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.finish(outcome: .win, winner: 0) }
            }
            if args.contains("-demoExtras"), let game = game {
                game.addNote(.player(1), text: "Played a sweeper last game. Keep creatures back.", isPrivate: false, author: 0)
                game.addNote(.commander(CommanderRef(player: 1, index: 0)), text: "Needs 2 more turns to go infinite.", isPrivate: true, author: 0)
                game.reminders = [
                    Reminder(owner: 0, timing: .upkeep, text: "Draw a card", scope: .mine),
                    Reminder(owner: 0, timing: .upkeep, text: "Create 1 Treasure token", scope: .mine),
                    Reminder(owner: 0, timing: .landEnters, text: "Remember: Landfall, put a +1/+1 counter", scope: .mine),
                    Reminder(owner: 0, timing: .landEnters, text: "Gain 1 life", scope: .mine),
                    Reminder(owner: 0, timing: .landEnters, text: "Scry 1", scope: .mine),
                ]
                game.record(.voltronBase(CommanderRef(player: 0, index: 0), power: 3, toughness: 3))
                game.record(.voltronAddMod(CommanderRef(player: 0, index: 0),
                                           VoltronMod(name: "Equipment +2/+0", kind: .equipment, power: 2, toughness: 0)))
                game.record(.voltronAddMod(CommanderRef(player: 0, index: 0),
                                           VoltronMod(name: "Double strike", kind: .other, keywords: ["Double strike"])))
            }
            if args.contains("-demoEffects"), let game = game {
                game.record(.addEffect(TokenEffect(name: "Anthem", power: 1, toughness: 1, controller: 0)))
                game.record(.addEffect(TokenEffect(name: "Haste for Soldiers", keywords: ["Haste"], controller: 0,
                                                   filter: .types(["Soldier"]))))
            }
        }
    }

    /// Testing only: a few token groups so the board can be checked in the simulator.
    private static func seedDemoTokens(_ game: Game) {
        let lib = TokenLibrary.shared
        func preset(_ name: String) -> TokenTemplate? { lib.presets.first { $0.name == name } }
        if let soldier = preset("Soldier") {
            game.record(.createTokens(owner: 0, template: soldier, quantity: 5))
            game.record(.tokenModify(group: 1, count: 5, mod: .sick(false)))
            game.record(.createTokens(owner: 0, template: soldier, quantity: 3))
        }
        if let treasure = preset("Treasure") { game.record(.createTokens(owner: 0, template: treasure, quantity: 2)) }
        if let spirit = preset("Spirit") {
            game.record(.createTokens(owner: 0, template: spirit, quantity: 2))
            game.record(.tokenModify(group: game.state.tokens.last?.id ?? 0, count: 2, mod: .sick(false)))
            game.record(.tokenModify(group: game.state.tokens.last?.id ?? 0, count: 1, mod: .tapped(true)))
        }
        if let zombie = preset("Zombie") { game.record(.createTokens(owner: 1, template: zombie, quantity: 4)) }
        if let thopter = preset("Thopter") { game.record(.createTokens(owner: 1, template: thopter, quantity: 3)) }
    }

    private func load() {
        if let data = try? Data(contentsOf: presetsURL),
           let saved = try? decoder.decode([FormatPreset].self, from: data), !saved.isEmpty {
            presets = saved
        }
        if let data = try? Data(contentsOf: resultsURL),
           let saved = try? decoder.decode([GameResult].self, from: data) {
            results = saved
        }
        if let data = try? Data(contentsOf: activeURL),
           let saved = try? decoder.decode(SavedGame.self, from: data) {
            attach(Game(saved: saved))
        }
    }

    private func attach(_ g: Game) {
        g.onChange = { [weak self] in self?.saveActive() }
        game = g
    }

    func start(settings: GameSettings, players: [PlayerSetup]) {
        let g = Game(settings: settings, players: players)
        attach(g)
        saveActive()
        MTGShortcuts.updateAppShortcutParameters()
    }

    func saveActive() {
        guard let g = game else {
            try? FileManager.default.removeItem(at: activeURL)
            return
        }
        if let data = try? encoder.encode(g.saved) {
            try? data.write(to: activeURL, options: .atomic)
        }
    }

    private func saveResults() {
        if let data = try? encoder.encode(results) {
            try? data.write(to: resultsURL, options: .atomic)
        }
    }

    private func savePresets() {
        if let data = try? encoder.encode(presets) {
            try? data.write(to: presetsURL, options: .atomic)
        }
    }

    func finish(outcome: Outcome, winner: Int?) {
        guard let g = game else { return }
        let result = GameResult(
            date: Date(), formatName: g.settings.formatName, players: g.players,
            startingPlayer: g.settings.startingPlayer, winner: winner, outcome: outcome,
            durationSeconds: g.elapsedSeconds, totalTurns: g.state.turnSerial,
            rounds: g.state.round, finalLife: g.state.life,
            playerSeconds: (0..<2).map { Int(g.clock.liveUsed($0)) })
        results.insert(result, at: 0)
        saveResults()
        if (outcome == .win || outcome == .concession), let w = winner, CelebrationSettings.enabled {
            celebration = CelebrationInfo(
                winner: g.players[w].name,
                commander: g.settings.hasCommanders ? g.players[w].commanders.first?.name : nil,
                colors: g.players[w].effectiveColors,
                detail: (outcome == .concession ? "wins by concession" : "wins the game")
                    + " on turn \(g.state.turnSerial), round \(g.state.round)")
        }
        game = nil
        saveActive()
    }

    func discardGame() {
        game = nil
        saveActive()
    }

    func deleteResults(at offsets: IndexSet) {
        results.remove(atOffsets: offsets)
        saveResults()
    }

    func resetPresets() {
        presets = FormatPreset.defaults
    }
}
