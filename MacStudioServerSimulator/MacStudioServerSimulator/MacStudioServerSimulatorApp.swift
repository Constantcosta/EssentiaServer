//
//  MacStudioServerSimulatorApp.swift
//  MacStudioServerSimulator
//
//  macOS management app for the local audio-analysis server
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct MacStudioServerSimulatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var serverManager = MacStudioServerManager()
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    
    var body: some Scene {
        WindowGroup {
            ServerManagementView()
                .environmentObject(serverManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Mac Studio Server Manager") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Mac Studio Server Manager",
                            .applicationVersion: "1.0.0",
                            .version: "Build 1"
                        ]
                    )
                }
            }
            
            CommandGroup(after: .newItem) {
#if os(macOS)
                Button("Show Server Log") {
                    openWindow(id: "server-log")
                }
                .keyboardShortcut("l", modifiers: [.command])
#endif
                Button("Start Server") {
                    Task {
                        await serverManager.startServer()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(serverManager.isServerRunning || serverManager.isLoading)
                
                Button("Stop Server") {
                    Task {
                        await serverManager.stopServer()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!serverManager.isServerRunning || serverManager.isLoading)
                
                Divider()
                
                Button("Refresh Stats") {
                    Task {
                        await serverManager.fetchServerStats()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!serverManager.isServerRunning || serverManager.isLoading)
            }
        }
        
#if os(macOS)
        WindowGroup("Server Log", id: "server-log") {
            ServerLogView()
                .frame(minWidth: 700, minHeight: 400)
        }
        .windowResizability(.contentSize)
#endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
