import SwiftUI
import MotiSig

@main
struct motisig_ios_exampleApp: App {
    @State private var viewModel = NotificationsViewModel()

    init() {
        let env = ProcessInfo.processInfo.environment
        let sdkKey = env["MOTISIG_SDK_KEY"].flatMap { $0.isEmpty ? nil : $0 } ?? "demo_key"
        let projectId = env["MOTISIG_PROJECT_ID"].flatMap { $0.isEmpty ? nil : $0 } ?? "sdk-example"
        let baseURLEnv = env["MOTISIG_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let baseURLNote = baseURLEnv.isEmpty ? "default (SDK)" : baseURLEnv
        print(
            "[MotiSigExample] MotiSig config sdkKey=\(sdkKey) projectId=\(projectId) baseURL=\(baseURLNote) logLevel=debug userId=demo-user-ios"
        )
        MotiSig.initialize(sdkKey: sdkKey, projectId: projectId, logLevel: .debug)
        MotiSig.shared.setUser(id: "demo-user-ios")
    }

    var body: some Scene {
        WindowGroup {
            NotificationListView(viewModel: viewModel)
                .onAppear { viewModel.start() }
        }
    }
}
