import AppKit
import SwiftUI

@main
struct CodexQuotaApp: App {
    @StateObject private var server = CodexAppServer()

    var body: some Scene {
        WindowGroup {
            if AppInstallation.requiresInstalledCopy {
                InstallLocationView()
            } else {
                DashboardView(server: server)
            }
        }
        .windowResizability(.contentSize)

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

    var body: some View {
        if AppInstallation.requiresInstalledCopy {
            Text("请从“应用程序”启动")
            Button("打开“应用程序”文件夹") { AppInstallation.revealApplicationsFolder() }
        } else {
            Text(menuSummary)
            Divider()
            Button("立即刷新") { server.refresh() }
            Button("打开桌面玻璃面板") {
                DesktopPanelController.shared.show(server: server)
            }
            Button("关闭桌面玻璃面板") {
                DesktopPanelController.shared.close()
            }
        }
        Divider()
        Button("退出") { NSApp.terminate(nil) }
    }
}
