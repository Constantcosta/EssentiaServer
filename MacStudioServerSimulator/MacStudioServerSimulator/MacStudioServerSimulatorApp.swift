//
//  MacStudioServerSimulatorApp.swift
//  MacStudioServerSimulator
//
//  iOS/iPadOS Simulator for Mac Studio Audio Analysis Server
//

import SwiftUI

@main
struct MacStudioServerSimulatorApp: App {
    @StateObject private var serverManager = MacStudioServerManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverManager)
        }
    }
}
