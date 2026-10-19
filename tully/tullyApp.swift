// tully/tullyApp.swift
import SwiftUI

@main
struct TullyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { }
    }
}
