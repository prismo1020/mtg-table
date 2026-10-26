import AppIntents

// MARK: - Players Siri can name

struct PlayerEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Player" }
    static var defaultQuery = PlayerQuery()

    var id: Int
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// Matches what you say against the players in the game in progress: their names or their commanders.
struct PlayerQuery: EntityStringQuery {
    @MainActor private func all() -> [(PlayerEntity, [String])] {
        guard let g = AppModel.shared.game else { return [] }
        return (0..<2).map { p in
            var aliases = [g.players[p].name]
            aliases += g.players[p].commanders.map { $0.shortName }
            aliases += g.players[p].commanders.map { $0.name }
            return (PlayerEntity(id: p, name: g.players[p].name), aliases)
        }
    }

    @MainActor func entities(for identifiers: [Int]) async throws -> [PlayerEntity] {
        all().map { $0.0 }.filter { identifiers.contains($0.id) }
    }

    @MainActor func entities(matching string: String) async throws -> [PlayerEntity] {
        let q = string.lowercased()
        return all().filter { $0.1.contains { $0.lowercased().contains(q) || q.contains($0.lowercased()) } }.map { $0.0 }
    }

    @MainActor func suggestedEntities() async throws -> [PlayerEntity] { all().map { $0.0 } }
}

@MainActor private func currentGame() -> Game? { AppModel.shared.game }

private let noGame: IntentDialog = "There’s no game in progress in MTG Table. Start one first."

// MARK: - Intents

struct SetMonarchIntent: AppIntent {
    static var title: LocalizedStringResource = "Make someone the monarch"
    static var description = IntentDescription("Gives the monarch marker to a player in the current game.")

    @Parameter(title: "Player") var player: PlayerEntity

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let g = currentGame() else { return .result(dialog: noGame) }
        if g.state.monarch == player.id { return .result(dialog: "\(player.name) is already the monarch.") }
        g.record(.setMonarch(player: player.id))
        return .result(dialog: "\(player.name) is now the monarch.")
    }
}

struct SetInitiativeIntent: AppIntent {
    static var title: LocalizedStringResource = "Give someone the initiative"
    static var description = IntentDescription("Gives the initiative marker to a player in the current game.")

    @Parameter(title: "Player") var player: PlayerEntity

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let g = currentGame() else { return .result(dialog: noGame) }
        if g.state.initiative == player.id { return .result(dialog: "\(player.name) already has the initiative.") }
        g.record(.setInitiative(player: player.id))
        return .result(dialog: "\(player.name) took the initiative.")
    }
}

struct GainLifeIntent: AppIntent {
    static var title: LocalizedStringResource = "Gain life"
    static var description = IntentDescription("Adds life to a player in the current game.")

    @Parameter(title: "Player") var player: PlayerEntity
    @Parameter(title: "Amount", requestValueDialog: "How much life?") var amount: Int

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let g = currentGame() else { return .result(dialog: noGame) }
        guard amount > 0 else { return .result(dialog: "The amount has to be more than zero.") }
        g.changeLife(player.id, by: amount)
        return .result(dialog: "\(player.name) gained \(amount) life and is at \(g.state.life[player.id]).")
    }
}

struct LoseLifeIntent: AppIntent {
    static var title: LocalizedStringResource = "Lose life"
    static var description = IntentDescription("Takes life from a player in the current game.")

    @Parameter(title: "Player") var player: PlayerEntity
    @Parameter(title: "Amount", requestValueDialog: "How much life?") var amount: Int

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let g = currentGame() else { return .result(dialog: noGame) }
        guard amount > 0 else { return .result(dialog: "The amount has to be more than zero.") }
        g.changeLife(player.id, by: -amount)
        return .result(dialog: "\(player.name) lost \(amount) life and is at \(g.state.life[player.id]).")
    }
}

struct AddPoisonIntent: AppIntent {
    static var title: LocalizedStringResource = "Give poison counters"
    static var description = IntentDescription("Adds poison counters to a player in the current game.")

    @Parameter(title: "Player") var player: PlayerEntity
    @Parameter(title: "Amount", requestValueDialog: "How many poison counters?") var amount: Int

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let g = currentGame() else { return .result(dialog: noGame) }
        guard amount > 0 else { return .result(dialog: "The amount has to be more than zero.") }
        g.changeCounter(player.id, .poison, by: amount)
        return .result(dialog: "\(player.name) now has \(g.state.count(player.id, .poison)) poison counters.")
    }
}

struct NextTurnIntent: AppIntent {
    static var title: LocalizedStringResource = "Next turn"
    static var description = IntentDescription("Passes the turn in the current game.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let g = currentGame() else { return .result(dialog: noGame) }
        g.nextTurn()
        return .result(dialog: "It’s \(g.players[g.state.active].name)’s turn.")
    }
}

struct UndoIntent: AppIntent {
    static var title: LocalizedStringResource = "Undo the last change"
    static var description = IntentDescription("Undoes the last change in the current game.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let g = currentGame() else { return .result(dialog: noGame) }
        guard g.canUndo else { return .result(dialog: "There’s nothing to undo.") }
        g.undo()
        return .result(dialog: "Undone.")
    }
}

struct LifeTotalsIntent: AppIntent {
    static var title: LocalizedStringResource = "Read the life totals"
    static var description = IntentDescription("Tells you each player’s life total and whose turn it is.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let g = currentGame() else { return .result(dialog: noGame) }
        let s = g.state
        let totals = (0..<2).map { "\(g.players[$0].name) has \(s.life[$0])" }.joined(separator: ", and ")
        return .result(dialog: "\(totals). It’s \(g.players[s.active].name)’s turn.")
    }
}

// MARK: - Phrases

struct MTGShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetMonarchIntent(),
                    phrases: ["\(\.$player) is now the monarch in \(.applicationName)",
                              "Make \(\.$player) the monarch in \(.applicationName)"],
                    shortTitle: "Set the monarch", systemImageName: "crown.fill")
        AppShortcut(intent: SetInitiativeIntent(),
                    phrases: ["\(\.$player) takes the initiative in \(.applicationName)",
                              "Give \(\.$player) the initiative in \(.applicationName)"],
                    shortTitle: "Set the initiative", systemImageName: "map.fill")
        AppShortcut(intent: GainLifeIntent(),
                    phrases: ["\(\.$player) gains life in \(.applicationName)",
                              "Give \(\.$player) life in \(.applicationName)"],
                    shortTitle: "Gain life", systemImageName: "heart.fill")
        AppShortcut(intent: LoseLifeIntent(),
                    phrases: ["\(\.$player) loses life in \(.applicationName)",
                              "Hit \(\.$player) in \(.applicationName)"],
                    shortTitle: "Lose life", systemImageName: "bolt.heart.fill")
        AppShortcut(intent: AddPoisonIntent(),
                    phrases: ["Give \(\.$player) poison in \(.applicationName)"],
                    shortTitle: "Add poison", systemImageName: "drop.fill")
        AppShortcut(intent: NextTurnIntent(),
                    phrases: ["Next turn in \(.applicationName)", "Pass the turn in \(.applicationName)"],
                    shortTitle: "Next turn", systemImageName: "forward.end.fill")
        AppShortcut(intent: UndoIntent(),
                    phrases: ["Undo in \(.applicationName)"],
                    shortTitle: "Undo", systemImageName: "arrow.uturn.backward")
        AppShortcut(intent: LifeTotalsIntent(),
                    phrases: ["What are the life totals in \(.applicationName)",
                              "Read the life totals in \(.applicationName)"],
                    shortTitle: "Life totals", systemImageName: "list.number")
    }
}
