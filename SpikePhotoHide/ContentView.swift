import SwiftUI
import Photos
import UIKit

struct ContentView: View {
    @EnvironmentObject var photos: PhotoLibrary
    @EnvironmentObject var log: LogStore

    var body: some View {
        TabView {
            HiddenTestView()
                .tabItem { Label("S1 Hidden", systemImage: "eye.slash") }
            DeleteTestView()
                .tabItem { Label("S2 Delete", systemImage: "trash") }
            BenchmarkView()
                .tabItem { Label("S3 Model", systemImage: "cpu") }
            RestoreTestView()
                .tabItem { Label("S4 Restore", systemImage: "arrow.uturn.backward") }
            LogView()
                .tabItem { Label("Log", systemImage: "doc.text") }
        }
        .task {
            if photos.status == .notDetermined {
                await photos.requestAccess()
            }
            log.info("Photo status: \(photos.statusLabel)")
            if photos.status == .limited {
                log.info("⚠️ Đang LIMITED access — S1 cần kiểm tra isHidden có writable trên ảnh ngoài selection không")
            }
        }
    }
}

struct LogView: View {
    @EnvironmentObject var log: LogStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(log.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Test Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button("Copy") {
                            UIPasteboard.general.string = log.reportText
                        }
                        Button("Clear") { log.clear() }
                    }
                }
            }
        }
    }
}
