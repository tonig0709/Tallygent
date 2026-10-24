import SwiftUI

struct InstallLocationView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.blue)
            Text("请从“应用程序”启动")
                .font(.title2.weight(.semibold))
            Text("Tallygent 正在从下载文件或磁盘映像的临时副本运行。请将 App 拖到“应用程序”，再从那里打开，以免临时副本与已安装版本同时连接账户。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("打开“应用程序”文件夹") {
                    AppInstallation.revealApplicationsFolder()
                }
                .buttonStyle(.borderedProminent)
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(32)
        .frame(width: 460)
    }
}
