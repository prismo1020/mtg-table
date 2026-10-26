import SwiftUI

struct SetupView: View {
    @EnvironmentObject var app: AppModel

    @AppStorage("playerName1") private var name1 = "Player 1"
    @AppStorage("playerName2") private var name2 = "Player 2"

    @State private var presetID = "commander"
    @State private var startingLife = 40
    @State private var slots = 2
    @State private var tax = true
    @State private var damage = true
    @State private var setups = [PlayerSetup(name: ""), PlayerSetup(name: "")]
    @State private var startChoice = 0            // 0 = random, 1 = player 1, 2 = player 2

    @AppStorage("showArt") private var showArt = false
    @AppStorage("clockMode") private var clockMode = "off"
    @AppStorage("chessMin1") private var chessMin1 = 25
    @AppStorage("chessMin2") private var chessMin2 = 25
    @AppStorage("turnLimit") private var turnLimit = 0
    @AppStorage("alertSound") private var alertSound = true

    @State private var showSettings = false
    @State private var showResults = false

    // Random starting-player animation
    @State private var picking = false
    @State private var highlight = 0
    @State private var revealed: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    formatSection
                    optionsSection
                    HStack(alignment: .top, spacing: 20) {
                        playerCard(0)
                        playerCard(1)
                    }
                    startSection
                }
                .padding(28)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New game")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showResults = true } label: { Label("Past games", systemImage: "clock") }
                    Button { showSettings = true } label: { Label("Formats", systemImage: "slider.horizontal.3") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(app) }
            .sheet(isPresented: $showResults) { ResultsView().environmentObject(app) }
            .overlay { if picking { pickerOverlay } }
            .onAppear {
                syncSlots()
                if let p = app.presets.first(where: { $0.id == presetID }) { applyPreset(p) }
            }
            .onChange(of: slots) { _, _ in syncSlots() }
        }
    }

    // MARK: Format

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Format").font(.title3.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(app.presets) { preset in
                        Button {
                            presetID = preset.id
                            applyPreset(preset)
                        } label: {
                            VStack(spacing: 2) {
                                Text(preset.name).font(.headline)
                                Text("\(preset.startingLife) life").font(.caption).opacity(0.7)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(presetID == preset.id ? Color.accentColor : Color.white.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(presetID == preset.id ? Color.black : Color.white)
                        }
                    }
                }
            }

            HStack(spacing: 24) {
                Stepper("Starting life: \(startingLife)", value: $startingLife, in: 1...200)
                    .frame(maxWidth: 320)
                Picker("Commanders each", selection: $slots) {
                    Text("None").tag(0)
                    Text("1").tag(1)
                    Text("2 (partners)").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)
            }
            if slots > 0 {
                HStack(spacing: 28) {
                    Toggle("Commander tax", isOn: $tax)
                    Toggle("Commander damage", isOn: $damage)
                }
                .frame(maxWidth: 520)
            }
            if let note = app.presets.first(where: { $0.id == presetID })?.note, !note.isEmpty {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Timers and artwork

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Options").font(.title3.bold())

            if slots > 0 {
                Toggle("Show commander cards beside each name", isOn: $showArt)
                    .frame(maxWidth: 520)
            }

            Picker("Timer", selection: $clockMode) {
                Text("No timer").tag("off")
                Text("Turn timer").tag("turn")
                Text("Chess clock").tag("chess")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)

            if clockMode == "turn" {
                Stepper(turnLimit == 0 ? "Turn limit: none (just show time)" : "Turn limit alert: \(turnLimit) min",
                        value: $turnLimit, in: 0...60)
                    .frame(maxWidth: 520)
            }
            if clockMode == "chess" {
                HStack(spacing: 28) {
                    Stepper("\(name1.isEmpty ? "Player 1" : name1): \(chessMin1) min", value: $chessMin1, in: 1...180)
                    Stepper("\(name2.isEmpty ? "Player 2" : name2): \(chessMin2) min", value: $chessMin2, in: 1...180)
                }
                .frame(maxWidth: 780)
            }
            if clockMode != "off" {
                Toggle("Sound alerts (play always continues)", isOn: $alertSound)
                    .frame(maxWidth: 520)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyPreset(_ p: FormatPreset) {
        startingLife = p.startingLife
        slots = p.commanderSlots
        tax = p.trackTax
        damage = p.trackCommanderDamage
        syncSlots()
    }

    private func syncSlots() {
        for i in 0..<2 {
            while setups[i].commanders.count < slots { setups[i].commanders.append(CommanderInfo()) }
            if setups[i].commanders.count > slots { setups[i].commanders = Array(setups[i].commanders.prefix(slots)) }
        }
    }

    // MARK: Players

    private func nameBinding(_ i: Int) -> Binding<String> {
        i == 0 ? $name1 : $name2
    }

    private func playerCard(_ i: Int) -> some View {
        let colors = setups[i].effectiveColors
        let dark = Identity.prefersDarkText(for: colors)
        return VStack(alignment: .leading, spacing: 14) {
            Text("PLAYER \(i + 1)").font(.caption.weight(.bold)).opacity(0.7)
            TextField("Name", text: nameBinding(i))
                .font(.title3.weight(.semibold))
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)

            if slots > 0 {
                ForEach(0..<slots, id: \.self) { j in
                    if setups[i].commanders.indices.contains(j) {
                        CommanderEditor(info: $setups[i].commanders[j],
                                        label: j == 0 ? "Commander" : "Partner / second commander")
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Panel color (optional)").font(.footnote).opacity(0.8)
                    ColorPips(colors: $setups[i].colors)
                }
            }
        }
        .padding(18)
        .foregroundStyle(dark ? Color.black : Color.white)
        .background(Identity.background(for: colors), in: RoundedRectangle(cornerRadius: 20))
        .frame(maxWidth: .infinity)
    }

    // MARK: Start

    private var startSection: some View {
        VStack(spacing: 16) {
            Picker("Who goes first?", selection: $startChoice) {
                Text("Random").tag(0)
                Text(name1.isEmpty ? "Player 1" : name1).tag(1)
                Text(name2.isEmpty ? "Player 2" : name2).tag(2)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 560)

            Button {
                begin()
            } label: {
                Text("Start game")
                    .font(.title2.bold())
                    .foregroundStyle(.black)
                    .frame(maxWidth: 420)
                    .padding(.vertical, 18)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func begin() {
        if startChoice == 0 { runRandom() } else { launch(first: startChoice - 1) }
    }

    private func launch(first: Int) {
        let preset = app.presets.first(where: { $0.id == presetID })
        let names = [name1, name2].enumerated().map { i, n -> String in
            let t = n.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "Player \(i + 1)" : t
        }
        var players: [PlayerSetup] = []
        for i in 0..<2 {
            var s = setups[i]
            s.name = names[i]
            if slots > 0 {
                var list: [CommanderInfo] = []
                for (j, c) in s.commanders.enumerated() {
                    let trimmed = c.name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        list.append(CommanderInfo(name: trimmed, colors: c.colors))
                    } else if j == 0 {
                        list.append(CommanderInfo(name: "\(names[i])’s commander", colors: c.colors))
                    }
                }
                s.commanders = list
            } else {
                s.commanders = []
            }
            players.append(s)
        }
        var settings = GameSettings(
            formatName: preset?.name ?? "Custom", startingLife: startingLife,
            commanderSlots: slots, trackTax: tax && slots > 0,
            trackCommanderDamage: damage && slots > 0, startingPlayer: first)
        var timer = TimerSettings()
        timer.mode = clockMode == "turn" ? .turn : (clockMode == "chess" ? .chess : .off)
        timer.chessMinutes = [chessMin1, chessMin2]
        timer.turnLimitMinutes = turnLimit
        timer.soundAlerts = alertSound
        settings.timer = timer
        settings.showArt = showArt && slots > 0
        for p in players { for c in p.commanders { CardStore.shared.remember(name: c.name, colors: c.colors) } }
        app.start(settings: settings, players: players)
    }

    // MARK: Random starting player

    private func runRandom() {
        picking = true
        revealed = nil
        let final = Int.random(in: 0..<2)
        let startIndex = Int.random(in: 0..<2)
        var steps = 16
        if (startIndex + steps - 1) % 2 != final { steps += 1 }
        Task { @MainActor in
            for step in 0..<steps {
                highlight = (startIndex + step) % 2
                let t = Double(step) / Double(steps)
                try? await Task.sleep(nanoseconds: UInt64((0.07 + 0.38 * t * t) * 1_000_000_000))
            }
            revealed = final
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            picking = false
            launch(first: final)
        }
    }

    private var pickerOverlay: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 30) {
                Text(revealed == nil ? "Choosing who goes first…" : "Goes first!")
                    .font(.largeTitle.bold())
                HStack(spacing: 40) {
                    ForEach(0..<2, id: \.self) { i in
                        let n = (i == 0 ? name1 : name2).trimmingCharacters(in: .whitespaces)
                        let on = revealed == i || (revealed == nil && highlight == i)
                        Text(n.isEmpty ? "Player \(i + 1)" : n)
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 50).padding(.vertical, 40)
                            .background(on ? Color.accentColor : Color.white.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 28))
                            .foregroundStyle(on ? Color.black : Color.white)
                            .scaleEffect(revealed == i ? 1.15 : 1)
                            .animation(.spring(duration: 0.25), value: on)
                    }
                }
            }
        }
    }
}

// MARK: - Pieces

struct ColorPips: View {
    @Binding var colors: [ManaColor]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ManaColor.allCases) { c in
                let on = colors.contains(c)
                Button {
                    if on { colors.removeAll { $0 == c } }
                    else { colors = Identity.sorted(colors + [c]) }
                } label: {
                    Text(c.rawValue)
                        .font(.headline.bold())
                        .frame(width: 44, height: 44)
                        .background(c.color, in: Circle())
                        .foregroundStyle(c == .white ? .black : .white)
                        .overlay(Circle().stroke(.white, lineWidth: on ? 3 : 0))
                        .opacity(on ? 1 : 0.45)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CommanderEditor: View {
    @Binding var info: CommanderInfo
    let label: String

    @ObservedObject private var store = CardStore.shared
    @State private var looking = false
    @State private var message: String?

    private var suggestions: [LibraryEntry] {
        guard store.exactMatch(info.name) == nil else { return [] }
        return store.suggestions(for: info.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.footnote.weight(.semibold)).opacity(0.85)

            HStack(spacing: 8) {
                TextField("Commander name", text: $info.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)

                Menu {
                    ForEach(store.library) { entry in
                        Button("\(entry.name)  (\(Identity.label(for: entry.colors)))") { choose(entry) }
                    }
                } label: {
                    Label("Choose", systemImage: "list.bullet")
                        .padding(.horizontal, 12).padding(.vertical, 12)
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onChange(of: info.name) { _, new in
                // Typing a known commander's full name fills in its official name and colors.
                if let hit = store.exactMatch(new), (hit.name != new || hit.colors != info.colors) {
                    info.name = hit.name
                    info.colors = hit.colors
                }
            }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { entry in
                            Button { choose(entry) } label: {
                                HStack(spacing: 6) {
                                    ForEach(entry.colors) { c in
                                        Circle().fill(c.color).frame(width: 12, height: 12)
                                            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                                    }
                                    Text(entry.name).font(.subheadline.weight(.semibold))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(.black.opacity(0.35), in: Capsule())
                                .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }

            HStack {
                ColorPips(colors: $info.colors)
                Spacer()
                Button { lookUp() } label: {
                    if looking { ProgressView() }
                    else { Label("Look up online", systemImage: "wand.and.stars") }
                }
                .buttonStyle(.bordered)
                .disabled(info.name.trimmingCharacters(in: .whitespaces).isEmpty || looking)
            }
            if let message { Text(message).font(.footnote).opacity(0.85) }
        }
    }

    private func choose(_ entry: LibraryEntry) {
        info.name = entry.name
        info.colors = entry.colors
        message = nil
    }

    private func lookUp() {
        let query = info.name.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        looking = true
        message = nil
        Task {
            do {
                let card = try await CardStore.shared.lookup(query)
                await MainActor.run {
                    info.name = card.name
                    info.colors = card.manaColors
                    message = "Found \(card.name) (\(Identity.label(for: card.manaColors)))"
                    looking = false
                }
            } catch ScryfallError.network {
                await MainActor.run {
                    message = "Couldn’t reach Scryfall. Pick colors by hand."
                    looking = false
                }
            } catch {
                await MainActor.run {
                    message = "No card found. Check the spelling or pick colors by hand."
                    looking = false
                }
            }
        }
    }
}
