import SwiftUI

@main
struct OryClientExampleApp: App {

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: RootViewModel(client: AppComponents.oryClient))
                #if DEBUG
                .developerOverlay(store: AppComponents.networkHistory)
                #endif
        }
    }
}
