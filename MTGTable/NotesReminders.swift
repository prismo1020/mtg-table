import SwiftUI

// MARK: - Shared bits

private func bubble(_ title: String, on: Bool = false, tint: Color = Color(red: 0.2, green: 0.62, blue: 0.75),
                    _ run: @escaping () -> Void) -> some View {
    Button(action: run) {
        HStack(spacing: 6) {
            if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
            Text(title).font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(1)
        }
        .padding(.horizontal, 18).frame(height: 48)
        .background(Capsule().fill(on ? tint : Color.white.opacity(0.13)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(on ? 0 : 0.14), lineWidth: 1))
        .foregroundStyle(.white)
    }
    .buttonStyle(.plain)
}

private func sectionLabel(_ t: String) -> some View {
    Text(t.uppercased()).font(.system(size: 12, weight: .bold)).tracking(1.2).opacity(0.55)
}

private func smallAction(_ title: String, danger: Bool = false, prominent: Bool = false,
                         _ run: @escaping () -> Void) -> some View {
    Button(action: run) {
        Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, 16).frame(height: 42)
            .background(Capsule().fill(danger ? Palette.danger.opacity(0.8) : (prominent ? Palette.gold : Color.white.opacity(0.14))))
            .foregroundStyle(prominent ? Color.black.opacity(0.88) : Color.white)
    }
    .buttonStyle(.plain)
}

// MARK: - Notes

struct NotesPanel: View {
    @ObservedObject var game: Game
    let player: Int
    let wide: Bool
    let close: () -> Void

    @State private var revealed: Set<UUID> = []
    @State private var target: NoteTarget
    @State private var text = ""
    @State private var isPrivate = false
    @State private var editing: UUID?
    @State private var composing = false

    init(game: Game, player: Int, wide: Bool, close: @escaping () -> Void) {
        self.game = game
        self.player = player
        self.wide = wide
        self.close = close
        _target = State(initialValue: .player(player))
    }

    private var visible: [Note] {
        game.notes.filter { !$0.isPrivate || $0.author == player }.sorted { $0.date > $1.date }
    }

    private var targets: [(NoteTarget, String)] {
        var out: [(NoteTarget, String)] = [(.player(player), "Me"), (.player(1 - player), game.players[1 - player].name)]
        for p in [player, 1 - player] {
            for (i, c) in game.players[p].commanders.enumerated() {
                out.append((.commander(CommanderRef(player: p, index: i)), c.shortName))
            }
        }
        for g in game.state.tokens { out.append((.tokenGroup(g.id), "\(g.name) x\(g.quantity) (\(game.players[g.owner].name))")) }
        for e in game.state.effects { out.append((.effect(e.id), "Effect: \(e.name)")) }
        return out
    }

    var body: some View {
        PanelFrame(title: "Notes", refW: wide ? 1100 : 760, refH: wide ? 430 : 800, close: close) {
            if composing { composer } else { list }
        }
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("Public notes show to both players. Your private notes stay hidden until you reveal them.")
                Spacer()
                smallAction("New note", prominent: true) { startNew() }
            }
            if visible.isEmpty {
                Text("No notes yet.").font(.system(size: 17)).opacity(0.6).padding(.top, 8)
            }
            ScrollView {
                VStack(spacing: 8) { ForEach(visible) { note in row(note) } }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func row(_ note: Note) -> some View {
        let hidden = note.isPrivate && !revealed.contains(note.id)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Chip(text: game.noteTargetName(note.target), fill: Color.white.opacity(0.18))
                    Chip(text: note.isPrivate ? "Private" : "Public",
                         fill: note.isPrivate ? Color.purple.opacity(0.75) : Color(red: 0.2, green: 0.62, blue: 0.75).opacity(0.85))
                    if !note.isPrivate { Chip(text: "by \(game.players[note.author].name)", fill: Color.white.opacity(0.12)) }
                }
                if hidden {
                    Label("Hidden. Tap Reveal to read it.", systemImage: "eye.slash")
                        .font(.system(size: 16, weight: .medium)).opacity(0.7)
                } else {
                    Text(note.text).font(.system(size: 18, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    if note.isPrivate {
                        Text("Hides again in a few seconds").font(.system(size: 12)).opacity(0.5)
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(spacing: 6) {
                if note.isPrivate {
                    smallAction(hidden ? "Reveal" : "Hide", prominent: hidden) { toggleReveal(note.id) }
                }
                HStack(spacing: 6) {
                    if note.author == player { smallAction("Edit") { startEditing(note) } }
                    smallAction("Delete", danger: true) { game.removeNote(note.id) }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.07)))
    }

    private func toggleReveal(_ id: UUID) {
        if revealed.contains(id) { revealed.remove(id); return }
        revealed.insert(id)
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            revealed.remove(id)
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("About")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(targets.enumerated()), id: \.offset) { _, t in
                        bubble(t.1, on: target == t.0) { target = t.0 }
                    }
                }
            }
            sectionLabel("Who can see it")
            Picker("", selection: $isPrivate) {
                Text("Public (both players)").tag(false)
                Text("Private (hidden until I reveal it)").tag(true)
            }
            .pickerStyle(.segmented)

            TextField("Write the note", text: $text, axis: .vertical)
                .lineLimit(3...5)
                .font(.system(size: 20, weight: .medium))
                .padding(14).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))

            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Button { composing = false; editing = nil } label: {
                    Text("Cancel").font(.system(size: 20, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 56).background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                Button { save() } label: {
                    Text(editing == nil ? "Add note" : "Save changes").font(.system(size: 20, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(Capsule().fill(canSave ? Palette.gold : Color.white.opacity(0.14)))
                        .foregroundStyle(canSave ? Color.black.opacity(0.88) : Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func startNew() {
        editing = nil
        text = ""
        isPrivate = false
        target = .player(player)
        composing = true
    }

    private func startEditing(_ n: Note) {
        editing = n.id
        text = n.text
        isPrivate = n.isPrivate
        target = n.target
        composing = true
    }

    private func save() {
        if let id = editing { game.updateNote(id, text: text, isPrivate: isPrivate) }
        else { game.addNote(target, text: text, isPrivate: isPrivate, author: player) }
        composing = false
        editing = nil
        text = ""
    }
}

// MARK: - Reminders

private enum ReminderAction: String, CaseIterable, Identifiable {
    case draw, gainLife, createToken, addCounter, remember
    case loseLife, scry, discard, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draw: return "Draw a card"
        case .gainLife: return "Gain life"
        case .createToken: return "Create a token"
        case .addCounter: return "Add a counter"
        case .remember: return "Remember this ability"
        case .loseLife: return "Lose life"
        case .scry: return "Scry"
        case .discard: return "Discard"
        case .custom: return "Something else"
        }
    }

    var usesAmount: Bool {
        switch self {
        case .remember, .custom: return false
        default: return true
        }
    }

    static let common: [ReminderAction] = [.draw, .gainLife, .createToken, .addCounter, .remember]
    static let more: [ReminderAction] = [.loseLife, .scry, .discard, .custom]
}

struct RemindersPanel: View {
    @ObservedObject var game: Game
    @ObservedObject private var library = ReminderLibrary.shared
    @ObservedObject private var tokens = TokenLibrary.shared
    let player: Int
    let wide: Bool
    let close: () -> Void

    // Builder state
    @State private var building = false
    @State private var editingID: UUID?
    @State private var timing: ReminderTiming?
    @State private var action: ReminderAction?
    @State private var amount = "1"
    @State private var tokenName = "Treasure"
    @State private var counterName = "+1/+1"
    @State private var detail = ""
    @State private var scope: ReminderScope = .mine
    @State private var moreTimings = false
    @State private var moreActions = false

    private var mine: [Reminder] { game.reminders.filter { $0.owner == player } }

    var body: some View {
        PanelFrame(title: building ? (editingID == nil ? "New reminder" : "Edit reminder") : "Reminders",
                   refW: wide ? 1100 : 780, refH: wide ? 430 : 820, close: close) {
            if building { builder } else { list }
        }
    }

    // MARK: List

    private var suggestions: [Reminder] {
        var out: [Reminder] = []
        func missing(_ r: Reminder) -> Bool { !mine.contains { $0.text == r.text } }
        if game.state.monarch == player {
            let r = Reminder(owner: player, timing: .endStep, text: "Draw a card (monarch)", scope: .mine)
            if missing(r) { out.append(r) }
        }
        if game.state.initiative == player {
            let r = Reminder(owner: player, timing: .upkeep, text: "Venture into the Undercity (initiative)", scope: .mine)
            if missing(r) { out.append(r) }
        }
        return out
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Reminders are prompts. You decide whether an ability actually triggers.")
                    .font(.system(size: 14)).opacity(0.6)
                Spacer()
                smallAction("New reminder", prominent: true) { startNew() }
            }
            if !suggestions.isEmpty {
                sectionLabel("Suggested for you")
                FlowLayout(spacing: 8) {
                    ForEach(suggestions) { s in
                        bubble("Add: " + s.summary(ownerName: "me"), tint: Palette.gold) { game.addReminder(s) }
                    }
                }
            }
            sectionLabel("Your reminders")
            if mine.isEmpty { Text("None yet.").font(.system(size: 16)).opacity(0.6) }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(mine) { r in row(r) }
                    if !library.saved.isEmpty {
                        sectionLabel("Saved to reuse").frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        ForEach(library.saved) { r in savedRow(r) }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func row(_ r: Reminder) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { r.enabled }, set: { game.setReminderEnabled(r.id, $0) }))
                .labelsHidden().fixedSize()
            Text(r.summary(ownerName: game.players[r.owner].name))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .opacity(r.enabled ? 1 : 0.5).lineLimit(2)
            Spacer(minLength: 6)
            smallAction(library.contains(r) ? "Saved" : "Save for later") { library.save(r) }
            smallAction("Edit") { startEditing(r) }
            smallAction("Remove", danger: true) { game.removeReminder(r.id) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.07)))
    }

    private func savedRow(_ r: Reminder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark.fill").opacity(0.6)
            Text(r.summary(ownerName: "me")).font(.system(size: 17, weight: .medium, design: .rounded)).lineLimit(2)
            Spacer(minLength: 6)
            smallAction("Use now", prominent: true) {
                var copy = r
                copy.id = UUID()
                copy.owner = player
                game.addReminder(copy)
            }
            smallAction("Forget") { library.remove(r) }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
    }

    private func startNew() {
        editingID = nil; timing = nil; action = nil; amount = "1"; detail = ""; scope = .mine
        moreTimings = false; moreActions = false
        building = true
    }

    private func startEditing(_ r: Reminder) {
        editingID = r.id; timing = r.timing; scope = r.scope
        action = .custom; detail = r.text; amount = "1"
        building = true
    }

    // MARK: Builder (tap bubbles; typing is optional)

    private var builder: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("1. When?")
                    FlowLayout(spacing: 8) {
                        ForEach(ReminderTiming.common) { t in
                            bubble(t.title, on: timing == t) { timing = t; if scope == .mine { scope = .mine } }
                        }
                        if moreTimings {
                            ForEach(ReminderTiming.more) { t in bubble(t.title, on: timing == t) { timing = t } }
                        } else {
                            bubble("More…") { moreTimings = true }
                        }
                    }

                    if timing != nil {
                        sectionLabel("2. What should I be reminded to do?")
                        FlowLayout(spacing: 8) {
                            ForEach(ReminderAction.common) { a in bubble(a.title, on: action == a) { pick(a) } }
                            if moreActions {
                                ForEach(ReminderAction.more) { a in bubble(a.title, on: action == a) { pick(a) } }
                            } else {
                                bubble("More…") { moreActions = true }
                            }
                        }
                    }

                    if let a = action, a.usesAmount {
                        sectionLabel("3. How many?")
                        FlowLayout(spacing: 8) {
                            ForEach(["1", "2", "3", "4", "5", "X"], id: \.self) { n in bubble(n, on: amount == n) { amount = n } }
                        }
                        if a == .createToken {
                            sectionLabel("Which token?")
                            FlowLayout(spacing: 8) {
                                ForEach(tokenChoices, id: \.self) { n in bubble(n, on: tokenName == n) { tokenName = n } }
                            }
                        }
                        if a == .addCounter {
                            sectionLabel("Which counter?")
                            FlowLayout(spacing: 8) {
                                ForEach(TokenKeywords.counters, id: \.self) { n in bubble(n, on: counterName == n) { counterName = n } }
                            }
                        }
                    }

                    if action != nil {
                        sectionLabel(action == .remember || action == .custom ? "Describe it" : "Extra detail (optional)")
                        TextField(action == .remember ? "For example: Landfall, put a +1/+1 counter" : "Type anything to add",
                                  text: $detail, axis: .vertical)
                            .lineLimit(1...3)
                            .font(.system(size: 19, weight: .medium))
                            .padding(12).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                        sectionLabel("Whose \(timing?.isEvent == true ? "actions" : "turn")?")
                        FlowLayout(spacing: 8) {
                            ForEach(ReminderScope.allCases) { s in
                                bubble(s.title(isEvent: timing?.isEvent ?? false), on: scope == s) { scope = s }
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: .infinity)

            if let r = draftReminder {
                Text(r.summary(ownerName: game.players[player].name))
                    .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Palette.gold)
            }
            HStack(spacing: 14) {
                Button { building = false } label: {
                    Text("Cancel").font(.system(size: 20, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 56).background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                Button { saveDraft() } label: {
                    Text("Save reminder").font(.system(size: 20, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(Capsule().fill(draftReminder != nil ? Palette.gold : Color.white.opacity(0.14)))
                        .foregroundStyle(draftReminder != nil ? Color.black.opacity(0.88) : Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(draftReminder == nil)
            }
        }
    }

    private var tokenChoices: [String] {
        var out: [String] = tokens.recents.map { $0.name }
        for n in ["Treasure", "Soldier", "Clue", "Food", "Goblin", "Spirit", "Zombie"] where !out.contains(n) { out.append(n) }
        return Array(out.prefix(10))
    }

    private func pick(_ a: ReminderAction) {
        action = a
        if !a.usesAmount && a == .remember { amount = "1" }
    }

    private func plural(_ n: String, _ word: String) -> String { n == "1" ? word : word + "s" }

    private var composedText: String? {
        guard let a = action else { return nil }
        let extra = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: String
        switch a {
        case .draw: base = amount == "1" ? "Draw a card" : "Draw \(amount) cards"
        case .gainLife: base = "Gain \(amount) life"
        case .loseLife: base = "Lose \(amount) life"
        case .scry: base = "Scry \(amount)"
        case .discard: base = amount == "1" ? "Discard a card" : "Discard \(amount) cards"
        case .createToken: base = "Create \(amount) \(tokenName) \(plural(amount, "token"))"
        case .addCounter: base = "Add \(amount) \(counterName) \(plural(amount, "counter"))"
        case .remember:
            guard !extra.isEmpty else { return nil }
            return "Remember: \(extra)"
        case .custom:
            guard !extra.isEmpty else { return nil }
            return extra
        }
        return extra.isEmpty ? base : "\(base) (\(extra))"
    }

    private var draftReminder: Reminder? {
        guard let t = timing, let text = composedText else { return nil }
        return Reminder(owner: player, timing: t, text: text, scope: scope)
    }

    private func saveDraft() {
        guard var r = draftReminder else { return }
        if let id = editingID {
            game.removeReminder(id)
            r.id = id
        }
        game.addReminder(r)
        building = false
    }
}

// MARK: - Banner shown on a player's side

struct ReminderBanner: View {
    @ObservedObject var game: Game
    let player: Int
    let style: ZoneStyle

    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(spacing: 8) {
            if let s = game.suggestion, s.owner == player { suggestionCard(s) }
            ForEach(game.occurrences.filter { $0.owner == player }) { o in occurrenceCard(o) }
        }
        .frame(maxWidth: 440)
        .animation(.easeInOut(duration: 0.2), value: game.occurrences)
    }

    private func suggestionCard(_ s: ReminderSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(s.question, systemImage: "lightbulb.fill")
                .font(.system(size: 17, weight: .semibold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { game.acceptSuggestion() } label: {
                    Text("Add it").font(.system(size: 16, weight: .bold, design: .rounded))
                        .padding(.horizontal, 20).frame(height: 44)
                        .background(Capsule().fill(Palette.gold)).foregroundStyle(Color.black.opacity(0.88))
                }
                .buttonStyle(.plain)
                Button { game.declineSuggestion() } label: {
                    Text("No thanks").font(.system(size: 16, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 20).frame(height: 44)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.gold.opacity(0.7), lineWidth: 1.5))
        .foregroundStyle(.white)
    }

    private func occurrenceCard(_ o: ReminderOccurrence) -> some View {
        let open = expanded.contains(o.id)
        let n = o.pending.count
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if open { expanded.remove(o.id) } else { expanded.insert(o.id) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bell.fill")
                    Text("\(o.label) · \(n) reminder\(n == 1 ? "" : "s")")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Spacer(minLength: 4)
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 14, weight: .bold))
                }
                .padding(.horizontal, 16).frame(height: 50)
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(o.pending) { r in
                        HStack(spacing: 10) {
                            Text(r.text).font(.system(size: 17, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Button { game.acknowledge(r.id, in: o.id) } label: {
                                Text("Done").font(.system(size: 15, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 16).frame(height: 40)
                                    .background(Capsule().fill(Palette.good)).foregroundStyle(Color.black.opacity(0.88))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button { game.dismissOccurrence(o.id) } label: {
                        Text("Dismiss all for now").font(.system(size: 14, weight: .semibold)).opacity(0.75)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        .foregroundStyle(.white)
    }
}
