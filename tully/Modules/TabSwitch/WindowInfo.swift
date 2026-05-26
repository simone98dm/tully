// tully/Modules/TabSwitch/WindowInfo.swift
import AppKit
import CoreGraphics

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let appName: String
    let windowTitle: String
    let pid: pid_t
    var appIcon: NSImage?
    var thumbnail: NSImage?
}
