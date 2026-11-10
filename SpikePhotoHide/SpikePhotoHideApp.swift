import SwiftUI

/// Spike test app — verify các giả định G1/G2/G3 trước khi build MVP.
/// Mỗi tab = 1 task trong Spike Plan (spec mục 11).
@main
struct SpikePhotoHideApp: App {
    @StateObject private var log = LogStore()
    @StateObject private var photos = PhotoLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(log)
                .environmentObject(photos)
        }
    }
}
