import SwiftUI

private struct OwnerRequest: Identifiable { let id: Int }

struct TableView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var game: Game
    @ObservedObject var clock: ClockModel

    @State private var showHistory = false
    @State private var showEnd = false
    @State private var preview: PreviewRequest?
    @State private var adding: OwnerRequest?
    @State private var attack: AttackRequest?
    @StateObject private var drag = AttackDrag()

    private let stripHeight: CGFloat = 124

    init(game: Game) {
        _game = ObservedObject(wrappedValue: game)
        _clock = ObservedObject(wrappedValue: game.clock)
    }

    var body: some View {
        GeometryReader { geo in
            let zoneHeight = (geo.size.height - stripHeight) / 2
            ZStack {
                VStack(spacing: 0) {
                    PlayerZone(game: game, clock: clock, player: 1, rotated: true,
                               inset: geo.safeAreaInsets.top,
                               onPreview: { preview = $0 }, onAddToken: { adding = OwnerRequest(id: 1) },
                               onStartAttack: { attack = $0 })
                        .frame(height: zoneHeight)
                    centerStrip
                        .frame(height: stripHeight)
                    PlayerZone(game: game, clock: clock, player: 0, rotated: false,
                               inset: geo.safeAreaInsets.bottom,
                               onPreview: { preview = $0 }, onAddToken: { adding = OwnerRequest(id: 0) },
                               onStartAttack: { attack = $0 })
                        .frame(height: zoneHeight)
                }

                if drag.active, showsArrow {
                    AttackOverlay(drag: drag, game: game, zoneHeight: zoneHeight, stripHeight: stripHeight, size: geo.size)
                }

                if let request = preview {
                    CardPreviewOverlay(game: game, request: request) { preview = nil }
                        .transition(.opacity)
                }

                if let request = attack {
                    AttackPanel(game: game, request: request) { attack = nil }
                        .transition(.opacity)
                }
            }
            .coordinateSpace(name: "table")
            .simultaneousGesture(attackGesture(zoneHeight: zoneHeight, size: geo.size))
            .background(
                TwoFingerPan(
                    onBegan: { twoFingerBegan($0, zoneHeight: zoneHeight) },
                    onChanged: { if drag.special { drag.current = $0 } },
                    onEnded: { twoFingerEnded($0, zoneHeight: zoneHeight) }
                )
            )
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .environmentObject(drag)
        .animation(.easeInOut(duration: 0.2), value: preview)
        .animation(.easeInOut(duration: 0.15), value: attack)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showHistory) { HistoryView(game: game) }
        .sheet(isPresented: $showEnd) { EndGameView(game: game).environmentObject(app) }
        .sheet(item: $adding) { request in AddTokenSheet(game: game, owner: request.id) }
    }

    // MARK: Dragging to deal damage

    /// The arrow only appears once the drag is clearly heading toward the other player.
    private var showsArrow: Bool {
        let forward = drag.attacker == 0 ? drag.start.y - drag.current.y : drag.current.y - drag.start.y
        return forward > 36 && forward > abs(drag.current.x - drag.start.x) * 0.45
    }

    private func zoneOwner(at y: CGFloat, zoneHeight: CGFloat) -> Int? {
        if y < zoneHeight { return 1 }
        if y > zoneHeight + stripHeight { return 0 }
        return nil
    }

    private func attackGesture(zoneHeight: CGFloat, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 22, coordinateSpace: .named("table"))
            .onChanged { v in
                guard !drag.twoFingerLive, attack == nil, preview == nil, adding == nil, !drag.isBlocked else { return }
                if !drag.active {
                    guard let owner = zoneOwner(at: v.startLocation.y, zoneHeight: zoneHeight) else { return }
                    drag.begin(attacker: owner, start: v.startLocation)
                }
                drag.current = v.location
                drag.adoptClaimIfNeeded()
            }
            .onEnded { v in
                guard !drag.twoFingerLive else { return }
                defer { drag.reset() }
                guard drag.active, attack == nil else { return }
                let attacker = drag.attacker
                let forward = attacker == 0 ? v.startLocation.y - v.location.y : v.location.y - v.startLocation.y
                let defender = 1 - attacker
                guard forward > 36, zoneOwner(at: v.location.y, zoneHeight: zoneHeight) == defender else { return }
                drag.adoptClaimIfNeeded()
                attack = AttackRequest(attacker: attacker, defender: defender, commander: drag.commander)
            }
    }

    /// Two fingers dragging toward the opponent: a special attack (life gain and/or double strike).
    private func twoFingerBegan(_ p: CGPoint, zoneHeight: CGFloat) {
        guard attack == nil, preview == nil, adding == nil, !drag.isBlocked,
              let owner = zoneOwner(at: p.y, zoneHeight: zoneHeight) else { return }
        drag.twoFingerLive = true
        drag.begin(attacker: owner, start: p, special: true)
    }

    private func twoFingerEnded(_ p: CGPoint, zoneHeight: CGFloat) {
        defer {
            drag.reset()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { drag.twoFingerLive = false }
        }
        guard drag.active, drag.special, attack == nil else { return }
        let attacker = drag.attacker
        let forward = attacker == 0 ? drag.start.y - p.y : p.y - drag.start.y
        let defender = 1 - attacker
        guard p.x >= 0, forward > 36, zoneOwner(at: p.y, zoneHeight: zoneHeight) == defender else { return }
        drag.adoptClaimIfNeeded()
        attack = AttackRequest(attacker: attacker, defender: defender, commander: drag.commander, special: true)
    }

    // MARK: Shared bar (both players can reach it)

    private var centerStrip: some View {
        let s = game.state
        return HStack(spacing: 14) {
            HStack(spacing: 10) {
                roundButton("clock.arrow.circlepath", enabled: true) { showHistory = true }
                roundButton("arrow.uturn.backward", enabled: game.canUndo) { game.undo() }
                roundButton("arrow.uturn.forward", enabled: game.canRedo) { game.redo() }
            }

            Spacer(minLength: 6)

            VStack(spacing: 3) {
                if let banner = clock.banner {
                    Button { clock.dismissBanner() } label: {
                        Label(banner, systemImage: "bell.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(Palette.warn))
                            .foregroundStyle(Color.black.opacity(0.88))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Round \(s.round)  ·  Turn \(s.turnSerial)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("\(game.players[s.active].name)’s turn, number \(s.turnsTaken[s.active])")
                        .font(.system(size: 15, weight: .medium)).opacity(0.7)
                }
                phaseTracker
                if clock.mode != .off { timerLine }
                if !s.extraTurns.isEmpty || s.skipNext.contains(true) {
                    Text(pendingTurnText(s))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.gold)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Button { game.nextTurn() } label: {
                HStack(spacing: 10) {
                    Text("Next Turn").font(.system(size: 22, weight: .bold, design: .rounded))
                    Image(systemName: "forward.end.fill").font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(Color.black.opacity(0.88))
                .padding(.horizontal, 28).frame(height: 66)
                .background(Capsule().fill(Palette.gold))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 6)

            menu
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(Palette.bar)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
        .foregroundStyle(.white)
    }

    private func roundButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.32)
    }

    /// Compact turn phases. Tap one to move there; reminders for that phase appear on the right side.
    private var phaseTracker: some View {
        HStack(spacing: 6) {
            ForEach(TurnPhase.allCases) { p in
                let on = game.phase == p
                Button { game.setPhase(p) } label: {
                    Text(p.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().fill(on ? Color.white : Color.white.opacity(0.12)))
                        .foregroundStyle(on ? Color.black.opacity(0.88) : Color.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Game time with pause and resume (only when a timer is on).
    private var timerLine: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            HStack(spacing: 10) {
                Text(clock.isPaused ? "PAUSED" : "Game \(ClockModel.format(clock.liveGame(ctx.date)))")
                    .font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(clock.isPaused ? Palette.gold : Color.white.opacity(0.75))
                Button {
                    clock.isPaused ? clock.resume() : clock.pause()
                } label: {
                    Label(clock.isPaused ? "Resume" : "Pause", systemImage: clock.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(Capsule().fill(clock.isPaused ? Palette.gold : Color.white.opacity(0.16)))
                        .foregroundStyle(clock.isPaused ? Color.black.opacity(0.88) : Color.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pendingTurnText(_ s: GameState) -> String {
        var parts: [String] = []
        for p in s.extraTurns { parts.append("\(game.players[p].name) extra turn queued") }
        for p in 0..<2 where s.skipNext[p] { parts.append("\(game.players[p].name) will skip next turn") }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: Menu (everything that is not needed every turn)

    private var menu: some View {
        Menu {
            Menu("Turns") {
                ForEach(0..<2, id: \.self) { p in
                    Button("\(game.players[p].name) takes an extra turn") { game.record(.extraTurn(player: p)) }
                }
                ForEach(0..<2, id: \.self) { p in
                    let on = game.state.skipNext[p]
                    Button(on ? "Cancel \(game.players[p].name)’s skipped turn" : "\(game.players[p].name) skips their next turn") {
                        game.record(.skipNextTurn(player: p, on: !on))
                    }
                }
                ForEach(0..<2, id: \.self) { p in
                    Button("It’s actually \(game.players[p].name)’s turn") { game.record(.setActive(player: p)) }
                        .disabled(game.state.active == p)
                }
            }
            Menu("Timer") {
                ForEach(TimerSettings.Mode.allCases, id: \.self) { mode in
                    Button {
                        clock.setMode(mode)
                    } label: {
                        if clock.mode == mode { Label(mode.title, systemImage: "checkmark") } else { Text(mode.title) }
                    }
                }
                if clock.mode == .chess {
                    ForEach(0..<2, id: \.self) { p in
                        Button("Give \(game.players[p].name) 1 more minute") { clock.addTime(to: p, seconds: 60) }
                    }
                }
                Toggle("Sound alerts", isOn: Binding(get: { clock.settings.soundAlerts },
                                                     set: { clock.settings.soundAlerts = $0 }))
            }
            Toggle("Untap tokens automatically each turn",
                   isOn: Binding(get: { game.state.autoUntap }, set: { game.record(.setAutoUntap($0)) }))
            Divider()
            Button("End game…") { showEnd = true }
            Button("Cancel game without saving", role: .destructive) { app.discardGame() }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 24, weight: .bold))
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
    }
}

// MARK: - Full-card preview (faces the player who asked)

struct CardPreviewOverlay: View {
    @ObservedObject var game: Game
    let request: PreviewRequest
    let close: () -> Void

    private struct Item: Identifiable {
        let id = UUID()
        let title: String
        let ref: String?
    }

    @State private var items: [Item] = []
    @State private var loaded = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 16) {
                if loaded && items.isEmpty {
                    Text("No card image is saved for this commander yet. Connect to the internet once to download it.")
                        .font(.title3).multilineTextAlignment(.center).padding(40)
                } else {
                    HStack(spacing: 20) {
                        ForEach(items) { item in
                            VStack(spacing: 8) {
                                StoreImage(ref: item.ref, contentMode: .fit) {
                                    RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.1))
                                        .overlay(ProgressView())
                                        .aspectRatio(488.0 / 680.0, contentMode: .fit)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                Text(item.title).font(.system(size: 16, weight: .semibold))
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 20)
                }
                Text("Tap anywhere to close").font(.footnote).opacity(0.6)
            }
            .foregroundStyle(.white)
            .frame(maxHeight: .infinity)
            .rotationEffect(.degrees(request.player == 1 ? 180 : 0))
            .allowsHitTesting(false)
        }
        .task { await load() }
    }

    private func load() async {
        var out: [Item] = []
        for ref in request.refs {
            let list = game.players[ref.player].commanders
            guard list.indices.contains(ref.index) else { continue }
            if let card = await CardStore.shared.card(named: list[ref.index].name) {
                for face in card.faces {
                    out.append(Item(title: face.name, ref: face.normal))
                }
            }
        }
        items = out
        loaded = true
    }
}
