import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var blockStore: BlockStore
    @EnvironmentObject private var workspaceManager: WorkspaceManager
    @EnvironmentObject private var settingsOpenCoordinator: SettingsOpenCoordinator
    @Environment(\.openSettings) private var openSettings

    private var showTabBar: Bool {
        workspaceManager.tabs.count > 1
    }

    private var themeBackgroundColor: NSColor {
        NSColor(settingsStore.activeTheme.swiftUIColor(from: settingsStore.activeTheme.background))
    }

    var body: some View {
        if #available(macOS 15.0, *) {
            baseContent
                .toolbar(removing: .sidebarToggle)
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            baseContent
                .toolbar(removing: .sidebarToggle)
        }
    }

    private var baseContent: some View {
        TerminalWorkspaceView(manager: workspaceManager)
            .background {
                WindowConfigurator(
                    backgroundColor: themeBackgroundColor,
                    isDark: settingsStore.activeTheme.isDarkBackground
                )
            }
            .background {
                Color.clear
                    .frame(width: 0, height: 0)
                    .onAppear {
                        settingsOpenCoordinator.setAction {
                            openSettings()
                        }
                    }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showTabBar {
                    TitleBarTabStrip(manager: workspaceManager, isDarkBackground: settingsStore.activeTheme.isDarkBackground, onNewTab: addTab)
                        .padding(.vertical, 4)
                }
            }
    }

    private func addTab() {
        workspaceManager.newTab(
            shellPath: settingsStore.settings.shellPath,
            workingDirectory: settingsStore.settings.defaultWorkingDirectory,
            blockStore: blockStore
        )
    }
}

// MARK: - Window Configurator

private struct WindowConfigurator: NSViewRepresentable {
    let backgroundColor: NSColor
    let isDark: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            self.configureWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        configureWindow(window)
    }

    private func configureWindow(_ window: NSWindow) {
        // Match the window appearance to the theme so system chrome and traffic lights
        // adopt the correct contrast while SwiftUI owns the toolbar background.
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = backgroundColor
    }
}

#Preview {
    MainWindowView()
        .environmentObject(SettingsStore())
        .environmentObject(BlockStore())
        .environmentObject(WorkspaceManager())
        .environmentObject(SettingsOpenCoordinator())
}
