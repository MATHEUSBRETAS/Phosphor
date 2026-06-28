import Foundation

final class LinearNode {
    let name: String
    var children: [LinearNode] = []
    var files = 0
    init(_ name: String) { self.name = name }
}

final class IndexedNode {
    let name: String
    var children: [IndexedNode] = []
    private var childrenByName: [String: IndexedNode] = [:]
    var files = 0
    init(_ name: String) { self.name = name }
    func child(named name: String) -> IndexedNode? { childrenByName[name] }
    func addChild(_ child: IndexedNode) {
        children.append(child)
        childrenByName[child.name] = child
    }
}

struct SyntheticDevice {
    let udid: String
    let connectionType: String
    let name: String
    let battery: Int
    let paired: Bool
}

final class SyntheticDevicePoller {
    private var deviceInfoCache: [String: (device: SyntheticDevice, fetchedAt: Date)] = [:]
    private let cacheInterval: TimeInterval
    private(set) var detailFetches = 0

    init(cacheInterval: TimeInterval) {
        self.cacheInterval = cacheInterval
    }

    func scan(entries: [(udid: String, connectionType: String)], forceRefresh: Bool = false) -> [SyntheticDevice] {
        if entries.isEmpty {
            deviceInfoCache.removeAll()
            return []
        }
        let visible = Set(entries.map(\.udid))
        deviceInfoCache = deviceInfoCache.filter { visible.contains($0.key) }
        return entries.map { entry in
            if !forceRefresh,
               let cached = deviceInfoCache[entry.udid],
               Date().timeIntervalSince(cached.fetchedAt) < cacheInterval {
                var device = cached.device
                device = SyntheticDevice(
                    udid: device.udid,
                    connectionType: entry.connectionType,
                    name: device.name,
                    battery: device.battery,
                    paired: device.paired
                )
                return device
            }
            detailFetches += 1
            let device = SyntheticDevice(
                udid: entry.udid,
                connectionType: entry.connectionType,
                name: "Device \(entry.udid.suffix(4))",
                battery: 80,
                paired: true
            )
            deviceInfoCache[entry.udid] = (device, Date())
            return device
        }
    }
}

let entries = (0..<120_000).map { i in
    "AppDomain-com.example.\(i % 500)/Library/Caches/folder\(i % 1_000)/file\(i).dat"
}

@discardableResult
func elapsed(_ label: String, _ body: () -> Void) -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    body()
    let end = DispatchTime.now().uptimeNanoseconds
    let sec = Double(end - start) / 1_000_000_000
    print("\(label): \(String(format: "%.4f", sec))s")
    return sec
}

let linear = elapsed("linear child lookup") {
    let root = LinearNode("/")
    for path in entries {
        let parts = path.split(separator: "/").map(String.init)
        var current = root
        for (idx, part) in parts.enumerated() {
            if idx == parts.count - 1 {
                current.files += 1
            } else if let existing = current.children.first(where: { $0.name == part }) {
                current = existing
            } else {
                let child = LinearNode(part)
                current.children.append(child)
                current = child
            }
        }
    }
}

let indexed = elapsed("indexed child lookup") {
    let root = IndexedNode("/")
    for path in entries {
        let parts = path.split(separator: "/").map(String.init)
        var current = root
        for (idx, part) in parts.enumerated() {
            if idx == parts.count - 1 {
                current.files += 1
            } else if let existing = current.child(named: part) {
                current = existing
            } else {
                let child = IndexedNode(part)
                current.addChild(child)
                current = child
            }
        }
    }
}

print("tree speedup: \(String(format: "%.2fx", linear / indexed))")

if indexed >= linear {
    fputs("ERROR: indexed lookup should be faster than linear lookup\n", stderr)
    exit(1)
}

let pollEntries = (0..<6).map { (udid: "00008030-DEVICE-\($0)", connectionType: $0 == 0 ? "USB" : "Network") }
let uncachedPollTime = elapsed("uncached device detail polling") {
    let poller = SyntheticDevicePoller(cacheInterval: 0)
    for _ in 0..<1_000 {
        _ = poller.scan(entries: pollEntries)
    }
}
let cachedPoller = SyntheticDevicePoller(cacheInterval: 60)
let cachedPollTime = elapsed("cached device detail polling") {
    for _ in 0..<1_000 {
        _ = cachedPoller.scan(entries: pollEntries)
    }
}
print("cached detail fetches: \(cachedPoller.detailFetches)")
print("polling speedup: \(String(format: "%.2fx", uncachedPollTime / max(cachedPollTime, 0.000_001)))")

if cachedPoller.detailFetches != pollEntries.count {
    fputs("ERROR: cached poller should fetch details once per visible device\n", stderr)
    exit(1)
}
