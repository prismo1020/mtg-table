import SwiftUI
import UIKit

/// Shared state for dragging from one player's half to the other to deal damage.
final class AttackDrag: ObservableObject {
    @Published var active = false
    @Published var start: CGPoint = .zero
    @Published var current: CGPoint = .zero
    /// The player whose half the drag started in.
    @Published var attacker = 0
    /// Set when the drag started on a commander chip or card (so it deals commander damage).
    @Published var commander: CommanderRef?
    /// True for a two-finger drag, which offers life gain and double strike.
    @Published var special = false

    /// True while a two-finger drag is in progress (and briefly after), so the single-finger drag stays out of the way.
    var twoFingerLive = false

    private var claim: CommanderRef?
    private var blockers: Set<Int> = []

    var isBlocked: Bool { !blockers.isEmpty }

    /// A commander chip or card was touched and is being dragged.
    func claim(_ ref: CommanderRef) { claim = ref }
    func unclaim() { claim = nil }

    func setBlocked(_ key: Int, _ on: Bool) {
        if on { blockers.insert(key) } else { blockers.remove(key) }
    }

    func begin(attacker: Int, start: CGPoint, special: Bool = false) {
        self.attacker = attacker
        self.start = start
        self.current = start
        self.commander = claim
        self.special = special
        self.active = true
    }

    /// The chip's touch may be reported slightly after the table's drag begins.
    func adoptClaimIfNeeded() {
        if commander == nil, let c = claim { commander = c }
    }

    func reset() {
        active = false
        special = false
        commander = nil
        // The chip releases its own claim a moment later, once its touch ends.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            if self?.active == false { self?.claim = nil }
        }
    }
}

/// What the attack panel is about to apply.
struct AttackRequest: Identifiable, Equatable {
    var id = UUID()
    var attacker: Int
    var defender: Int
    var commander: CommanderRef?
    /// Opened by a two-finger drag: ask about life gain and double strike first.
    var special = false
    /// A damage amount to start with (from the attacking power panel).
    var prefill: Int? = nil
}

enum AttackStyle {
    static let commanderColor = Color(red: 0.66, green: 0.45, blue: 0.98)
    static let specialColor = Color(red: 0.25, green: 0.78, blue: 0.92)

    static func color(commander: Bool, special: Bool) -> Color {
        commander ? commanderColor : (special ? specialColor : Palette.gold)
    }
}

// MARK: - Two-finger drag (UIKit, because SwiftUI cannot tell how many fingers are down)

struct TwoFingerPan: UIViewRepresentable {
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void

    func makeUIView(context: Context) -> HostView {
        let v = HostView()
        v.isUserInteractionEnabled = false
        v.coordinator = context.coordinator
        return v
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Invisible view whose only job is to attach the recognizer to the whole window.
    final class HostView: UIView {
        weak var coordinator: Coordinator?
        private var recognizer: UIPanGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let r = recognizer { r.view?.removeGestureRecognizer(r); recognizer = nil }
            guard let window, let coordinator else { return }
            let r = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handle(_:)))
            r.minimumNumberOfTouches = 2
            r.maximumNumberOfTouches = 2
            r.cancelsTouchesInView = false
            r.delaysTouchesBegan = false
            r.delaysTouchesEnded = false
            r.delegate = coordinator
            window.addGestureRecognizer(r)
            recognizer = r
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TwoFingerPan
        init(_ parent: TwoFingerPan) { self.parent = parent }

        @objc func handle(_ g: UIPanGestureRecognizer) {
            let p = g.location(in: g.view)
            switch g.state {
            case .began: parent.onBegan(p)
            case .changed: parent.onChanged(p)
            case .ended: parent.onEnded(p)
            case .cancelled, .failed: parent.onEnded(CGPoint(x: -1, y: -1))
            default: break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// MARK: - Arrow and drop highlight shown while dragging

struct AttackOverlay: View {
    @ObservedObject var drag: AttackDrag
    let game: Game
    let zoneHeight: CGFloat
    let stripHeight: CGFloat
    let size: CGSize

    private var defender: Int { 1 - drag.attacker }

    private var inDefenderZone: Bool {
        let y = drag.current.y
        return defender == 1 ? y < zoneHeight : y > zoneHeight + stripHeight
    }

    private var isCommander: Bool { drag.commander != nil }

    private var label: String {
        if let ref = drag.commander { return "\(game.commanderName(ref)) commander damage" }
        return drag.special ? "Special attack" : "Damage"
    }

    var body: some View {
        let color = AttackStyle.color(commander: isCommander, special: drag.special)
        ZStack {
            // Highlight the zone you are aiming at.
            RoundedRectangle(cornerRadius: 26)
                .fill(color.opacity(inDefenderZone ? 0.26 : 0.08))
                .overlay(RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(color.opacity(inDefenderZone ? 0.95 : 0.4), lineWidth: inDefenderZone ? 8 : 3))
                .frame(width: size.width - 12, height: zoneHeight - 12)
                .position(x: size.width / 2,
                          y: defender == 1 ? zoneHeight / 2 : zoneHeight + stripHeight + zoneHeight / 2)

            if inDefenderZone {
                Text("Release to hit \(game.players[defender].name)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(Capsule().fill(color.opacity(0.9)))
                    .rotationEffect(.degrees(defender == 1 ? 180 : 0))
                    .position(x: size.width / 2,
                              y: defender == 1 ? zoneHeight / 2 : zoneHeight + stripHeight + zoneHeight / 2)
            }

            // Dotted trail from where the drag began to the finger.
            Path { p in
                p.move(to: drag.start)
                p.addLine(to: drag.current)
            }
            .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round, dash: [0.1, 20]))

            Circle().fill(color).frame(width: 70, height: 70)
                .overlay(Image(systemName: isCommander ? "shield.lefthalf.filled" : (drag.special ? "sparkles" : "bolt.fill"))
                    .font(.system(size: 30, weight: .bold)).foregroundStyle(.white))
                .shadow(color: .black.opacity(0.4), radius: 8)
                .position(drag.current)

            Text(label)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .rotationEffect(.degrees(drag.attacker == 1 ? 180 : 0))
                .position(x: drag.start.x, y: drag.start.y + (drag.attacker == 0 ? 50 : -50))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Amount panel

struct AttackPanel: View {
    @ObservedObject var game: Game
    let request: AttackRequest
    let close: () -> Void

    private enum Stage { case choose, amount }

    @AppStorage("attackAlsoLife") private var alsoLife = true
    @State private var digits = ""
    @State private var stage: Stage
    @State private var lifeGain = false
    @State private var doubleStrike = false

    init(game: Game, request: AttackRequest, close: @escaping () -> Void) {
        self.game = game
        self.request = request
        self.close = close
        _stage = State(initialValue: request.special ? .choose : .amount)
        _digits = State(initialValue: request.prefill.map { String(min($0, 999)) } ?? "")
    }

    private var amount: Int { Int(digits) ?? 0 }
    private var hits: Int { doubleStrike ? 2 : 1 }
    private var total: Int { amount * hits }
    private var isCommander: Bool { request.commander != nil }
    private var color: Color { AttackStyle.color(commander: isCommander, special: request.special) }

    private var defenderName: String { game.players[request.defender].name }
    private var attackerName: String { game.players[request.attacker].name }

    private var defenderLife: Int { game.state.life[request.defender] }
    private var attackerLife: Int { game.state.life[request.attacker] }

    private var defenderLifeAfter: Int {
        if isCommander && !alsoLife { return defenderLife }
        return defenderLife - total
    }

    private var damageNow: Int {
        guard let ref = request.commander else { return 0 }
        return game.state.damage(to: request.defender, from: ref)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea().onTapGesture { close() }
            FitView(refW: 600, refH: (request.special && stage == .amount) ? 920 : 760) {
                VStack(spacing: 14) {
                    header
                    if stage == .choose { chooser } else { amountStage }
                }
                .foregroundStyle(.white)
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 30).fill(Palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(color.opacity(0.7), lineWidth: 2))
            }
            .padding(30)
        }
        .rotationEffect(.degrees(request.attacker == 1 ? 180 : 0))
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let ref = request.commander {
                    Text("\(game.commanderName(ref)) attacks \(defenderName)")
                        .font(.system(size: 26, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("Commander damage").font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                } else {
                    Text("\(attackerName) attacks \(defenderName)")
                        .font(.system(size: 26, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(request.special ? "Special attack" : "Damage")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                }
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 20, weight: .bold))
                    .frame(width: 50, height: 50).background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Step 1 (two-finger drags only): life gain, double strike, or both

    private var chooser: some View {
        VStack(spacing: 14) {
            Text("What does this attack have?")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .padding(.top, 8)
            choice("Life gain", "\(attackerName) gains life equal to the damage dealt",
                   icon: "heart.fill") { lifeGain = true; doubleStrike = false; stage = .amount }
            choice("Double strike", "The damage is dealt twice",
                   icon: "bolt.horizontal.fill") { lifeGain = false; doubleStrike = true; stage = .amount }
            choice("Both", "Dealt twice, and \(attackerName) gains all of it",
                   icon: "sparkles") { lifeGain = true; doubleStrike = true; stage = .amount }
            Button { lifeGain = false; doubleStrike = false; stage = .amount } label: {
                Text("Neither, just damage")
                    .font(.system(size: 19, weight: .semibold, design: .rounded)).opacity(0.8)
                    .frame(maxWidth: .infinity).frame(height: 56)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private func choice(_ title: String, _ detail: String, icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 30, weight: .semibold)).frame(width: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(detail).font(.system(size: 16, weight: .medium)).opacity(0.8)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22).frame(maxWidth: .infinity).frame(height: 116)
            .background(RoundedRectangle(cornerRadius: 24).fill(color.opacity(0.22)))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(color.opacity(0.7), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 2: the amount

    private var amountStage: some View {
        VStack(spacing: 14) {
            amountBlock
            if request.special { optionToggles }
            keypad
            if isCommander {
                Toggle("Also lower \(defenderName)’s life", isOn: $alsoLife)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
            }
            HStack(spacing: 14) {
                Button(action: close) {
                    Text("Cancel").font(.system(size: 22, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 62)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                Button(action: apply) {
                    Text(amount == 0 ? "Enter an amount" : "Deal \(total)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 62)
                        .background(Capsule().fill(amount == 0 ? Color.white.opacity(0.18) : color))
                        .foregroundStyle(amount == 0 ? Color.white.opacity(0.5) : Color.white)
                }
                .buttonStyle(.plain)
                .disabled(amount == 0)
            }
        }
    }

    private var optionToggles: some View {
        HStack(spacing: 12) {
            toggleChip("Life gain", icon: "heart.fill", on: $lifeGain)
            toggleChip("Double strike", icon: "bolt.horizontal.fill", on: $doubleStrike)
        }
    }

    private func toggleChip(_ title: String, icon: String, on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: on.wrappedValue ? "checkmark.circle.fill" : "circle").font(.system(size: 20, weight: .semibold))
                Text(title).font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(Capsule().fill(on.wrappedValue ? color.opacity(0.9) : Color.white.opacity(0.12)))
            .foregroundStyle(on.wrappedValue ? Color.white : Color.white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }

    private var amountBlock: some View {
        VStack(spacing: 6) {
            Text(digits.isEmpty ? "0" : digits)
                .font(.system(size: 84, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(digits.isEmpty ? Color.white.opacity(0.35) : Color.white)
            if doubleStrike {
                Text("Double strike: \(amount) x 2 = \(total) damage")
                    .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(color)
            }
            if let ref = request.commander {
                let after = damageNow + total
                Text("Commander damage from \(game.commanderName(ref)): \(damageNow) → \(after)")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(after >= commanderDamageLethal ? Palette.danger : Color.white)
                Text("\(defenderName)’s life: \(defenderLife) → \(defenderLifeAfter)")
                    .font(.system(size: 18, weight: .medium, design: .rounded)).opacity(isCommander && !alsoLife ? 0.5 : 0.9)
            } else {
                Text("\(defenderName)’s life: \(defenderLife) → \(defenderLifeAfter)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
            }
            if lifeGain {
                Text("\(attackerName)’s life: \(attackerLife) → \(attackerLife + total)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(Palette.good)
            }
        }
        .frame(minHeight: 150)
    }

    private var keypad: some View {
        VStack(spacing: 10) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                HStack(spacing: 10) { ForEach(row, id: \.self) { n in key("\(n)") { append("\(n)") } } }
            }
            HStack(spacing: 10) {
                key("C") { digits = "" }
                key("0") { append("0") }
                key("Del") { if !digits.isEmpty { digits.removeLast() } }
            }
        }
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 34, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity).frame(height: 76)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func append(_ d: String) {
        guard digits.count < 3 else { return }
        digits = (digits == "0" ? "" : digits) + d
    }

    /// Everything in one undo step: the damage, any life loss, and any life gain.
    private func apply() {
        guard amount > 0 else { return }
        var actions: [Action] = []
        if let ref = request.commander {
            actions.append(.commanderDamage(victim: request.defender, sourcePlayer: ref.player,
                                            sourceCommander: ref.index, delta: total))
            if alsoLife { actions.append(.life(player: request.defender, delta: -total)) }
        } else {
            actions.append(.life(player: request.defender, delta: -total))
        }
        if lifeGain { actions.append(.life(player: request.attacker, delta: total)) }
        game.record(actions)
        close()
    }
}
