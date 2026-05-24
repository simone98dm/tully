// tully/ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("System", systemImage: "cpu") {
                SystemMonitorView()
            }
            Tab("Disk", systemImage: "internaldrive") {
                DiskUtilityView()
            }
            Tab("Windows", systemImage: "rectangle.3.group") {
                WindowManagerView()
            }
        }
        .frame(width: 340, height: 480)
    }
}
