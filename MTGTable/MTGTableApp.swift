import SwiftUI

@main
struct MTGTableApp: App {
    @StateObject private var app = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        // Testing only: `-forceLandscape` lays the app out sideways so landscape can be checked
        // in a simulator window that can't be rotated from here.
        if ProcessInfo.processInfo.arguments.contains("-forceLandscape") {
            GeometryReader { geo in
                content
                    .frame(width: geo.size.height, height: geo.size.width)
                    .rotationEffect(.degrees(90))
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        ZStack {
            if let game = app.game {
                TableView(game: game)
            } else {
                SetupView()
            }
            if let c = app.celebration {
                CelebrationView(info: c) { app.celebration = nil }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: app.celebration?.id)
    }
}
