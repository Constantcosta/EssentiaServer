//
//  ServerManagerApp.swift
//  Mac Studio Server Manager
//
//  Created on 29/10/2025.
//

import SwiftUI

@main
struct ServerManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var serverManager = MacStudioServerManager()
    
    var body: some Scene {
        WindowGroup {
            ServerManagementView(manager: serverManager)
                .environmentObject(serverManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Server Manager") {
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
                Button("Start Server") {
                    Task {
                        await serverManager.startServer()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(serverManager.isServerRunning)
                
                Button("Stop Server") {
                    Task {
                        await serverManager.stopServer()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!serverManager.isServerRunning)
                
                Divider()
                
                Button("Refresh Stats") {
                    Task {
                        await serverManager.fetchServerStats()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!serverManager.isServerRunning)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure window appearance
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
