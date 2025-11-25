#if os(macOS)
import SwiftUI
import AppKit

struct ServerLogView: View {
    @State private var logText: String = "Loading log…"
    private let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    
    private var logURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Music")
            .appendingPathComponent("AudioAnalysisCache")
            .appendingPathComponent("server.log")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analyzer Server Log")
                        .font(.headline)
                    Text(logURL.path)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([logURL])
                }
                .disabled(!FileManager.default.fileExists(atPath: logURL.path))
            }
            .padding()
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("log-bottom")
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: logText) { _, _ in
                    DispatchQueue.main.async {
                        proxy.scrollTo("log-bottom", anchor: .bottom)
                    }
                }
            }
        }
        .onAppear(perform: loadLog)
        .onReceive(timer) { _ in loadLog() }
        .frame(minWidth: 700, minHeight: 400)
    }
    
    private func loadLog() {
        guard let data = try? String(contentsOf: logURL) else {
            logText = "Log file not found at \(logURL.path)"
            return
        }
        let lines = data.split(whereSeparator: \.isNewline)
        let tail = lines.suffix(600)
        logText = tail.joined(separator: "\n")
        if logText.isEmpty {
            logText = "(Log is currently empty)"
        }
    }
}
#endif
