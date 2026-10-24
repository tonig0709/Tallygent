import AppKit
import SwiftUI

@main
enum CodexQuotaMain {
    static func main() {
        if let status = ClaudeStatuslineBridge.runIfRequested() { exit(status) }
        CodexQuotaApp.main()
    }
}

struct CodexQuotaApp: App {
    @StateObject private var server = QuotaMonitor()

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
        server.snapshot.menuSummary()
    }
}

private struct CodexQuotaMenuBarContent: View {
    @ObservedObject var server: QuotaMonitor
    let menuSummary: String

    var body: some View {
        if AppInstallation.requiresInstalledCopy {
            Text("请从“应用程序”启动")
            Button("打开“应用程序”文件夹") { AppInstallation.revealApplicationsFolder() }
        } else {
            Picker("监测服务", selection: Binding(get: { server.service }, set: server.selectService)) {
                ForEach(AgentService.allCases) { Text($0.title).tag($0) }
            }
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
