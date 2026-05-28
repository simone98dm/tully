// tully/Shared/AppSettings.swift
import Foundation

@Observable
final class AppSettings {
    var showCPU: Bool = UserDefaults.standard.bool(forKey: "tully.showCPU") {
        didSet { UserDefaults.standard.set(showCPU, forKey: "tully.showCPU") }
    }
    var showRAM: Bool = UserDefaults.standard.bool(forKey: "tully.showRAM") {
        didSet { UserDefaults.standard.set(showRAM, forKey: "tully.showRAM") }
    }
    var showNet: Bool = UserDefaults.standard.bool(forKey: "tully.showNet") {
        didSet { UserDefaults.standard.set(showNet, forKey: "tully.showNet") }
    }

    func resetAll() {
        showCPU = false
        showRAM = false
        showNet = false
        ["tully.showCPU", "tully.showRAM", "tully.showNet"].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }
}
