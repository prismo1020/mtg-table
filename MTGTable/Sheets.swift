import SwiftUI

// MARK: - History

struct HistoryView: View {
    @ObservedObject var game: Game
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if game.entries.isEmpty {
                    ContentUnavailableView("Nothing yet", systemImage: "list.bullet",
                                           description: Text("Every life change, counter, cast and turn shows up here."))
                } else {
                    List {
                        ForEach(Array(game.entries.enumerated()).reversed(), id: \.element.id) { index, entry in
                            let undone = index >= game.cursor
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.text)
                                    .font(.headline)
                                    .strikethrough(undone)
                                Text("Turn \(entry.turn) · \(entry.date.formatted(date: .omitted, time: .standard))\(undone ? " · undone" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .opacity(undone ? 0.45 : 1)
                        }
                    }
                }
            }
            .navigationTitle("Game history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { game.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .disabled(!game.canUndo)
                    Button { game.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                        .disabled(!game.canRedo)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - End game

struct EndGameView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var game: Game
    @Environment(\.dismiss) private var dismiss

    private enum Choice: Hashable {
        case win(Int), draw, concede(Int), unfinished
    }

    @State private var choice: Choice?

    var body: some View {
        NavigationStack {
            List {
                let warns = trackedWarnings
                if !warns.isEmpty {
                    Section("Heads up") {
                        ForEach(warns, id: \.self) { w in
                            Label(w, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        }
                        Text("These are only reminders. Nothing is saved until you confirm a result below.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Result") {
                    ForEach(0..<2, id: \.self) { p in
                        row("\(game.players[p].name) won", .win(p))
                    }
                    row("Draw", .draw)
                    ForEach(0..<2, id: \.self) { p in
                        row("\(game.players[p].name) conceded", .concede(p))
                    }
                    row("Unfinished (save without a winner)", .unfinished)
                }

                Section {
                    Button {
                        confirm()
                    } label: {
                        Text("Confirm and save result").font(.headline).frame(maxWidth: .infinity)
                    }
                    .disabled(choice == nil)
                }
            }
            .navigationTitle("End game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Keep playing") { dismiss() } } }
        }
    }

    private var trackedWarnings: [String] {
        var out: [String] = []
        let s = game.state
        for p in 0..<2 {
            if s.life[p] <= 0 { out.append("\(game.players[p].name) is at \(s.life[p]) life.") }
            if s.count(p, .poison) >= poisonLethal { out.append("\(game.players[p].name) has \(s.count(p, .poison)) poison counters.") }
            if game.settings.trackCommanderDamage {
                for ref in game.commanderRefs(opponentOf: p, includeOwn: true) {
                    let d = s.damage(to: p, from: ref)
                    if d >= commanderDamageLethal {
                        out.append("\(game.players[p].name) took \(d) commander damage from \(game.commanderName(ref)).")
                    }
                }
            }
        }
        return out
    }

    private func row(_ title: String, _ value: Choice) -> some View {
        Button {
            choice = value
        } label: {
            HStack {
                Text(title)
                Spacer()
                if choice == value { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
            }
        }
        .foregroundStyle(.primary)
    }

    private func confirm() {
        guard let choice else { return }
        dismiss()
        switch choice {
        case let .win(p): app.finish(outcome: .win, winner: p)
        case .draw: app.finish(outcome: .draw, winner: nil)
        case let .concede(p): app.finish(outcome: .concession, winner: 1 - p)
        case .unfinished: app.finish(outcome: .unfinished, winner: nil)
        }
    }
}

// MARK: - Format presets

struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CelebrationSettings.onKey) private var celebrate = true
    @AppStorage(CelebrationSettings.soundKey) private var celebrateSound = true
    @AppStorage(CelebrationSettings.animationKey) private var celebrateAnimation = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Edit the starting life and which commander tools each format uses. Changes apply to new games.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach($app.presets) { $preset in
                    Section(preset.name) {
                        if preset.id == "custom" {
                            TextField("Name", text: $preset.name)
                        }
                        Stepper("Starting life: \(preset.startingLife)", value: $preset.startingLife, in: 1...200)
                        Picker("Commanders each", selection: $preset.commanderSlots) {
                            Text("None").tag(0)
                            Text("1").tag(1)
                            Text("2 (partners)").tag(2)
                        }
                        if preset.commanderSlots > 0 {
                            Toggle("Commander tax", isOn: $preset.trackTax)
                            Toggle("Commander damage", isOn: $preset.trackCommanderDamage)
                        }
                    }
                }
                Section("Winner celebration") {
                    Toggle("Celebrate when a game is won", isOn: $celebrate)
                    Toggle("Drum roll and trumpet", isOn: $celebrateSound)
                    Toggle("Winner animation and confetti", isOn: $celebrateAnimation)
                    Button("Preview it") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            app.celebration = CelebrationInfo(winner: "Danielle", commander: "Zimone, Mystery Unraveler",
                                                              colors: [.green, .blue], detail: "wins the game on turn 9, round 5")
                        }
                    }
                }
                Section {
                    Button("Reset all formats to defaults", role: .destructive) { app.resetPresets() }
                }
            }
            .navigationTitle("Formats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Past games (a simple list for now; full stats come later)

struct ResultsView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if app.results.isEmpty {
                    ContentUnavailableView("No saved games", systemImage: "trophy",
                                           description: Text("Finished games show up here."))
                } else {
                    List {
                        ForEach(app.results) { r in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(headline(r)).font(.headline)
                                Text("\(r.formatName) · \(r.date.formatted(date: .abbreviated, time: .shortened)) · \(duration(r.durationSeconds)) · \(r.totalTurns) turns, \(r.rounds) round\(r.rounds == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { app.deleteResults(at: $0) }
                    }
                }
            }
            .navigationTitle("Past games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func headline(_ r: GameResult) -> String {
        switch r.outcome {
        case .win: return "\(r.players[r.winner ?? 0].name) won"
        case .concession: return "\(r.players[1 - (r.winner ?? 0)].name) conceded"
        case .draw: return "Draw"
        case .unfinished: return "Unfinished"
        }
    }

    private func duration(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(max(1, m))m"
    }
}
