import SwiftUI
import AudioToolbox

struct TimerSettings: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable {
        case off, turn, chess

        var title: String {
            switch self {
            case .off: return "Off"
            case .turn: return "Turn timer"
            case .chess: return "Chess clock"
            }
        }
    }

    var mode: Mode = .off
    var chessMinutes: [Int] = [25, 25]
    /// Soft limit for one turn in turn-timer mode. 0 means no limit.
    var turnLimitMinutes: Int = 0
    /// Chess clock warning, in seconds remaining.
    var warnSeconds: Int = 60
    var soundAlerts: Bool = true
}

struct ClockState: Codable, Equatable {
    var mode: TimerSettings.Mode
    var running: Bool
    var runner: Int                    // whose clock is counting
    var segmentStart: Date?            // when the running stretch began
    var heartbeat: Date                // last time the game was saved (used when restoring)
    var turnBase: TimeInterval         // time in the current turn, before the running stretch
    var playerUsed: [TimeInterval]     // time each player has used on the clock
    var remaining: [TimeInterval]      // chess-clock time left for each player
    var gameBase: TimeInterval         // total game time, before the running stretch
    var lastActive: Int
    var lastTurn: Int
}

/// Tracks game time, turn time, per-player time and the chess clock. It never ends a game:
/// reaching a limit only raises an alert.
final class ClockModel: ObservableObject {
    @Published private(set) var state: ClockState
    @Published var settings: TimerSettings
    @Published var banner: String?

    var onChange: (() -> Void)?

    private var ticker: Timer?
    private var warned = [false, false]
    private var expired = [false, false]
    private var turnLimitFired = false
    private var lastHeartbeat = Date()
    private var bannerToken = 0

    // MARK: Setup

    init(settings: TimerSettings, active: Int, turnSerial: Int) {
        self.settings = settings
        let budgets = settings.chessMinutes.map { TimeInterval($0 * 60) }
        state = ClockState(mode: settings.mode, running: true, runner: active, segmentStart: Date(),
                           heartbeat: Date(), turnBase: 0, playerUsed: [0, 0],
                           remaining: budgets.count == 2 ? budgets : [1500, 1500], gameBase: 0,
                           lastActive: active, lastTurn: turnSerial)
        startTicker()
    }

    init(restoring saved: ClockState, settings: TimerSettings) {
        self.settings = settings
        var s = saved
        // Count time only up to the last save, so time while the app was closed isn't charged.
        if s.running, let start = s.segmentStart {
            let seg = max(0, s.heartbeat.timeIntervalSince(start))
            s.turnBase += seg
            s.playerUsed[s.runner] += seg
            if s.mode == .chess { s.remaining[s.runner] -= seg }
            s.gameBase += seg
        }
        if s.mode == .off {
            s.running = true
            s.segmentStart = Date()
        } else {
            s.running = false           // timed games come back paused
            s.segmentStart = nil
        }
        state = s
        startTicker()
    }

    deinit { ticker?.invalidate() }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    // MARK: Live values

    private func segment(_ now: Date) -> TimeInterval {
        guard state.running, let start = state.segmentStart else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }

    func liveGame(_ now: Date = Date()) -> TimeInterval { state.gameBase + segment(now) }

    func liveTurn(_ now: Date = Date()) -> TimeInterval { state.turnBase + segment(now) }

    func liveUsed(_ p: Int, _ now: Date = Date()) -> TimeInterval {
        state.playerUsed[p] + (state.runner == p ? segment(now) : 0)
    }

    func liveRemaining(_ p: Int, _ now: Date = Date()) -> TimeInterval {
        state.remaining[p] - (state.runner == p ? segment(now) : 0)
    }

    var isPaused: Bool { !state.running }
    var mode: TimerSettings.Mode { state.mode }

    // MARK: Changes

    private func commit(_ now: Date = Date()) {
        guard state.running, let start = state.segmentStart else { return }
        let seg = max(0, now.timeIntervalSince(start))
        state.turnBase += seg
        state.playerUsed[state.runner] += seg
        if state.mode == .chess { state.remaining[state.runner] -= seg }
        state.gameBase += seg
        state.segmentStart = now
    }

    func pause() {
        guard state.running else { return }
        commit()
        state.running = false
        state.segmentStart = nil
        onChange?()
    }

    func resume() {
        guard !state.running else { return }
        state.running = true
        state.segmentStart = Date()
        onChange?()
    }

    /// Call whenever the active player or turn number may have changed (including undo/redo).
    func sync(active: Int, turnSerial: Int) {
        guard state.lastActive != active || state.lastTurn != turnSerial else { return }
        commit()
        state.turnBase = 0
        state.runner = active
        state.lastActive = active
        state.lastTurn = turnSerial
        turnLimitFired = false
        onChange?()
    }

    /// Chess clock: the non-active player starts responding and the running clock switches to them.
    func takePriority(by p: Int) {
        guard state.mode == .chess, p != state.lastActive, state.runner != p else { return }
        commit()
        state.runner = p
        onChange?()
    }

    /// Chess clock: hand the running clock back to the active player without advancing the turn.
    func returnClock() {
        guard state.runner != state.lastActive else { return }
        commit()
        state.runner = state.lastActive
        onChange?()
    }

    func setMode(_ mode: TimerSettings.Mode) {
        commit()
        state.mode = mode
        settings.mode = mode
        if mode == .chess, state.remaining.count != 2 {
            state.remaining = settings.chessMinutes.map { TimeInterval($0 * 60) }
        }
        warned = [false, false]
        expired = [false, false]
        turnLimitFired = false
        state.runner = state.lastActive
        onChange?()
    }

    func addTime(to p: Int, seconds: Int) {
        commit()
        state.remaining[p] += TimeInterval(seconds)
        warned[p] = false
        expired[p] = false
        onChange?()
    }

    func snapshot() -> ClockState {
        var s = state
        s.heartbeat = Date()
        return s
    }

    // MARK: Alerts (never end the game)

    private func tick() {
        guard state.running else { return }
        let now = Date()
        // No redraw here: the clock faces refresh themselves, and redrawing the whole table every
        // half second would collapse any open menu.

        if state.mode == .chess {
            let p = state.runner
            let left = liveRemaining(p, now)
            if left <= 0, !expired[p] {
                expired[p] = true
                raise("Time’s up for \(label(p)). Play continues.", loud: true)
            } else if left <= TimeInterval(settings.warnSeconds), left > 0, !warned[p] {
                warned[p] = true
                raise("\(label(p)) has \(Self.format(left)) left.", loud: false)
            }
        } else if state.mode == .turn, settings.turnLimitMinutes > 0, !turnLimitFired,
                  liveTurn(now) >= TimeInterval(settings.turnLimitMinutes * 60) {
            turnLimitFired = true
            raise("Turn limit reached (\(settings.turnLimitMinutes) min). Play continues.", loud: true)
        }

        if now.timeIntervalSince(lastHeartbeat) >= 5 {
            lastHeartbeat = now
            onChange?()
        }
    }

    var names: [String] = ["Player 1", "Player 2"]

    private func label(_ p: Int) -> String { names.indices.contains(p) ? names[p] : "Player \(p + 1)" }

    private func raise(_ text: String, loud: Bool) {
        banner = text
        if settings.soundAlerts { AudioServicesPlaySystemSound(loud ? 1005 : 1007) }
        bannerToken += 1
        let token = bannerToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            if self?.bannerToken == token { self?.banner = nil }
        }
    }

    func dismissBanner() { banner = nil }

    // MARK: Formatting

    static func format(_ seconds: TimeInterval) -> String {
        let negative = seconds < 0
        let total = Int(abs(seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let body = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        return negative ? "+" + body : body
    }
}
