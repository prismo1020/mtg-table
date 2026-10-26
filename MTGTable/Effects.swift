import SwiftUI

// MARK: - Effects panel (anthems and other persistent bonuses)

private struct EffectDraft {
    enum Kind: String, CaseIterable { case all, types, groups }

    var id: Int?
    var name = ""
    var power = 0
    var toughness = 0
    var keywords: [String] = []
    var scope: EffectScope = .mine
    var kind: Kind = .all
    var types: [String] = []
    var groups: [Int] = []
    var enabled = true
}

struct EffectsPanel: View {
    @ObservedObject var game: Game
    let player: Int
    let wide: Bool
    let close: () -> Void

    @State private var draft: EffectDraft?
    @State private var typeText = ""

    private var me: String { game.players[player].name }
    private var other: String { game.players[1 - player].name }

    var body: some View {
        PanelFrame(title: title, refW: wide ? 1100 : 760, refH: wide ? 430 : 800, close: close) {
            if draft != nil { editor } else { list }
        }
    }

    private var title: String {
        guard let d = draft else { return "Effects" }
        return d.id == nil ? "New effect" : "Edit effect"
    }

    // MARK: List

    private var list: some View {
        let s = game.state
        return VStack(alignment: .leading, spacing: 12) {
            Text("QUICK ADD (for \(me)’s creature tokens)")
                .font(.system(size: 12, weight: .bold)).tracking(1.2).opacity(0.55)
            FlowLayout(spacing: 8) {
                quick("+1/+1 anthem", power: 1, toughness: 1)
                quick("+1/+0", power: 1, toughness: 0)
                quick("+2/+2", power: 2, toughness: 2)
                quick("Gain flying", keywords: ["Flying"])
                quick("Gain haste", keywords: ["Haste"])
                quick("Gain trample", keywords: ["Trample"])
            }

            Text("ACTIVE EFFECTS").font(.system(size: 12, weight: .bold)).tracking(1.2).opacity(0.55).padding(.top, 4)
            if s.effects.isEmpty {
                Text("No effects yet. Quick add one above, or make your own.")
                    .font(.system(size: 16)).opacity(0.65).padding(.vertical, 6)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(s.effects) { e in row(e, s) }
                }
            }
            .frame(maxHeight: .infinity)

            Button { draft = EffectDraft() } label: {
                Label("New custom effect", systemImage: "plus")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .padding(.horizontal, 22).frame(height: 54)
                    .background(Capsule().fill(Color.white))
                    .foregroundStyle(Color.black.opacity(0.88))
            }
            .buttonStyle(.plain)
        }
    }

    private func quick(_ title: String, power: Int = 0, toughness: Int = 0, keywords: [String] = []) -> some View {
        Button {
            game.record(.addEffect(TokenEffect(name: title, power: power, toughness: toughness,
                                               keywords: keywords, controller: player)))
        } label: {
            Text(title).font(.system(size: 16, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16).frame(height: 46)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func affectedCount(_ e: TokenEffect, _ s: GameState) -> Int {
        s.tokens.filter { e.matches($0) }.reduce(0) { $0 + $1.quantity }
    }

    private func row(_ e: TokenEffect, _ s: GameState) -> some View {
        let c = game.players[e.controller].name
        let o = game.players[1 - e.controller].name
        return HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { e.enabled },
                                     set: { game.record(.setEffectEnabled(id: e.id, enabled: $0)) }))
                .labelsHidden().fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(e.name).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(1)
                    Text(e.effectText).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.35, green: 0.8, blue: 0.9))
                }
                Text("\(e.targetText(controllerName: c, otherName: o))  ·  affects \(affectedCount(e, s)) token\(affectedCount(e, s) == 1 ? "" : "s")")
                    .font(.system(size: 13)).opacity(0.65).lineLimit(1)
            }
            .opacity(e.enabled ? 1 : 0.5)
            Spacer(minLength: 6)
            Button { startEditing(e) } label: { smallButton("Edit") }.buttonStyle(.plain)
            Button { game.record(.removeEffect(id: e.id)) } label: { smallButton("Remove", danger: true) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.07)))
    }

    private func smallButton(_ title: String, danger: Bool = false) -> some View {
        Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, 16).frame(height: 42)
            .background(Capsule().fill(danger ? Palette.danger.opacity(0.8) : Color.white.opacity(0.14)))
    }

    private func startEditing(_ e: TokenEffect) {
        var d = EffectDraft()
        d.id = e.id; d.name = e.name; d.power = e.power; d.toughness = e.toughness
        d.keywords = e.keywords; d.scope = e.scope; d.enabled = e.enabled
        switch e.filter {
        case .allCreatures: d.kind = .all
        case let .types(t): d.kind = .types; d.types = t
        case let .groups(g): d.kind = .groups; d.groups = g
        }
        draft = d
    }

    // MARK: Editor

    private var knownTypes: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for g in game.state.tokens where g.isCreature {
            let subs = g.types.components(separatedBy: " — ").dropFirst().joined(separator: " ")
            for w in subs.split(separator: " ") where seen.insert(w.lowercased()).inserted { out.append(String(w)) }
        }
        return out
    }

    private var editor: some View {
        let binding = Binding<EffectDraft>(get: { draft ?? EffectDraft() }, set: { draft = $0 })
        let d = binding.wrappedValue
        return VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Name (for example Anthem)", text: binding.name)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .padding(12).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                    HStack(spacing: 24) {
                        Stepper("Power \(signed(d.power))", value: binding.power, in: -9...9)
                        Stepper("Toughness \(signed(d.toughness))", value: binding.toughness, in: -9...9)
                    }
                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                    label("Grants keywords")
                    FlowLayout(spacing: 8) {
                        ForEach(TokenKeywords.common, id: \.self) { k in
                            chip(k, on: d.keywords.contains(k)) {
                                if let i = binding.wrappedValue.keywords.firstIndex(of: k) { draft?.keywords.remove(at: i) }
                                else { draft?.keywords.append(k) }
                            }
                        }
                    }

                    label("Whose tokens")
                    Picker("", selection: binding.scope) {
                        Text("\(me)’s").tag(EffectScope.mine)
                        Text("\(other)’s").tag(EffectScope.theirs)
                        Text("Both").tag(EffectScope.both)
                    }
                    .pickerStyle(.segmented)

                    label("Which tokens")
                    Picker("", selection: binding.kind) {
                        Text("All creature tokens").tag(EffectDraft.Kind.all)
                        Text("Chosen types").tag(EffectDraft.Kind.types)
                        Text("Specific groups").tag(EffectDraft.Kind.groups)
                    }
                    .pickerStyle(.segmented)

                    if d.kind == .types { typePicker(binding) }
                    if d.kind == .groups { groupPicker(binding) }
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 14) {
                Button { draft = nil } label: {
                    Text("Cancel").font(.system(size: 20, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 58)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                Button { save() } label: {
                    Text("Save effect").font(.system(size: 20, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 58)
                        .background(Capsule().fill(canSave ? Palette.gold : Color.white.opacity(0.14)))
                        .foregroundStyle(canSave ? Color.black.opacity(0.88) : Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        guard let d = draft else { return false }
        let hasEffect = d.power != 0 || d.toughness != 0 || !d.keywords.isEmpty
        let hasTarget = d.kind == .all || (d.kind == .types && !d.types.isEmpty) || (d.kind == .groups && !d.groups.isEmpty)
        return hasEffect && hasTarget
    }

    private func save() {
        guard let d = draft, canSave else { return }
        let filter: EffectFilter
        switch d.kind {
        case .all: filter = .allCreatures
        case .types: filter = .types(d.types)
        case .groups: filter = .groups(d.groups)
        }
        let name = d.name.trimmingCharacters(in: .whitespaces)
        var e = TokenEffect(name: name.isEmpty ? "Effect" : name, power: d.power, toughness: d.toughness,
                            keywords: d.keywords, controller: player, scope: d.scope, filter: filter, enabled: d.enabled)
        if let id = d.id {
            e.id = id
            // Keep the original controller when editing.
            if let old = game.state.effects.first(where: { $0.id == id }) { e.controller = old.controller }
            game.record(.updateEffect(e))
        } else {
            game.record(.addEffect(e))
        }
        draft = nil
    }

    private func typePicker(_ binding: Binding<EffectDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let all = Array(Set(knownTypes + binding.wrappedValue.types)).sorted()
            if !all.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(all, id: \.self) { t in
                        chip(t, on: binding.wrappedValue.types.contains(t)) {
                            if let i = binding.wrappedValue.types.firstIndex(of: t) { draft?.types.remove(at: i) }
                            else { draft?.types.append(t) }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                TextField("Another creature type, like Goblin", text: $typeText)
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                    .padding(12).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    let t = typeText.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty, !(draft?.types.contains(t) ?? true) { draft?.types.append(t) }
                    typeText = ""
                } label: { smallButton("Add") }
                .buttonStyle(.plain)
            }
        }
    }

    private func groupPicker(_ binding: Binding<EffectDraft>) -> some View {
        let groups = game.state.tokens.filter { $0.isCreature }
        return VStack(alignment: .leading, spacing: 8) {
            if groups.isEmpty { Text("There are no creature tokens yet.").opacity(0.6) }
            ForEach(groups) { g in
                chip("\(g.name) x\(g.quantity)  (\(game.players[g.owner].name))",
                     on: binding.wrappedValue.groups.contains(g.id)) {
                    if let i = binding.wrappedValue.groups.firstIndex(of: g.id) { draft?.groups.remove(at: i) }
                    else { draft?.groups.append(g.id) }
                }
            }
        }
    }

    private func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }

    private func label(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 12, weight: .bold)).tracking(1.2).opacity(0.55)
    }

    private func chip(_ title: String, on: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
                Text(title).font(.system(size: 16, weight: .semibold, design: .rounded)).lineLimit(1)
            }
            .padding(.horizontal, 16).frame(height: 44)
            .background(Capsule().fill(on ? Color(red: 0.2, green: 0.62, blue: 0.75) : Color.white.opacity(0.12)))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Attacking power

/// Pick attacking token groups and quantities and see their combined power.
/// It is attacking power, not guaranteed damage: blocks and other effects change what actually happens.
struct AttackPowerPanel: View {
    @ObservedObject var game: Game
    let player: Int
    let wide: Bool
    let onUseAsDamage: (Int) -> Void
    let close: () -> Void

    @State private var chosen: [Int: Int] = [:]
    @State private var loaded = false

    private var groups: [TokenGroup] { game.state.tokens(of: player).filter { $0.isCreature } }

    var body: some View {
        let s = game.state
        PanelFrame(title: "Attacking power", refW: wide ? 1100 : 760, refH: wide ? 430 : 780, close: close) {
            VStack(alignment: .leading, spacing: 10) {
                if groups.isEmpty {
                    Text("No creature tokens to attack with yet.").font(.system(size: 18)).opacity(0.7)
                    Spacer(minLength: 0)
                } else {
                    HStack(spacing: 10) {
                        quickButton("Select all that can attack") { selectReady() }
                        quickButton("Clear") { chosen = [:] }
                    }
                    ScrollView {
                        VStack(spacing: 8) { ForEach(groups) { g in row(g, s) } }
                    }
                    .frame(maxHeight: .infinity)
                    summary(s)
                }
            }
        }
        .onAppear { if !loaded { loaded = true; selectReady() } }
    }

    // MARK: Numbers

    private func perToken(_ g: TokenGroup, _ s: GameState) -> Int {
        max(0, s.power(g)) * (s.hasKeyword(g, "Double strike") ? 2 : 1)
    }

    private func total(_ s: GameState, readyOnly: Bool) -> Int {
        groups.reduce(0) { acc, g in
            let n = chosen[g.id] ?? 0
            if readyOnly && !TokenRules.attackBlockers(g, s).isEmpty { return acc }
            return acc + n * perToken(g, s)
        }
    }

    private func selectReady() {
        let s = game.state
        var next: [Int: Int] = [:]
        for g in groups where TokenRules.attackBlockers(g, s).isEmpty { next[g.id] = g.quantity }
        chosen = next
    }

    // MARK: Pieces

    private func row(_ g: TokenGroup, _ s: GameState) -> some View {
        let blockers = TokenRules.attackBlockers(g, s)
        let n = min(chosen[g.id] ?? 0, g.quantity)
        let ds = s.hasKeyword(g, "Double strike")
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("\(g.name)  x\(g.quantity)").font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(1)
                    Text("\(s.power(g))/\(s.toughness(g))")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(s.isModified(g) ? Palette.gold : Color.white)
                    if ds { Chip(text: "Double strike counts twice", fill: Color.teal.opacity(0.8)) }
                }
                HStack(spacing: 6) {
                    if blockers.isEmpty { Chip(text: "Can attack", fill: Palette.good, color: .black) }
                    else { ForEach(blockers, id: \.self) { Chip(text: $0, fill: Palette.warn, color: .black) } }
                }
            }
            Spacer(minLength: 6)
            Button { chosen[g.id] = max(0, n - 1) } label: { panelRound("-", size: 46) }.buttonStyle(.plain)
            Text("\(n) of \(g.quantity)")
                .font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                .frame(minWidth: 84)
            Button { chosen[g.id] = min(g.quantity, n + 1) } label: { panelRound("+", size: 46) }.buttonStyle(.plain)
            Button { chosen[g.id] = g.quantity } label: { smallChip("All") }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(n > 0 ? 0.12 : 0.06)))
    }

    private func summary(_ s: GameState) -> some View {
        let all = total(s, readyOnly: false)
        let ready = total(s, readyOnly: true)
        let flagged = groups.filter { (chosen[$0.id] ?? 0) > 0 && !TokenRules.attackBlockers($0, s).isEmpty }
        let blockedCount = flagged.reduce(0) { $0 + min(chosen[$1.id] ?? 0, $1.quantity) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("\(all)").font(.system(size: 64, weight: .heavy, design: .rounded)).monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text("attacking power").font(.system(size: 20, weight: .bold, design: .rounded))
                    if blockedCount > 0 {
                        Text("\(ready) from tokens that can attack right now")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.warn)
                    }
                }
                Spacer()
            }
            if blockedCount > 0 {
                Text("\(blockedCount) selected can’t attack: " + flagged.map {
                    "\(min(chosen[$0.id] ?? 0, $0.quantity)) \($0.name) (\(TokenRules.attackBlockers($0, s).joined(separator: ", ").lowercased()))"
                }.joined(separator: "; "))
                    .font(.system(size: 14)).opacity(0.85)
            }
            Text("This is the power of the tokens you picked, not guaranteed damage. Blockers, removal and other effects can change what is dealt.")
                .font(.system(size: 13)).opacity(0.6)
            HStack(spacing: 12) {
                Button { tapSelected(s) } label: {
                    Text("Tap selected attackers").font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.horizontal, 22).frame(height: 54)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .disabled(all == 0).opacity(all == 0 ? 0.4 : 1)
                Button { onUseAsDamage(all) } label: {
                    Text("Deal \(all) as damage…").font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.horizontal, 22).frame(height: 54)
                        .background(Capsule().fill(all == 0 ? Color.white.opacity(0.14) : Palette.gold))
                        .foregroundStyle(all == 0 ? Color.white.opacity(0.4) : Color.black.opacity(0.88))
                }
                .buttonStyle(.plain)
                .disabled(all == 0)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))
    }

    /// Taps the selected tokens, except those with vigilance. One undo step.
    private func tapSelected(_ s: GameState) {
        var acts: [Action] = []
        for g in groups {
            let n = min(chosen[g.id] ?? 0, g.quantity)
            if n > 0, !g.tapped, !s.hasKeyword(g, "Vigilance") {
                acts.append(.tokenModify(group: g.id, count: n, mod: .tapped(true)))
            }
        }
        game.record(acts)
        close()
    }

    private func quickButton(_ t: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(t).font(.system(size: 16, weight: .semibold, design: .rounded))
                .padding(.horizontal, 18).frame(height: 46)
                .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private func smallChip(_ t: String) -> some View {
        Text(t).font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, 16).frame(height: 42)
            .background(Capsule().fill(Color.white.opacity(0.14)))
    }
}
