// tully/tullyApp.swift
import SwiftUI

@main
struct MyMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { }
    }
}
