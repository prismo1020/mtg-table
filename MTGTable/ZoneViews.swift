import SwiftUI

// MARK: - Building blocks

/// Lays content out at a fixed reference size, then scales it to fit the space it is given.
struct FitView<Content: View>: View {
    let refW: CGFloat
    let refH: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / refW, geo.size.height / refH)
            content
                .frame(width: refW, height: refH)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// A long-press on a commander's name asks the table to show its full card, facing that player.
struct PreviewRequest: Identifiable, Equatable {
    var id = UUID()
    var player: Int
    var refs: [CommanderRef]
}

enum AdjustTarget: Equatable {
    case life
    case counter(CounterKind)
}

enum ZonePanelKind: Equatable {
    case adjust(AdjustTarget)
    case counters
    case commander
    case group(Int)
    case effects
    case attackPower
    case notes
    case reminders
    case voltron(Int)
}

// MARK: - A player's half of the table

struct PlayerZone: View {
    @ObservedObject var game: Game
    @ObservedObject var clock: ClockModel
    @EnvironmentObject var drag: AttackDrag
    let player: Int
    let rotated: Bool
    let inset: CGFloat
    var onPreview: (PreviewRequest) -> Void = { _ in }
    var onAddToken: () -> Void = {}
    var onStartAttack: (AttackRequest) -> Void = { _ in }

    @State private var panel: ZonePanelKind?
    @State private var artRefs: [String?] = []
    @State private var alsoLoseLife = true
    @State private var includeOwn = false
    @State private var dismissed: Set<String> = []

    private var colors: [ManaColor] { game.players[player].effectiveColors }
    private var showArt: Bool { game.settings.artOn }
    private var style: ZoneStyle { ZoneStyle(dark: Identity.prefersDarkText(for: colors)) }
    private var isActive: Bool { game.state.active == player }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width / max(geo.size.height, 1) > 2.0
            ZStack(alignment: .top) {
                zoneBackground

                let availH = max(120, geo.size.height - 12 - 24 - inset)
                let card = cardSize(availH)
                HStack(alignment: .top, spacing: 14) {
                    if cardCount > 0 { cardColumn(card) }
                    FitView(refW: wide ? 1340 : 1000, refH: wide ? 392 : 596) {
                        if wide { wideContent } else { tallContent }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12 + inset)

                if !isActive {
                    RoundedRectangle(cornerRadius: 26).fill(Color.black.opacity(0.26)).allowsHitTesting(false)
                }
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(Color.white.opacity(isActive ? 0.95 : 0), lineWidth: 5)
                    .shadow(color: .white.opacity(isActive ? 0.5 : 0), radius: 14)
                    .allowsHitTesting(false)

                warningBar.padding(.top, 14).padding(.horizontal, 24)

                ReminderBanner(game: game, player: player, style: style)
                    .padding(.top, 16).padding(.horizontal, 24)

                panelOverlay(wide: wide)
            }
            .padding(6)
            .rotationEffect(.degrees(rotated ? 180 : 0))
            .onChange(of: panel) { _, new in drag.setBlocked(player, new != nil) }
            .onAppear {
                // Testing only: open the Voltron calculator straight away in the simulator.
                if ProcessInfo.processInfo.arguments.contains("-demoVoltron"), player == 0, game.settings.hasCommanders {
                    panel = .voltron(0)
                }
            }
        }
        .foregroundStyle(style.fg)
    }

    // MARK: Layouts

    private var wideContent: some View {
        VStack(spacing: 10) {
            header.frame(height: 64)
            HStack(alignment: .top, spacing: 22) {
                lifeBlock.frame(width: 430, height: 250)
                tokenArea(cardHeight: 204).frame(width: 888, height: 250)
            }
            actionRow.frame(height: 56)
        }
    }

    private var tallContent: some View {
        VStack(spacing: 10) {
            header.frame(height: 64)
            lifeBlock.frame(width: 430, height: 190)
            tokenArea(cardHeight: 232).frame(height: 270)
            actionRow.frame(height: 56)
        }
    }

    // MARK: Background (always the commander's color identity) and commander cards

    private var zoneBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26).fill(Identity.background(for: colors))
            RoundedRectangle(cornerRadius: 26)
                .fill(LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.22)],
                                     startPoint: .top, endPoint: .bottom))
        }
        // Decoration only: it must never catch taps meant for buttons.
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .allowsHitTesting(false)
    }

    private var cardCount: Int { showArt ? game.players[player].commanders.count : 0 }

    private func cardSize(_ availH: CGFloat) -> CGSize {
        let n = CGFloat(max(cardCount, 1))
        let ch = (availH - 8 * (n - 1)) / n
        let cw = min(ch * 0.718, 172)
        return CGSize(width: cw, height: cw / 0.718)
    }

    private func cardColumn(_ size: CGSize) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(game.players[player].commanders.enumerated()), id: \.offset) { i, c in
                CommanderCardView(name: c.name, size: size, style: style,
                                  commanderRef: CommanderRef(player: player, index: i),
                                  claimsDrag: game.settings.trackCommanderDamage) {
                    onPreview(PreviewRequest(player: player, refs: [CommanderRef(player: player, index: i)]))
                }
            }
        }
        .frame(width: size.width)
    }

    // MARK: Header

    private var allCommanderRefs: [CommanderRef] {
        game.players[player].commanders.indices.map { CommanderRef(player: player, index: $0) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.players[player].name)
                    .font(.system(size: 28, weight: .bold, design: .rounded)).lineLimit(1)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.6) {
                        if game.settings.hasCommanders, !allCommanderRefs.isEmpty {
                            onPreview(PreviewRequest(player: player, refs: allCommanderRefs))
                        }
                    }
                commanderChips
            }

            Spacer(minLength: 8)

            statusPills

            if isActive {
                Text("YOUR TURN")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(1.2)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Capsule().fill(style.fg))
                    .foregroundStyle(style.inverse)
            }
            clockView
        }
    }

    /// Counters, commander damage taken and commander tax, shown whenever they are above zero.
    @ViewBuilder private var statusPills: some View {
        let infos = counterInfos + commanderInfos
        if !infos.isEmpty {
            HStack(spacing: 8) {
                ForEach(infos) { info in
                    Button {
                        withAnimation { panel = info.opensCommander ? .commander : .counters }
                    } label: {
                        InfoPill(icon: info.icon, text: info.text, style: style, warn: info.warn)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// One chip per commander. Dragging a chip toward the opponent deals commander damage from it.
    @ViewBuilder private var commanderChips: some View {
        if game.settings.hasCommanders, !game.players[player].commanders.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(game.players[player].commanders.enumerated()), id: \.offset) { i, c in
                    let ref = CommanderRef(player: player, index: i)
                    HStack(spacing: 6) {
                        if game.settings.trackCommanderDamage {
                            Image(systemName: "arrow.up.forward").font(.system(size: 11, weight: .heavy))
                        }
                        ForEach(Identity.sorted(c.colors)) { col in
                            Circle().fill(col.color).frame(width: 10, height: 10)
                                .overlay(Circle().stroke(style.fg.opacity(0.6), lineWidth: 1))
                        }
                        Text(c.shortName).font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1)
                    }
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(style.chip))
                    .overlay(Capsule().strokeBorder(style.stroke, lineWidth: 1))
                    .contentShape(Capsule())
                    .onLongPressGesture(minimumDuration: 0.6) {
                        onPreview(PreviewRequest(player: player, refs: [ref]))
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("table"))
                            .onChanged { _ in if game.settings.trackCommanderDamage { drag.claim(ref) } }
                            .onEnded { _ in drag.unclaim() }
                    )
                }
            }
        }
    }

    // MARK: Life

    private var lifeBlock: some View {
        let life = game.state.life[player]
        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button { game.changeLife(player, by: -1) } label: {
                    RoundKey(text: "-1", size: 100, style: style, fontSize: 38)
                }
                .buttonStyle(.plain)
                Text("\(life)")
                    .font(.system(size: 128, weight: .heavy, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    .shadow(color: .black.opacity(style.dark ? 0 : 0.25), radius: 8, y: 3)
                    .frame(width: 222, height: 120)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { panel = .adjust(.life) } }
                Button { game.changeLife(player, by: 1) } label: {
                    RoundKey(text: "+1", size: 100, style: style, fontSize: 38)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                quick(-10); quick(-5)
                Button { withAnimation { panel = .adjust(.life) } } label: {
                    Pill(text: "Set", icon: "keyboard", style: style, height: 48, fontSize: 16)
                }
                .buttonStyle(.plain)
                quick(5); quick(10)
            }
        }
    }

    private func quick(_ d: Int) -> some View {
        Button { game.changeLife(player, by: d) } label: {
            Text(d > 0 ? "+\(d)" : "-\(abs(d))")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .frame(width: 64, height: 48)
                .background(Capsule().fill(style.chip))
                .overlay(Capsule().strokeBorder(style.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Info pills (counters and commander numbers worth seeing at a glance)

    private struct Info: Identifiable {
        let id: String
        let icon: String?
        let text: String
        var warn = false
        var opensCommander = false
    }

    private var counterInfos: [Info] {
        let s = game.state
        return CounterKind.allCases.compactMap { kind in
            let n = s.count(player, kind)
            guard n > 0 else { return nil }
            return Info(id: kind.rawValue, icon: kind.icon, text: "\(kind.title) \(n)", warn: kind == .poison && n >= poisonLethal)
        }
    }

    private var commanderInfos: [Info] {
        guard game.settings.hasCommanders else { return [] }
        let s = game.state
        var out: [Info] = []
        if game.settings.trackCommanderDamage {
            for ref in game.commanderRefs(opponentOf: player, includeOwn: true) {
                let d = s.damage(to: player, from: ref)
                if d > 0 {
                    out.append(Info(id: "d\(ref.key)", icon: "shield.lefthalf.filled",
                                    text: "Hit by \(game.commanderName(ref)) \(d)", warn: d >= commanderDamageLethal,
                                    opensCommander: true))
                }
            }
        }
        if game.settings.trackTax {
            for (i, c) in game.players[player].commanders.enumerated() where s.casts[player][i] > 0 {
                out.append(Info(id: "t\(i)", icon: "arrow.up.circle",
                                text: "\(c.shortName) tax +\(s.nextTax(player: player, commander: i))",
                                opensCommander: true))
            }
        }
        return out
    }

    // MARK: Warnings (never end the game by themselves)

    private func warningItems(_ s: GameState) -> [(key: String, text: String)] {
        var items: [(String, String)] = []
        let life = s.life[player]
        if life <= 0 { items.append(("life-\(life)", "Life is at \(life). Confirm the result in Game, End game.")) }
        let poison = s.count(player, .poison)
        if poison >= poisonLethal { items.append(("poison-\(poison)", "\(poison) poison counters (10 or more).")) }
        if game.settings.trackCommanderDamage {
            for ref in game.commanderRefs(opponentOf: player, includeOwn: true) {
                let d = s.damage(to: player, from: ref)
                if d >= commanderDamageLethal {
                    items.append(("cmd-\(ref.key)-\(d)", "\(d) commander damage from \(game.commanderName(ref)) (21 or more)."))
                }
            }
        }
        return items.filter { !dismissed.contains("\(player)|\($0.0)") }
    }

    @ViewBuilder private var warningBar: some View {
        let items = warningItems(game.state)
        if !items.isEmpty {
            VStack(spacing: 6) {
                ForEach(items, id: \.key) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(item.text).font(.system(size: 16, weight: .semibold, design: .rounded)).lineLimit(2)
                        Spacer(minLength: 4)
                        Button("Dismiss") { dismissed.insert("\(player)|\(item.key)") }
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.25)))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.82)))
                    .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: Tokens (always visible)

    private func tokenArea(cardHeight: CGFloat) -> some View {
        let s = game.state
        let groups = s.tokens(of: player)
        let total = s.tokenCount(of: player)
        let ready = s.attackReady(of: player)
        let creatures = s.creatureCount(of: player)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("TOKENS").font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(1.4).foregroundStyle(style.soft)
                if total > 0 {
                    Text(creatures > 0 ? "\(total) total  ·  \(ready) of \(creatures) ready" : "\(total) total")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(style.soft)
                }
                Spacer()
                if groups.contains(where: { $0.tapped }) {
                    Button {
                        game.record(groups.filter { $0.tapped }.map { .tokenModify(group: $0.id, count: $0.quantity, mod: .tapped(false)) })
                    } label: { Pill(text: "Untap all", icon: "arrow.counterclockwise", style: style, height: 34, fontSize: 14) }
                        .buttonStyle(.plain)
                }
                Button { withAnimation { panel = .effects } } label: {
                    let n = s.effects.filter { $0.enabled }.count
                    Pill(text: n > 0 ? "Effects \(n)" : "Effects", icon: "wand.and.stars", style: style, height: 34, fontSize: 14)
                }
                .buttonStyle(.plain)
                if creatures > 0 {
                    Button { withAnimation { panel = .attackPower } } label: {
                        Pill(text: "Attack power", icon: "bolt.fill", style: style, height: 34, fontSize: 14)
                    }
                    .buttonStyle(.plain)
                }
                if groups.count > 1 {
                    Button { game.record(.mergeTokens(owner: player)) } label: {
                        Pill(text: "Merge", icon: "arrow.triangle.merge", style: style, height: 34, fontSize: 14)
                    }
                    .buttonStyle(.plain)
                }
                if !groups.isEmpty {
                    Button(action: onAddToken) {
                        Pill(text: "Add", icon: "plus", style: style, prominent: true, height: 34, fontSize: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 34)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(groups) { g in
                        TokenCard(game: game, group: g, state: s, height: cardHeight) {
                            withAnimation { panel = .group(g.id) }
                        }
                    }
                    AddTokenCard(height: cardHeight, style: style, action: onAddToken)
                }
                .padding(.trailing, 4)
            }
        }
    }

    // MARK: Action row

    private var actionRow: some View {
        let s = game.state
        let publicNotes = game.notes.filter { !$0.isPrivate || $0.author == player }.count
        let hasEventReminders = game.reminders.contains { $0.enabled && $0.timing.isEvent }
        return HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    chip("Counters", icon: "number.circle", on: false) { withAnimation { panel = .counters } }
                    if game.settings.hasCommanders {
                        chip("Commander", icon: "shield.lefthalf.filled", on: false) { withAnimation { panel = .commander } }
                    }
                    chip(publicNotes > 0 ? "Notes \(publicNotes)" : "Notes", icon: "note.text", on: false) { withAnimation { panel = .notes } }
                    chip("Reminders", icon: "bell", on: false) { withAnimation { panel = .reminders } }
                    if hasEventReminders { eventMenu }
                    chip("Monarch", icon: "crown.fill", on: s.monarch == player, iconOnly: s.monarch != player) { game.toggleMonarch(player) }
                    chip("Initiative", icon: "map.fill", on: s.initiative == player, iconOnly: s.initiative != player) { game.toggleInitiative(player) }
                }
            }
            priorityButton
            if isActive {
                Button { game.nextTurn() } label: {
                    Pill(text: "End my turn", icon: "forward.end.fill", style: style, prominent: true, height: 52)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Quick event buttons: tell the app something just happened so matching reminders appear.
    private var eventMenu: some View {
        Menu {
            ForEach(ReminderTiming.allCases.filter { $0.isEvent }) { t in
                Button(t.title) { game.fireReminders(t, by: player) }
            }
        } label: {
            Pill(text: "Event", icon: "bolt.badge.clock", style: style, height: 52)
        }
    }

    private func chip(_ text: String, icon: String, on: Bool, iconOnly: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Pill(text: text, icon: icon, style: style, prominent: on, height: 52, iconOnly: iconOnly)
        }
        .buttonStyle(.plain)
    }

    // MARK: Timers

    @ViewBuilder private var clockView: some View {
        if clock.mode != .off {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let now = ctx.date
                if clock.mode == .chess {
                    let left = clock.liveRemaining(player, now)
                    let running = clock.state.runner == player && !clock.isPaused
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(ClockModel.format(left))
                            .font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                            .foregroundStyle(left <= 0 ? Palette.danger : (left <= Double(clock.settings.warnSeconds) ? Palette.warn : style.fg))
                        Text(clock.isPaused ? "paused" : (running ? "running" : "waiting"))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(style.soft)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 14).fill(running ? style.chipStrong : style.chip))
                } else {
                    let limit = Double(clock.settings.turnLimitMinutes * 60)
                    let turn = clock.liveTurn(now)
                    VStack(alignment: .trailing, spacing: 0) {
                        if isActive {
                            Text(ClockModel.format(turn))
                                .font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                                .foregroundStyle(limit > 0 && turn >= limit ? Palette.danger : style.fg)
                        }
                        Text("Total \(ClockModel.format(clock.liveUsed(player, now)))")
                            .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(style.soft)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 14).fill(isActive ? style.chipStrong : style.chip))
                }
            }
        }
    }

    @ViewBuilder private var priorityButton: some View {
        if clock.mode == .chess && !clock.isPaused {
            let active = game.state.active
            if !isActive && clock.state.runner == active {
                priorityLabel("Take priority", icon: "hand.raised.fill") { clock.takePriority(by: player) }
            } else if !isActive && clock.state.runner == player {
                priorityLabel("Return clock to \(game.players[active].name)", icon: "arrow.uturn.backward") { clock.returnClock() }
            } else if isActive && clock.state.runner != player {
                priorityLabel("Return clock to me", icon: "arrow.uturn.backward") { clock.returnClock() }
            }
        }
    }

    private func priorityLabel(_ text: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold))
                Text(text).font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(1)
            }
            .padding(.horizontal, 18).frame(height: 52)
            .background(Capsule().fill(Palette.gold))
            .foregroundStyle(Color.black.opacity(0.88))
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    // MARK: Panels shown on top of this half

    @ViewBuilder private func panelOverlay(wide: Bool) -> some View {
        if let kind = panel {
            switch kind {
            case let .adjust(target):
                AdjustPanel(game: game, player: player, target: target) { panel = nil }
            case .counters:
                CountersPanel(game: game, player: player,
                              openKeypad: { panel = .adjust(.counter($0)) }) { panel = nil }
            case .commander:
                CommanderPanel(game: game, player: player, wide: wide,
                               alsoLoseLife: $alsoLoseLife, includeOwn: $includeOwn,
                               onPreview: onPreview,
                               onOpenCalculator: { i in withAnimation { panel = .voltron(i) } }) { panel = nil }
            case .notes:
                NotesPanel(game: game, player: player, wide: wide) { panel = nil }
            case .reminders:
                RemindersPanel(game: game, player: player, wide: wide) { panel = nil }
            case let .voltron(i):
                VoltronPanel(game: game, player: player, index: i, wide: wide,
                             onDeal: { n, ref in
                                 panel = nil
                                 onStartAttack(AttackRequest(attacker: player, defender: 1 - player,
                                                             commander: ref, prefill: n))
                             }) { panel = nil }
            case .effects:
                EffectsPanel(game: game, player: player, wide: wide) { panel = nil }
            case .attackPower:
                AttackPowerPanel(game: game, player: player, wide: wide,
                                 onUseAsDamage: { n in
                                     panel = nil
                                     onStartAttack(AttackRequest(attacker: player, defender: 1 - player,
                                                                 commander: nil, prefill: n))
                                 }) { panel = nil }
            case let .group(id):
                if let g = game.state.tokens.first(where: { $0.id == id }) {
                    GroupPanel(game: game, group: g, wide: wide) { panel = nil }
                } else {
                    Color.clear.onAppear { panel = nil }
                }
            }
        }
    }
}

// MARK: - A commander's card, shown beside the player's name

struct CommanderCardView: View {
    @EnvironmentObject var drag: AttackDrag
    let name: String
    let size: CGSize
    let style: ZoneStyle
    let commanderRef: CommanderRef
    let claimsDrag: Bool
    let onTap: () -> Void

    @State private var ref: String?

    var body: some View {
        StoreImage(ref: ref, contentMode: .fit) {
            RoundedRectangle(cornerRadius: 12).fill(style.chip)
                .overlay(Text(name).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
                    .padding(8).foregroundStyle(style.soft))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: size.width * 0.05))
        .overlay(RoundedRectangle(cornerRadius: size.width * 0.05).strokeBorder(Color.black.opacity(0.5), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        // Dragging from the card deals commander damage from this commander.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("table"))
                .onChanged { _ in if claimsDrag { drag.claim(commanderRef) } }
                .onEnded { _ in drag.unclaim() }
        )
        .task(id: name) {
            ref = nil
            let card = await CardStore.shared.card(named: name)
            ref = card?.faces.first?.normal
        }
    }
}

// MARK: - Panel frame

struct PanelFrame<Content: View>: View {
    let title: String
    let refW: CGFloat
    let refH: CGFloat
    let close: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).onTapGesture { close() }
            FitView(refW: refW, refH: refH) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
                        Spacer()
                        Button(action: close) {
                            Image(systemName: "xmark").font(.system(size: 20, weight: .bold))
                                .frame(width: 50, height: 50)
                                .background(Circle().fill(Color.white.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                    content
                }
                .foregroundStyle(.white)
                .padding(22)
                .background(RoundedRectangle(cornerRadius: 28).fill(Palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }
}

func panelRound(_ text: String, size: CGFloat = 52) -> some View {
    Text(text)
        .font(.system(size: 26, weight: .bold, design: .rounded))
        .frame(width: size, height: size)
        .background(Circle().fill(Color.white.opacity(0.14)))
        .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .contentShape(Circle())
}

// MARK: - Counters panel

struct CountersPanel: View {
    @ObservedObject var game: Game
    let player: Int
    let openKeypad: (CounterKind) -> Void
    let close: () -> Void

    var body: some View {
        let s = game.state
        PanelFrame(title: "Counters", refW: 620, refH: 400, close: close) {
            VStack(spacing: 10) {
                ForEach(CounterKind.allCases) { kind in
                    HStack(spacing: 12) {
                        Image(systemName: kind.icon).font(.system(size: 22, weight: .semibold))
                            .frame(width: 38)
                        Text(kind.title).font(.system(size: 22, weight: .semibold, design: .rounded))
                        Spacer()
                        Button { game.changeCounter(player, kind, by: -1) } label: { panelRound("-") }
                            .buttonStyle(.plain)
                        Text("\(s.count(player, kind))")
                            .font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                            .frame(width: 70)
                            .contentShape(Rectangle())
                            .onTapGesture { openKeypad(kind) }
                        Button { game.changeCounter(player, kind, by: 1) } label: { panelRound("+") }
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))
                }
                Text("Tap a number to type an exact value. Toxic damage is just poison counters.")
                    .font(.system(size: 13)).opacity(0.55)
            }
        }
    }
}

// MARK: - Commander panel (tax and damage)

struct CommanderPanel: View {
    @ObservedObject var game: Game
    let player: Int
    let wide: Bool
    @Binding var alsoLoseLife: Bool
    @Binding var includeOwn: Bool
    let onPreview: (PreviewRequest) -> Void
    var onOpenCalculator: (Int) -> Void = { _ in }
    let close: () -> Void

    var body: some View {
        PanelFrame(title: "Commander", refW: wide ? 1180 : 760, refH: wide ? 390 : 640, close: close) {
            if wide {
                HStack(alignment: .top, spacing: 22) {
                    if game.settings.trackTax { taxColumn.frame(maxWidth: .infinity, alignment: .top) }
                    if game.settings.trackCommanderDamage { damageColumn.frame(maxWidth: .infinity, alignment: .top) }
                }
            } else {
                VStack(spacing: 14) {
                    if game.settings.trackTax { taxColumn }
                    if game.settings.trackCommanderDamage { damageColumn }
                }
            }
        }
    }

    private var taxColumn: some View {
        let s = game.state
        let mine = game.players[player].commanders
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Command zone casts")
            ForEach(Array(mine.enumerated()), id: \.offset) { i, c in
                let casts = s.casts[player][i]
                let tax = s.nextTax(player: player, commander: i)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(Identity.sorted(c.colors)) { col in
                            Circle().fill(col.color).frame(width: 14, height: 14)
                                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                        }
                        Text(c.name).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.6) {
                        onPreview(PreviewRequest(player: player, refs: [CommanderRef(player: player, index: i)]))
                    }
                    HStack(spacing: 10) {
                        Button { game.cast(player, commander: i, by: 1) } label: {
                            Text("Cast from command zone")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .padding(.horizontal, 20).frame(height: 52)
                                .background(Capsule().fill(Color.white))
                                .foregroundStyle(Color.black.opacity(0.88))
                        }
                        .buttonStyle(.plain)
                        Button { game.cast(player, commander: i, by: -1) } label: { panelRound("-", size: 52) }
                            .buttonStyle(.plain)
                    }
                    Button { onOpenCalculator(i) } label: {
                        Label("Voltron calculator", systemImage: "function")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 18).frame(height: 44)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    Text(casts == 0 ? "Not cast yet. The next cast has no extra cost."
                                    : "Cast \(casts) time\(casts == 1 ? "" : "s"). Next cast costs \(tax) more mana.")
                        .font(.system(size: 15, weight: .medium)).opacity(0.8)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))
            }
        }
    }

    private var damageColumn: some View {
        let s = game.state
        let refs = game.commanderRefs(opponentOf: player, includeOwn: includeOwn)
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Commander damage taken")
            ForEach(refs, id: \.key) { ref in
                let d = s.damage(to: player, from: ref)
                let owner = game.players[ref.player].commanders
                let colors = owner.indices.contains(ref.index) ? owner[ref.index].colors : []
                HStack(spacing: 10) {
                    Circle().fill(Identity.accent(for: colors)).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                    Text(game.commanderName(ref))
                        .font(.system(size: 19, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.6) {
                            onPreview(PreviewRequest(player: player, refs: [ref]))
                        }
                    Spacer(minLength: 4)
                    Button { game.commanderDamage(victim: player, from: ref, by: -1, alsoLoseLife: alsoLoseLife) } label: { panelRound("-") }
                        .buttonStyle(.plain)
                    Text("\(d)")
                        .font(.system(size: 32, weight: .heavy, design: .rounded)).monospacedDigit()
                        .frame(width: 56)
                        .foregroundStyle(d >= commanderDamageLethal ? Palette.danger : Color.white)
                    Button { game.commanderDamage(victim: player, from: ref, by: 1, alsoLoseLife: alsoLoseLife) } label: { panelRound("+") }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))
            }
            Toggle("Also lower my life", isOn: $alsoLoseLife)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Toggle("Include my own commanders", isOn: $includeOwn)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 12, weight: .bold)).tracking(1.2).opacity(0.55)
    }
}

// MARK: - Adjustment keypad (shown on the player's own side)

struct AdjustPanel: View {
    @ObservedObject var game: Game
    let player: Int
    let target: AdjustTarget
    let close: () -> Void

    enum Mode: Int { case decrease, increase, set }

    @State private var mode: Mode = .decrease
    @State private var digits = ""
    @State private var negative = false

    private var current: Int {
        switch target {
        case .life: return game.state.life[player]
        case let .counter(k): return game.state.count(player, k)
        }
    }

    private var title: String {
        switch target {
        case .life: return "Life"
        case let .counter(k): return k.title
        }
    }

    private var entered: Int? {
        guard !digits.isEmpty, let n = Int(digits) else { return nil }
        return negative && mode == .set ? -n : n
    }

    private var preview: Int? {
        guard let n = entered else { return nil }
        let raw: Int
        switch mode {
        case .decrease: raw = current - n
        case .increase: raw = current + n
        case .set: raw = n
        }
        if case .counter = target { return max(0, raw) }
        return raw
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).onTapGesture { close() }
            FitView(refW: 560, refH: 560) {
                VStack(spacing: 12) {
                    Picker("", selection: $mode) {
                        Text(target == .life ? "Lose" : "Remove").tag(Mode.decrease)
                        Text(target == .life ? "Gain" : "Add").tag(Mode.increase)
                        Text("Set to").tag(Mode.set)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 440)

                    VStack(spacing: 2) {
                        Text("\(title): \(current) → \(preview.map(String.init) ?? "…")")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                        Text(summary).font(.system(size: 18, weight: .medium)).opacity(0.85)
                    }
                    .frame(height: 78)

                    VStack(spacing: 8) {
                        ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                            HStack(spacing: 8) { ForEach(row, id: \.self) { n in key("\(n)") { append("\(n)") } } }
                        }
                        HStack(spacing: 8) {
                            key(mode == .set ? (negative ? "Neg" : "+/-") : "C") {
                                if mode == .set { negative.toggle() } else { digits = "" }
                            }
                            key("0") { append("0") }
                            key("⌫") { if !digits.isEmpty { digits.removeLast() } }
                        }
                    }

                    HStack(spacing: 16) {
                        Button("Cancel") { close() }
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 200, height: 60)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                        Button { apply() } label: {
                            Text("Apply").font(.system(size: 22, weight: .bold))
                                .frame(width: 200, height: 60)
                                .background(Capsule().fill(Color.accentColor))
                                .foregroundStyle(.black)
                        }
                        .disabled(entered == nil)
                        .opacity(entered == nil ? 0.4 : 1)
                    }
                }
                .foregroundStyle(.white)
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 28).fill(Color(white: 0.12)))
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var summary: String {
        guard let n = entered else { return "Enter an amount" }
        switch (target, mode) {
        case (.life, .decrease): return "Lose \(n) life"
        case (.life, .increase): return "Gain \(n) life"
        case (.life, .set): return "Set life to \(n)"
        case (let .counter(k), .decrease): return "Remove \(n) \(k.title.lowercased())"
        case (let .counter(k), .increase): return "Add \(n) \(k.title.lowercased())"
        case (let .counter(k), .set): return "Set \(k.title.lowercased()) to \(n)"
        }
    }

    private func append(_ d: String) {
        guard digits.count < 4 else { return }
        digits = (digits == "0" ? "" : digits) + d
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .frame(width: 130, height: 76)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.14)))
        }
    }

    private func apply() {
        guard let n = entered else { return }
        switch (target, mode) {
        case (.life, .decrease): game.changeLife(player, by: -n)
        case (.life, .increase): game.changeLife(player, by: n)
        case (.life, .set): game.setLife(player, to: n)
        case (let .counter(k), .decrease): game.changeCounter(player, k, by: -n)
        case (let .counter(k), .increase): game.changeCounter(player, k, by: n)
        case (let .counter(k), .set): game.setCounter(player, k, to: n)
        }
        close()
    }
}
