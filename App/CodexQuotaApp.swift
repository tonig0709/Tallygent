import AppKit
import SwiftUI

@main
struct CodexQuotaApp: App {
    @StateObject private var server = CodexAppServer()

    init() {
        WidgetRepairService.repair()
    }

    var body: some Scene {
        WindowGroup {
            if WidgetRepairService.requiresInstalledCopy {
                InstallLocationView()
            } else {
                DashboardView(server: server)
            }
        }
        .windowResizability(.contentSize)

        Window("Codex Quota 桌面玻璃面板", id: DesktopGlassPanelView.windowID) {
            DesktopGlassPanelView(server: server)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra("Codex Quota", image: "CodexMark") {
            CodexQuotaMenuBarContent(server: server, menuSummary: menuSummary)
        }
    }

    private var menuSummary: String {
        guard let value = server.snapshot.weekly?.remainingPercent else { return "等待额度数据" }
        return "周额度剩余 \(value)%"
    }
}

private struct CodexQuotaMenuBarContent: View {
    @ObservedObject var server: CodexAppServer
    let menuSummary: String
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        if WidgetRepairService.requiresInstalledCopy {
            Text("请从“应用程序”启动")
            Button("打开“应用程序”文件夹") { WidgetRepairService.revealApplicationsFolder() }
        } else {
            Text(menuSummary)
            Divider()
            Button("立即刷新") { server.refresh() }
            Button("修复桌面小组件") { WidgetRepairService.repair() }
            Button("打开桌面玻璃面板") {
                openWindow(id: DesktopGlassPanelView.windowID)
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("关闭桌面玻璃面板") {
                dismissWindow(id: DesktopGlassPanelView.windowID)
            }
        }
        Divider()
        Button("退出") { NSApp.terminate(nil) }
    }
}
