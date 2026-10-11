import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if os(iOS)
import os
#endif

/// What this device can reasonably run, measured at runtime rather than
/// looked up from a device-model table.
struct DeviceCapabilities: Sendable {
    enum Platform: String, Sendable {
        case iPhone, iPad, mac, visionPro, other
    }

    let platform: Platform
    let physicalMemoryBytes: UInt64
    /// Memory the OS currently lets this process grow into (iOS only).
    let appMemoryBudgetBytes: UInt64?
    let isAppleSilicon: Bool
    let processorCount: Int

    /// Physical memory rounded to the marketed figure (devices report a
    /// little under, e.g. 7.5 GB for an 8 GB iPhone).
    var memoryGB: Int {
        Int((Double(physicalMemoryBytes) / 1_073_741_824).rounded())
    }

    var platformName: String {
        switch platform {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .mac: "Mac"
        case .visionPro: "Apple Vision Pro"
        case .other: "this device"
        }
    }

    @MainActor
    static func current() -> DeviceCapabilities {
        let info = ProcessInfo.processInfo

        var platform: Platform = .other
        #if os(macOS)
        platform = .mac
        #elseif os(visionOS)
        platform = .visionPro
        #elseif canImport(UIKit)
        if info.isiOSAppOnMac {
            platform = .mac
        } else {
            switch UIDevice.current.userInterfaceIdiom {
            case .phone: platform = .iPhone
            case .pad: platform = .iPad
            case .mac: platform = .mac
            case .vision: platform = .visionPro
            default: platform = .other
            }
        }
        #endif

        var budget: UInt64?
        #if os(iOS)
        let available = os_proc_available_memory()
        if available > 0 { budget = UInt64(available) }
        #endif

        #if arch(arm64)
        let appleSilicon = true
        #else
        let appleSilicon = false
        #endif

        return DeviceCapabilities(
            platform: platform,
            physicalMemoryBytes: info.physicalMemory,
            appMemoryBudgetBytes: budget,
            isAppleSilicon: appleSilicon,
            processorCount: info.activeProcessorCount
        )
    }

    // MARK: Recommendations

    enum Fit: Int, Comparable, Sendable {
        case notRecommended = 0
        case mayBeSlow = 1
        case recommended = 2

        static func < (lhs: Fit, rhs: Fit) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .recommended: "Recommended"
            case .mayBeSlow: "May be slow"
            case .notRecommended: "Not recommended"
            }
        }
    }

    /// A recommendation, not a guarantee: based on physical memory versus
    /// the model's recommended minimum, and on the file actually fitting
    /// in what the OS will give the app.
    func fit(for model: LocalModelDescriptor) -> Fit {
        guard isAppleSilicon else { return .notRecommended }
        let fileGB = Double(model.sizeBytes) / 1_073_741_824
        // Weights plus KV cache/runtime overhead need roughly 1.3x the file.
        let neededGB = fileGB * 1.3
        if let budget = appMemoryBudgetBytes {
            let budgetGB = Double(budget) / 1_073_741_824
            if neededGB > budgetGB { return memoryGB >= model.minimumMemoryGB ? .mayBeSlow : .notRecommended }
        }
        if memoryGB >= model.minimumMemoryGB { return .recommended }
        if memoryGB >= model.minimumMemoryGB - 2, neededGB < Double(memoryGB) * 0.5 { return .mayBeSlow }
        return .notRecommended
    }

    /// The most capable recommended model: the one to suggest first.
    func bestModel(in catalog: [LocalModelDescriptor]) -> LocalModelDescriptor? {
        catalog
            .filter { fit(for: $0) == .recommended }
            .max { $0.sizeBytes < $1.sizeBytes }
    }
}
