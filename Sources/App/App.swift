import SwiftUI

@main
struct ALogApp: App {
    @UIApplicationDelegateAdaptor var delegate: AppDelegate
    
    let container = DataContainer.shared
    let appState = AppState.shared
    let conn = Connectivity.shared
    
    @StateObject var config = Config.shared
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .tint(JournalTheme.accent)
                .environmentObject(container)
                .environmentObject(appState)
                .environmentObject(config)
                .environmentObject(conn)
                .environment(\.managedObjectContext, container.context)
                .preferredColorScheme(config.darkMode == .auto ? nil : config.darkMode == .dark ? .dark : .light)
                .task(id: [config.transProvider.rawValue, config.transLang.rawValue,
                           config.localTranscriptionModel.rawValue]) {
                    await Transcription.shared.prepareSelectedModel()
                }
                .onOpenURL { url in
                    appState.openURL(url)
                }
        }
    }
}
