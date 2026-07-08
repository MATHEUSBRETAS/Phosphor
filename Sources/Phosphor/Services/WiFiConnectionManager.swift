import Foundation

/// Manages Wi-Fi device connections.
/// Primary: pymobiledevice3 usbmux. Fallback: libimobiledevice network mode.
@MainActor
final class WiFiConnectionManager: ObservableObject {

    @Published var wifiDevices: [WiFiDevice] = []
    @Published var isScanning = false
    @Published var lastError: String?

    struct WiFiDevice: Identifiable, Hashable {
        let id: String // UDID
        let name: String
        let networkAddress: String
        let isReachable: Bool
    }

    /// Enable Wi-Fi sync on a USB-connected device.
    func enableWiFiSync(udid: String) async -> Bool {
        lastError = nil

        // Primary: pymobiledevice3 maps to Finder's "Show this iPhone when on Wi-Fi" toggle.
        let result = await PyMobileDevice.setWiFiConnections(udid: udid, enabled: true)
        if result.succeeded { return true }

        // Pairing can surface the Trust flow, but it is not a substitute for enabling Wi-Fi.
        if await PyMobileDevice.pair(udid: udid) {
            let retry = await PyMobileDevice.setWiFiConnections(udid: udid, enabled: true)
            if retry.succeeded { return true }
            lastError = retry.stderr.nilIfEmpty ?? retry.output.nilIfEmpty
            return false
        }

        lastError = result.stderr.nilIfEmpty
            ?? result.output.nilIfEmpty
            ?? "Connect the device over USB, unlock it, tap Trust, then try enabling Wi-Fi again."
        return false
    }

    /// Scan for devices available over the network.
    func scanForWiFiDevices() async {
        isScanning = true
        lastError = nil

        // Primary: pymobiledevice3 network listing
        let pyUdids = await PyMobileDevice.listNetworkDevices()
        if !pyUdids.isEmpty {
            var devices: [WiFiDevice] = []
            for udid in pyUdids {
                let name = await PyMobileDevice.deviceName(udid: udid) ?? "Device \(udid.prefix(8))"
                devices.append(WiFiDevice(id: udid, name: name, networkAddress: "", isReachable: true))
            }
            wifiDevices = devices
            isScanning = false
            return
        }

        // Fallback: libimobiledevice idevice_id -n
        let result = await Shell.runAsync("idevice_id", arguments: ["-n"])
        guard result.succeeded else {
            lastError = result.stderr.nilIfEmpty
            wifiDevices = []
            isScanning = false
            return
        }

        let udids = result.output.components(separatedBy: "\n").filter { !$0.isEmpty }
        var devices: [WiFiDevice] = []

        for udid in udids {
            let infoResult = await Shell.runAsync("ideviceinfo", arguments: ["-u", udid, "-n"])
            let name: String
            let address: String

            if infoResult.succeeded {
                let info = infoResult.output.parseKeyValuePairs()
                name = info["DeviceName"] ?? "Unknown"
                address = info["WiFiAddress"] ?? ""
            } else {
                name = "Device \(udid.prefix(8))"
                address = ""
            }

            devices.append(WiFiDevice(id: udid, name: name, networkAddress: address, isReachable: infoResult.succeeded))
        }

        wifiDevices = devices
        isScanning = false
    }

    /// Check if a specific device is reachable over Wi-Fi.
    func isDeviceReachable(udid: String) async -> Bool {
        // Try pymobiledevice3 first
        let name = await PyMobileDevice.deviceName(udid: udid)
        if name != nil { return true }
        // Fallback
        let result = await Shell.runAsync("ideviceinfo", arguments: ["-u", udid, "-n", "-k", "DeviceName"], timeout: 5)
        return result.succeeded
    }
}
