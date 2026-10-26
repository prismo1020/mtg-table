import SwiftUI

/// Works out a commander's current power and toughness from its base stats and every modifier on it.
/// The result is attacking power, kept separate from commander damage actually dealt.
struct VoltronPanel: View {
    @ObservedObject var game: Game
    let player: Int
    let index: Int
    let wide: Bool
    let onDeal: (Int, CommanderRef) -> Void
    let close: () -> Void

    private struct Draft {
        var name = ""
        var kind: VoltronKind = .equipment
        var power = 0
        var toughness = 0
        var keywords: [String] = []
        var expiry = 0           // 0 permanent, 1 this turn, 2 until my next turn
    }

    @State private var draft: Draft?

    private var ref: CommanderRef { CommanderRef(player: player, index: index) }
    private var v: VoltronCommander { game.state.voltron(ref) }
    private var name: String { game.commanderName(ref) }

    var body: some View {
        PanelFrame(title: "\(name) calculator", refW: wide ? 1100 : 780, refH: wide ? 430 : 840, close: close) {
            if draft != nil { editor } else { main }
        }
    }

    // MARK: Main

    private var main: some View {
        VStack(alignment: .leading, spacing: 10) {
            results
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    baseSection
                    keywordSection
                    modSection
                    quickSection
                    Text("Not covered: copy effects, power set to a fixed number, or stats that depend on the board. For those, set the base stats above or add a modifier with the difference.")
                        .font(.system(size: 13)).opacity(0.6)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var results: some View {
        let power = v.power, tough = v.toughness
        return HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(power)/\(tough)")
                    .font(.system(size: 62, weight: .heavy, design: .rounded)).foregroundStyle(v.mods.contains { $0.enabled } ? Palette.gold : .white)
                Text("current power and toughness").font(.system(size: 13, weight: .semibold)).opacity(0.6)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Attacking power: \(v.attackingPower)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                if v.has("Double strike") { Text("Double strike counts the power twice").font(.system(size: 14)).opacity(0.75) }
                Text("This is calculated power, not commander damage dealt.")
                    .font(.system(size: 13)).opacity(0.6)
            }
            Spacer(minLength: 6)
            Button { onDeal(v.attackingPower, ref) } label: {
                Text("Deal \(v.attackingPower) as commander damage…")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .padding(.horizontal, 20).frame(height: 54)
                    .background(Capsule().fill(v.attackingPower > 0 ? Palette.gold : Color.white.opacity(0.14)))
                    .foregroundStyle(v.attackingPower > 0 ? Color.black.opacity(0.88) : Color.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(v.attackingPower <= 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))
    }

    private var baseSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Base stats")
            HStack(spacing: 24) {
                Stepper("Power \(v.basePower)", value: Binding(get: { v.basePower },
                                                              set: { game.record(.voltronBase(ref, power: $0, toughness: v.baseToughness)) }), in: 0...30)
                Stepper("Toughness \(v.baseToughness)", value: Binding(get: { v.baseToughness },
                                                                      set: { game.record(.voltronBase(ref, power: v.basePower, toughness: $0)) }), in: 0...30)
            }
            .font(.system(size: 18, weight: .semibold, design: .rounded))
        }
    }

    private var keywordSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Keywords the commander has on its own")
            FlowLayout(spacing: 8) {
                ForEach(VoltronKeywords.all, id: \.self) { k in
                    let own = v.baseKeywords.contains { $0.caseInsensitiveCompare(k) == .orderedSame }
                    let granted = !own && v.has(k)
                    chip(k + (granted ? " (granted)" : ""), on: own || granted, dim: granted) {
                        if !granted { game.record(.voltronKeyword(ref, k, !own)) }
                    }
                }
            }
        }
    }

    private var modSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Modifiers and what each adds")
            if v.mods.isEmpty { Text("None yet. Add equipment, auras, counters or other effects.").font(.system(size: 15)).opacity(0.6) }
            ForEach(v.mods) { m in
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(get: { m.enabled }, set: { game.record(.voltronSetMod(ref, id: m.id, enabled: $0)) }))
                        .labelsHidden().fixedSize()
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(m.name).font(.system(size: 18, weight: .bold, design: .rounded))
                            Chip(text: m.kind.title, fill: Color.white.opacity(0.16))
                            Text(m.effectText).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(red: 0.35, green: 0.8, blue: 0.9))
                        }
                        Text(expiryText(m.expiry)).font(.system(size: 13)).opacity(0.6)
                    }
                    .opacity(m.enabled ? 1 : 0.5)
                    Spacer(minLength: 6)
                    small("Remove", danger: true) { game.record(.voltronRemoveMod(ref, id: m.id)) }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
            }
        }
    }

    private var quickSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Add a modifier")
            FlowLayout(spacing: 8) {
                quick("+1/+1 counter", .counter, 1, 1)
                quick("Equipment +2/+0", .equipment, 2, 0)
                quick("Aura +2/+2", .aura, 2, 2)
                quick("+3/+0 until end of turn", .other, 3, 0, expiry: .endOfTurn(game.state.turnSerial))
                quick("Flying", .other, 0, 0, keywords: ["Flying"])
                quick("Double strike", .other, 0, 0, keywords: ["Double strike"])
                chip("Custom…", on: false) { draft = Draft() }
            }
        }
    }

    private func quick(_ title: String, _ kind: VoltronKind, _ p: Int, _ t: Int, keywords: [String] = [],
                       expiry: VoltronExpiry = .permanent) -> some View {
        chip(title, on: false) {
            game.record(.voltronAddMod(ref, VoltronMod(name: title, kind: kind, power: p, toughness: t,
                                                       keywords: keywords, expiry: expiry)))
        }
    }

    private func expiryText(_ e: VoltronExpiry) -> String {
        switch e {
        case .permanent: return "Stays until removed"
        case let .endOfTurn(serial): return game.state.turnSerial <= serial ? "Until end of this turn" : "Expired"
        case let .untilTurnStarts(p): return "Until \(game.players[p].name)’s next turn"
        }
    }

    // MARK: Custom modifier editor

    private var editor: some View {
        let b = Binding<Draft>(get: { draft ?? Draft() }, set: { draft = $0 })
        let d = b.wrappedValue
        return VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Name (for example Sword of Fire and Ice)", text: b.name)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .padding(12).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    label("Type")
                    Picker("", selection: b.kind) {
                        ForEach(VoltronKind.allCases) { k in Text(k.title).tag(k) }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 24) {
                        Stepper("Power \(signed(d.power))", value: b.power, in: -9...20)
                        Stepper("Toughness \(signed(d.toughness))", value: b.toughness, in: -9...20)
                    }
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    label("Grants keywords")
                    FlowLayout(spacing: 8) {
                        ForEach(VoltronKeywords.all, id: \.self) { k in
                            chip(k, on: d.keywords.contains(k)) {
                                if let i = b.wrappedValue.keywords.firstIndex(of: k) { draft?.keywords.remove(at: i) }
                                else { draft?.keywords.append(k) }
                            }
                        }
                    }
                    label("How long")
                    Picker("", selection: b.expiry) {
                        Text("Until removed").tag(0)
                        Text("Until end of turn").tag(1)
                        Text("Until my next turn").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 14) {
                Button { draft = nil } label: {
                    Text("Cancel").font(.system(size: 20, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 56).background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                Button { saveDraft() } label: {
                    Text("Add modifier").font(.system(size: 20, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 56)
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
        return d.power != 0 || d.toughness != 0 || !d.keywords.isEmpty
    }

    private func saveDraft() {
        guard let d = draft, canSave else { return }
        let expiry: VoltronExpiry
        switch d.expiry {
        case 1: expiry = .endOfTurn(game.state.turnSerial)
        case 2: expiry = .untilTurnStarts(player)
        default: expiry = .permanent
        }
        let name = d.name.trimmingCharacters(in: .whitespaces)
        game.record(.voltronAddMod(ref, VoltronMod(name: name.isEmpty ? d.kind.title : name, kind: d.kind,
                                                   power: d.power, toughness: d.toughness,
                                                   keywords: d.keywords, expiry: expiry)))
        draft = nil
    }

    // MARK: Pieces

    private func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }

    private func label(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 12, weight: .bold)).tracking(1.2).opacity(0.55)
    }

    private func chip(_ title: String, on: Bool, dim: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
                Text(title).font(.system(size: 16, weight: .semibold, design: .rounded)).lineLimit(1)
            }
            .padding(.horizontal, 16).frame(height: 44)
            .background(Capsule().fill(on ? Color(red: 0.2, green: 0.62, blue: 0.75).opacity(dim ? 0.55 : 1) : Color.white.opacity(0.12)))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func small(_ title: String, danger: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16).frame(height: 42)
                .background(Capsule().fill(danger ? Palette.danger.opacity(0.8) : Color.white.opacity(0.14)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
