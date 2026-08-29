import SwiftUI

@main
struct MirraApp: App {
    @StateObject private var mirrorController = MirrorController()

    var body: some Scene {
        WindowGroup("Mirra") {
            ContentView()
                .environmentObject(mirrorController)
                .onAppear {
                    mirrorController.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 430, height: 930)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("顯示") {
                Button(mirrorController.presentationMode ? "離開簡報模式" : "進入簡報模式") {
                    mirrorController.presentationMode.toggle()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}
