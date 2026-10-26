import SwiftUI

// MARK: - Small helpers

/// Lays out chips left to right and wraps them onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

struct Chip: View {
    let text: String
    var fill: Color = .black.opacity(0.45)
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(fill))
            .foregroundStyle(color)
    }
}

/// Art behind a token. Decoration only: never catches taps.
private func tokenBackground(art: String?, colors: [ManaColor]) -> some View {
    ZStack {
        Rectangle().fill(Identity.background(for: colors))
        GeometryReader { geo in
            StoreImage(ref: art) { Color.clear }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        Rectangle().fill(LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.28), .black.opacity(0.80)],
                                        startPoint: .top, endPoint: .bottom))
    }
    .clipped()
    .allowsHitTesting(false)
}

// MARK: - A group of tokens, shown as a card with its artwork

struct TokenCard: View {
    @ObservedObject var game: Game
    let group: TokenGroup
    let state: GameState
    let height: CGFloat
    let onOpen: () -> Void

    static let width: CGFloat = 200

    private var statusText: (String, Color, Color) {
        let g = group
        if !g.isCreature { return (g.tapped ? "Tapped" : "In play", g.tapped ? Palette.warn : Color.white.opacity(0.25), .black) }
        if g.tapped { return ("Tapped", Palette.warn, .black) }
        let blockers = TokenRules.attackBlockers(g, state)
        if blockers.isEmpty { return ("Ready", Palette.good, .black) }
        return (blockers[0] == "Summoning sick" ? "Sick" : blockers[0], Palette.warn, .black)
    }

    var body: some View {
        let g = group
        let modified = state.isModified(g)
        let status = statusText
        let fx = state.effects(affecting: g)
        let extras: [(String, Color)] =
            g.counters.sorted { $0.key < $1.key }.map { ("\($0.value) \($0.key)", Color.purple.opacity(0.75)) }
            + state.keywords(g).map { ($0, Color.black.opacity(0.45)) }
            + fx.map { ($0.name, Color(red: 0.2, green: 0.62, blue: 0.75).opacity(0.85)) }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(g.name)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.65)
                    Text(subtype)
                        .font(.system(size: 11, weight: .medium)).opacity(0.8).lineLimit(1)
                }
                Spacer(minLength: 2)
                Text("\(g.quantity)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit()
                    .padding(.horizontal, 12).frame(minWidth: 44, minHeight: 36)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
            }

            Spacer(minLength: 0)

            if !extras.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(extras.prefix(2).enumerated()), id: \.offset) { _, e in Chip(text: e.0, fill: e.1) }
                    if extras.count > 2 { Chip(text: "+\(extras.count - 2)") }
                }
            }

            HStack(alignment: .center) {
                if g.isCreature {
                    Text("\(state.power(g))/\(state.toughness(g))")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(modified ? Palette.gold : Color.white)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                }
                Spacer(minLength: 2)
                Text(status.0)
                    .font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(status.1))
                    .foregroundStyle(status.2)
            }

            HStack(spacing: 8) {
                small("minus") { game.record(.tokenRemove(group: g.id, count: 1)) }
                small("plus") { game.record(.tokenAdd(group: g.id, count: 1)) }
                Spacer(minLength: 2)
                Button {
                    game.tokenModify(g.id, count: g.quantity, .tapped(!g.tapped))
                } label: {
                    Text(g.tapped ? "Untap" : "Tap")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .padding(.horizontal, 18).frame(height: 38)
                        .background(Capsule().fill(Color.white.opacity(0.26)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: Self.width, height: height)
        .background(tokenBackground(art: g.art, colors: g.colors))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.28), lineWidth: 1.5))
        .saturation(g.tapped ? 0.35 : 1)
        .opacity(g.tapped ? 0.78 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { onOpen() }
        .foregroundStyle(.white)
    }

    private var subtype: String {
        let t = group.types.replacingOccurrences(of: "Token ", with: "")
        return t
    }

    private func small(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold))
                .frame(width: 42, height: 38)
                .background(Capsule().fill(Color.white.opacity(0.26)))
        }
        .buttonStyle(.plain)
    }
}

/// The empty slot at the end of a token row.
struct AddTokenCard: View {
    let height: CGFloat
    let style: ZoneStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 34, weight: .semibold))
                Text("Add token").font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .frame(width: 150, height: height)
            .foregroundStyle(style.soft)
            .background(RoundedRectangle(cornerRadius: 20).fill(style.chip.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .strokeBorder(style.stroke, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Panel for changing part of a group

struct GroupPanel: View {
    @ObservedObject var game: Game
    let group: TokenGroup
    let wide: Bool
    let close: () -> Void

    @State private var count = 0

    private var n: Int { max(1, min(count == 0 ? group.quantity : count, group.quantity)) }

    var body: some View {
        let g = group
        let s = game.state
        ZStack {
            Color.black.opacity(0.6).onTapGesture { close() }
            FitView(refW: wide ? 1240 : 780, refH: wide ? 430 : 700) {
                VStack(alignment: .leading, spacing: 12) {
                    header(g, s)
                    if wide {
                        HStack(alignment: .top, spacing: 28) {
                            VStack(alignment: .leading, spacing: 12) {
                                applyTo(g)
                                stateSection(g, s)
                                otherSection(g)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if g.isCreature {
                                VStack(alignment: .leading, spacing: 12) {
                                    counterSection(g)
                                    keywordSection(g)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        applyTo(g)
                        stateSection(g, s)
                        if g.isCreature {
                            counterSection(g)
                            keywordSection(g)
                        }
                        otherSection(g)
                    }
                }
                .foregroundStyle(.white)
                .padding(22)
                .background(RoundedRectangle(cornerRadius: 28).fill(Palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .onChange(of: group.quantity) { _, q in if count > q { count = q } }
    }

    // MARK: Sections

    private func header(_ g: TokenGroup, _ s: GameState) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(g.name)  x\(g.quantity)").font(.system(size: 28, weight: .bold, design: .rounded))
                Text(summary(g, s)).font(.system(size: 15, weight: .medium)).opacity(0.7)
                let fx = s.effects(affecting: g)
                if !fx.isEmpty {
                    Text("Effects: " + fx.map { "\($0.name) (\($0.effectText))" }.joined(separator: ", "))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(red: 0.35, green: 0.8, blue: 0.9))
                }
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 20, weight: .bold))
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
    }

    private func applyTo(_ g: TokenGroup) -> some View {
        HStack(spacing: 12) {
            Text("Apply to").font(.system(size: 17, weight: .semibold)).opacity(0.8)
            stepButton("minus") { count = max(1, n - 1) }
            Text("\(n) of \(g.quantity)")
                .font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit()
                .frame(minWidth: 96)
            stepButton("plus") { count = min(g.quantity, n + 1) }
            pill("All") { count = g.quantity }
            if g.quantity > 1 { pill("One") { count = 1 } }
        }
    }

    private func stateSection(_ g: TokenGroup, _ s: GameState) -> some View {
        section("State") {
            action("Tap", "hand.tap") { apply(.tapped(true)) }
            action("Untap", "arrow.counterclockwise") { apply(.tapped(false)) }
            if g.isCreature {
                action(TokenRules.isSick(g, s) ? "Clear summoning sickness" : "Mark summoning sick", "bolt.slash") {
                    apply(.sick(!TokenRules.isSick(g, s)))
                }
                action(g.cantAttack ? "Can attack again" : "Can’t attack", "nosign") { apply(.cantAttack(!g.cantAttack)) }
            }
            action(g.noUntap ? "Untaps normally" : "Doesn’t untap", "lock") { apply(.noUntap(!g.noUntap)) }
        }
    }

    private func counterSection(_ g: TokenGroup) -> some View {
        section("Counters and bonuses") {
            action("+1/+1 counter", "plus.circle") { apply(.counter("+1/+1", 1)) }
            action("-1/-1 counter", "minus.circle") { apply(.counter("-1/-1", 1)) }
            Menu {
                ForEach(TokenKeywords.counters.filter { $0 != "+1/+1" && $0 != "-1/-1" }, id: \.self) { k in
                    Button("Add \(k) counter") { apply(.counter(k, 1)) }
                }
                ForEach(g.counters.keys.sorted(), id: \.self) { k in
                    Button("Remove one \(k) counter") { apply(.counter(k, -1)) }
                }
            } label: { label("Other counters", "number.circle") }
            action("+1/+1 bonus", "arrow.up.circle") { apply(.bonus(power: 1, toughness: 1)) }
            action("+1/+0 bonus", "arrow.up.right.circle") { apply(.bonus(power: 1, toughness: 0)) }
            action("-1/-1 bonus", "arrow.down.circle") { apply(.bonus(power: -1, toughness: -1)) }
            if g.bonusPower != 0 || g.bonusToughness != 0 {
                action("Reset bonus", "arrow.uturn.backward.circle") {
                    apply(.bonus(power: -g.bonusPower, toughness: -g.bonusToughness))
                }
            }
        }
    }

    private func keywordSection(_ g: TokenGroup) -> some View {
        section("Keywords") {
            Menu {
                ForEach(TokenKeywords.common.filter { !game.state.hasKeyword(g, $0) }, id: \.self) { k in
                    Button(k) { apply(.keyword(k, true)) }
                }
            } label: { label("Give a keyword", "plus.square") }
            if !g.allKeywords.isEmpty {
                Menu {
                    ForEach(g.allKeywords, id: \.self) { k in
                        Button("Remove \(k)") { apply(.keyword(k, false)) }
                    }
                } label: { label("Remove a keyword", "minus.square") }
            }
        }
    }

    private func otherSection(_ g: TokenGroup) -> some View {
        section("Other") {
            action("Add \(n) more", "plus.rectangle.on.rectangle") {
                game.record(.tokenAdd(group: g.id, count: n)); close()
            }
            action("Give to \(game.players[1 - g.owner].name)", "arrow.left.arrow.right") {
                apply(.controller(1 - g.owner))
            }
            action("Remove \(n)", "trash", destructive: true) {
                game.record(.tokenRemove(group: g.id, count: n)); close()
            }
        }
    }

    private func summary(_ g: TokenGroup, _ s: GameState) -> String {
        var parts: [String] = []
        if g.isCreature { parts.append("\(s.power(g))/\(s.toughness(g))") }
        parts.append(g.tapped ? "tapped" : "untapped")
        if TokenRules.isSick(g, s) { parts.append("summoning sick") }
        return parts.joined(separator: "  ·  ")
    }

    private func apply(_ mod: TokenMod) {
        game.tokenModify(group.id, count: n, mod)
        close()
    }

    // MARK: Pieces

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 12, weight: .bold)).tracking(1.2).opacity(0.5)
            FlowLayout(spacing: 8) { content() }
        }
    }

    private func action(_ title: String, _ icon: String, destructive: Bool = false,
                        _ run: @escaping () -> Void) -> some View {
        Button(action: run) { label(title, icon, destructive: destructive) }.buttonStyle(.plain)
    }

    private func label(_ title: String, _ icon: String, destructive: Bool = false) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .padding(.horizontal, 16).frame(height: 48)
            .background(Capsule().fill(destructive ? Palette.danger.opacity(0.85) : Color.white.opacity(0.13)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(destructive ? 0 : 0.12), lineWidth: 1))
            .foregroundStyle(.white)
    }

    private func stepButton(_ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: icon).font(.system(size: 20, weight: .bold))
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private func pill(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
                .padding(.horizontal, 18).frame(height: 44)
                .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Adding tokens

/// Opens the sheet at (nearly) full size so nothing is cramped, in portrait or landscape.
struct FullSizeSheet: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}

struct TokenTile: View {
    let template: TokenTemplate
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(template.name).font(.system(size: 18, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 6) {
                Text(template.statsText).font(.system(size: 22, weight: .heavy, design: .rounded))
                ForEach(template.keywords.prefix(2), id: \.self) { Chip(text: $0) }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110, alignment: .topLeading)
        .background(tokenBackground(art: template.art, colors: template.colors))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.2),
                                                                 lineWidth: selected ? 5 : 1))
        .foregroundStyle(.white)
    }
}

struct AddTokenSheet: View {
    @ObservedObject var game: Game
    let owner: Int
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = TokenLibrary.shared

    @State private var tab = 0
    @State private var quickFilter = ""
    @State private var selected: TokenTemplate?
    @State private var quantity = 1
    @AppStorage("tokenMultipliers") private var multString = ""
    @State private var manual = false
    @State private var manualValue = 1

    // Search
    @State private var query = ""
    @State private var results: [TokenTemplate] = []
    @State private var searching = false
    @State private var searchMessage: String?

    // Custom
    @State private var cName = ""
    @State private var cCreature = true
    @State private var cType = ""
    @State private var cPower = 1
    @State private var cToughness = 1
    @State private var cColors: [ManaColor] = []
    @State private var cKeywords: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 190), spacing: 12)]

    private var customTemplate: TokenTemplate? {
        let name = cName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let type = cType.trimmingCharacters(in: .whitespaces)
        let types = cCreature ? "Token Creature" + (type.isEmpty ? "" : " — \(type)") : "Token " + (type.isEmpty ? "Artifact" : type)
        return TokenTemplate(name: name, types: types, power: cCreature ? cPower : nil,
                             toughness: cCreature ? cToughness : nil, colors: cColors,
                             keywords: TokenKeywords.common.filter { cKeywords.contains($0) },
                             art: nil, normal: nil)
    }

    private var chosen: TokenTemplate? { tab == 2 ? customTemplate : selected }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Quick").tag(0)
                    Text("Search").tag(1)
                    Text("Custom").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch tab {
                    case 0: quick
                    case 1: search
                    default: custom
                    }
                }
                .frame(maxHeight: .infinity)

                bottomBar
            }
            .navigationTitle("Add token for \(game.players[owner].name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
        // The sheet always opens upright at the bottom, so turn it around for the player across the table.
        .rotationEffect(.degrees(owner == 1 ? 180 : 0))
        .modifier(FullSizeSheet())
    }

    // MARK: Tabs

    private func matchesFilter(_ t: TokenTemplate) -> Bool {
        let q = quickFilter.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || t.name.lowercased().contains(q) || t.types.lowercased().contains(q)
    }

    private var quick: some View {
        let recents = library.recents.filter(matchesFilter)
        let creatures = library.presets.filter { $0.isCreature && matchesFilter($0) }
        let others = library.presets.filter { !$0.isCreature && matchesFilter($0) }
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter \(library.presets.count) tokens", text: $quickFilter)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !quickFilter.isEmpty {
                    Button { quickFilter = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !recents.isEmpty {
                        Text("Recently used").font(.headline)
                        LazyVGrid(columns: columns, spacing: 12) { ForEach(recents) { t in tile(t) } }
                    }
                    if !creatures.isEmpty {
                        Text("Creatures").font(.headline)
                        LazyVGrid(columns: columns, spacing: 12) { ForEach(creatures) { t in tile(t) } }
                    }
                    if !others.isEmpty {
                        Text("Artifacts and other tokens").font(.headline)
                        LazyVGrid(columns: columns, spacing: 12) { ForEach(others) { t in tile(t) } }
                    }
                    if recents.isEmpty && creatures.isEmpty && others.isEmpty {
                        Text("Nothing matches. Try Search for more tokens from Scryfall, or Custom.")
                            .foregroundStyle(.secondary).padding(.top, 20)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    private var search: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Token name, like Soldier or Treasure", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
                    .padding(12)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                Button { runSearch() } label: {
                    if searching { ProgressView() } else { Label("Search", systemImage: "magnifyingglass") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            }
            .padding(.horizontal)

            if let searchMessage { Text(searchMessage).font(.footnote).foregroundStyle(.secondary) }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(results) { t in tile(t) }
                }
                .padding(.horizontal)
            }
        }
    }

    private var custom: some View {
        Form {
            Section("Token") {
                TextField("Name (for example Cat)", text: $cName)
                Toggle("Creature", isOn: $cCreature)
                TextField(cCreature ? "Creature type (for example Cat Warrior)" : "Type (for example Artifact — Gold)",
                          text: $cType)
                if cCreature {
                    Stepper("Power: \(cPower)", value: $cPower, in: 0...30)
                    Stepper("Toughness: \(cToughness)", value: $cToughness, in: 0...30)
                }
            }
            Section("Colors") { ColorPips(colors: $cColors) }
            if cCreature {
                Section("Keywords") {
                    FlowLayout(spacing: 8) {
                        ForEach(TokenKeywords.common, id: \.self) { k in
                            Button {
                                if cKeywords.contains(k) { cKeywords.remove(k) } else { cKeywords.insert(k) }
                            } label: {
                                Text(k).font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(cKeywords.contains(k) ? Color.accentColor : Color.white.opacity(0.12)))
                                    .foregroundStyle(cKeywords.contains(k) ? Color.black : Color.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ t: TokenTemplate) -> some View {
        Button { selected = t } label: { TokenTile(template: t, selected: selected?.id == t.id) }
            .buttonStyle(.plain)
    }

    // MARK: Bottom bar (quantity and token math)

    private var multipliers: [Int] {
        multString.split(separator: ",").compactMap { Int($0) }.filter { $0 >= 2 }
    }

    private func setMultipliers(_ list: [Int]) { multString = list.map(String.init).joined(separator: ",") }

    private var calculated: Int { multipliers.reduce(quantity) { $0 * $1 } }

    private var finalQuantity: Int { manual ? manualValue : calculated }

    private var calculationText: String {
        if manual { return "Set by hand: \(manualValue)" }
        if multipliers.isEmpty { return "\(quantity)" }
        return ([String(quantity)] + multipliers.map { "x \($0)" }).joined(separator: " ") + " = \(calculated)"
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            FlowLayout(spacing: 10) {
                Text("Starting amount").font(.headline).fixedSize().padding(.trailing, 4)
                ForEach([1, 2, 3, 4, 5, 10], id: \.self) { q in
                    Button("\(q)") { quantity = q }
                        .font(.headline)
                        .frame(width: 52, height: 44)
                        .background(Capsule().fill(quantity == q ? Color.accentColor : Color.white.opacity(0.14)))
                        .foregroundStyle(quantity == q ? Color.black : Color.white)
                }
                Stepper("\(quantity)", value: $quantity, in: 1...99).fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FlowLayout(spacing: 10) {
                Text("Token doublers").font(.headline).fixedSize().padding(.trailing, 4)
                ForEach(Array(multipliers.enumerated()), id: \.offset) { i, m in
                    Button {
                        var list = multipliers
                        list.remove(at: i)
                        setMultipliers(list)
                    } label: {
                        Label("x\(m)", systemImage: "xmark.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 14).frame(height: 44)
                            .background(Capsule().fill(Color.teal.opacity(0.85)))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                }
                Button { setMultipliers(multipliers + [2]) } label: { mathButton("Add doubler (x2)") }.buttonStyle(.plain)
                Button { setMultipliers(multipliers + [3]) } label: { mathButton("Add tripler (x3)") }.buttonStyle(.plain)
                if !multipliers.isEmpty {
                    Button { setMultipliers([]) } label: { mathButton("Clear") }.buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 14) {
                Toggle("Set the result by hand (for other effects)", isOn: $manual)
                    .font(.subheadline.weight(.semibold))
                    .onChange(of: manual) { _, on in if on { manualValue = calculated } }
                if manual { Stepper("\(manualValue)", value: $manualValue, in: 1...999).fixedSize() }
            }

            Text("Tokens to add:  \(calculationText)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if let t = chosen {
                    game.createTokens(owner, t, quantity: finalQuantity)
                    dismiss()
                }
            } label: {
                Text(chosen.map { "Add \(finalQuantity) × \($0.name)" } ?? "Choose a token")
                    .font(.title3.bold()).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(chosen == nil)
        }
        .padding()
        .background(Color(white: 0.1))
    }

    private func mathButton(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).frame(height: 44)
            .background(Capsule().fill(Color.white.opacity(0.14)))
            .foregroundStyle(.white)
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        searchMessage = nil
        Task {
            do {
                let found = try await TokenLibrary.shared.search(q)
                await MainActor.run {
                    results = found
                    searchMessage = found.isEmpty ? "No tokens found. Try a different name, or use Custom." : nil
                    searching = false
                }
            } catch ScryfallError.network {
                await MainActor.run {
                    searchMessage = "Couldn’t reach Scryfall. Use Quick or Custom while offline."
                    searching = false
                }
            } catch {
                await MainActor.run {
                    searchMessage = "Something went wrong with the search."
                    searching = false
                }
            }
        }
    }
}
