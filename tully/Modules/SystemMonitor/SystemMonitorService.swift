// tully/Modules/SystemMonitor/SystemMonitorService.swift
import Foundation

@Observable
final class SystemMonitorService {
    var snapshot = SystemSnapshot()
    private var samplerTask: Task<Void, Never>?

    func start() {
        guard samplerTask == nil else { return }
        samplerTask = Task.detached(priority: .utility) { [weak self] in
            var sampler = SystemSampler()
            while !Task.isCancelled {
                let snap = sampler.sample()
                await MainActor.run { self?.snapshot = snap }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        samplerTask?.cancel()
        samplerTask = nil
    }
}
