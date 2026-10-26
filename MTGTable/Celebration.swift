import SwiftUI
import AVFoundation

// MARK: - Settings keys

enum CelebrationSettings {
    static let onKey = "celebrationOn"
    static let soundKey = "celebrationSound"
    static let animationKey = "celebrationAnimation"

    private static func flag(_ key: String) -> Bool {
        (UserDefaults.standard.object(forKey: key) as? Bool) ?? true
    }

    static var enabled: Bool { flag(onKey) }
    static var sound: Bool { flag(soundKey) }
    static var animation: Bool { flag(animationKey) }
}

struct CelebrationInfo: Identifiable {
    let id = UUID()
    var winner: String
    var commander: String?
    var colors: [ManaColor]
    var detail: String
}

// MARK: - Sound

final class CelebrationSound {
    static let shared = CelebrationSound()
    private var player: AVAudioPlayer?

    /// Plays a bundled sound and returns its length in seconds (0 if it could not play).
    @discardableResult
    func play(_ name: String) -> TimeInterval {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return 0 }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return 0 }
        player = p
        p.prepareToPlay()
        p.play()
        return p.duration
    }

    func stop() {
        player?.stop()
        player = nil
    }
}

// MARK: - View

struct CelebrationView: View {
    let info: CelebrationInfo
    let dismiss: () -> Void

    @State private var stage = 0          // 0 = drum roll, 1 = winner
    @State private var cardRef: String?

    private let sound = CelebrationSettings.sound
    private let animated = CelebrationSettings.animation

    var body: some View {
        ZStack {
            Rectangle().fill(Identity.background(for: info.colors)).ignoresSafeArea()
            Rectangle().fill(Color.black.opacity(0.45)).ignoresSafeArea()

            if stage == 1 && animated { Confetti().ignoresSafeArea().allowsHitTesting(false) }

            VStack(spacing: 0) {
                content.frame(maxHeight: .infinity, alignment: stage == 1 ? .bottom : .center)
                    .rotationEffect(.degrees(180))
                content.frame(maxHeight: .infinity, alignment: stage == 1 ? .bottom : .center)
            }

            if stage == 1, let cardRef {
                StoreImage(ref: cardRef, contentMode: .fit) { Color.clear }
                    .frame(width: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
                    .scaleEffect(animated ? 1 : 1)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .foregroundStyle(.white)
        .statusBarHidden(true)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await run() }
        .animation(.spring(duration: 0.5), value: stage)
    }

    private var content: some View {
        VStack(spacing: 14) {
            if stage == 0 {
                Text("And the winner is")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                PulsingDots(animated: animated)
            } else {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 78, weight: .bold)).foregroundStyle(Palette.gold)
                Text(info.winner)
                    .font(.system(size: 92, weight: .heavy, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.4)
                if let c = info.commander {
                    Text(c).font(.system(size: 28, weight: .semibold, design: .rounded)).opacity(0.9)
                }
                Text(info.detail).font(.system(size: 22, weight: .medium)).opacity(0.75)
                Text("Tap to continue").font(.system(size: 16, weight: .semibold)).opacity(0.55).padding(.top, 6)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, stage == 1 ? 60 : 0)
        .multilineTextAlignment(.center)
    }

    private func run() async {
        if let c = info.commander {
            let card = await CardStore.shared.card(named: c)
            cardRef = card?.faces.first?.normal
        }
        if !sound && !animated {
            stage = 1
            return
        }
        stage = 0
        var wait: TimeInterval = 2.0
        if sound { wait = max(CelebrationSound.shared.play("drumroll"), 1.2) }
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        stage = 1
        if sound { CelebrationSound.shared.play("trumpet") }
    }

    private func finish() {
        CelebrationSound.shared.stop()
        dismiss()
    }
}

private struct PulsingDots: View {
    let animated: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = animated ? (sin(t * 6 - Double(i) * 0.9) + 1) / 2 : 0.6
                    Circle().frame(width: 22, height: 22).scaleEffect(0.6 + 0.6 * phase).opacity(0.4 + 0.6 * phase)
                }
            }
        }
    }
}

private struct Confetti: View {
    private struct Piece {
        let x: Double, speed: Double, offset: Double, size: Double, spin: Double, drift: Double
        let color: Color
    }

    private let pieces: [Piece] = {
        var rng = SystemRandomNumberGenerator()
        let colors: [Color] = [Palette.gold, .white, Color(red: 0.95, green: 0.45, blue: 0.45),
                               Color(red: 0.4, green: 0.8, blue: 0.95), Color(red: 0.6, green: 0.9, blue: 0.5),
                               Color(red: 0.8, green: 0.55, blue: 0.95)]
        return (0..<90).map { _ in
            Piece(x: .random(in: 0...1, using: &rng), speed: .random(in: 0.12...0.32, using: &rng),
                  offset: .random(in: 0...1, using: &rng), size: .random(in: 9...20, using: &rng),
                  spin: .random(in: -6...6, using: &rng), drift: .random(in: -0.05...0.05, using: &rng),
                  color: colors.randomElement()!)
        }
    }()

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { gc, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                for p in pieces {
                    let progress = (t * p.speed + p.offset).truncatingRemainder(dividingBy: 1.0)
                    let y = progress * (size.height + 60) - 30
                    let x = (p.x + p.drift * sin(t * 2 + p.offset * 6)) * size.width
                    var c = gc
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(t * p.spin + p.offset * 6))
                    c.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)),
                           with: .color(p.color))
                }
            }
        }
    }
}
