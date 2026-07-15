import Combine
import CoreBluetooth
import Foundation
import Network
import SystemConfiguration.CaptiveNetwork

@MainActor
final class RadioScanner: NSObject, ObservableObject {
    @Published private(set) var signals: [RadioSignal] = []
    @Published private(set) var isScanning = false
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var statusMessage = "Radio scanner idle"

    private var centralManager: CBCentralManager?
    private var scanTimer: Timer?
    private var wifiTimer: Timer?
    private var discoveredDevices: [String: RadioSignal] = [:]
    private let bleQueue = DispatchQueue(label: "com.vozhyk.drone-detector.ble")

    override init() {
        super.init()
    }

    func start() {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = "Scanning BLE 2.4 GHz band..."
        centralManager = CBCentralManager(delegate: self, queue: bleQueue)

        scanTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.purgeStaleSignals()
            }
        }

        wifiTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanWiFiEnvironment()
            }
        }

        scanWiFiEnvironment()
    }

    func stop() {
        isScanning = false
        centralManager?.stopScan()
        scanTimer?.invalidate()
        wifiTimer?.invalidate()
        scanTimer = nil
        wifiTimer = nil
        statusMessage = "Radio scanner stopped"
    }

    private func purgeStaleSignals() {
        let cutoff = Date().addingTimeInterval(-8)
        discoveredDevices = discoveredDevices.filter { $0.value.lastSeen > cutoff }
        signals = discoveredDevices.values.sorted { $0.rssi > $1.rssi }
    }

    private func scanWiFiEnvironment() {
        guard isScanning else { return }

        if let interfaces = CNCopySupportedInterfaces() as? [String] {
            for interface in interfaces {
                guard
                    let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: AnyObject],
                    let ssid = info[kCNNetworkInfoKeySSID as String] as? String
                else { continue }

                if let profile = DroneRFDatabase.matchWiFiSSID(ssid) {
                    let signal = RadioSignal(
                        id: "wifi-\(ssid)",
                        name: ssid,
                        rssi: -55,
                        band: .wifi,
                        matchedProfile: profile.name,
                        lastSeen: Date()
                    )
                    discoveredDevices[signal.id] = signal
                }
            }
        }

        signals = discoveredDevices.values.sorted { $0.rssi > $1.rssi }
        if signals.isEmpty {
            statusMessage = "BLE scan active — no drone RF signatures yet"
        } else {
            statusMessage = "Drone-like RF: \(signals.count) signal(s)"
        }
    }

    private func handleDiscoveredPeripheral(
        peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown BLE Device"

        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map { $0.uuidString } ?? []

        var manufacturerID: UInt16?
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           manufacturerData.count >= 2 {
            manufacturerID = manufacturerData.withUnsafeBytes { ptr in
                ptr.load(as: UInt16.self)
            }
        }

        guard let profile = DroneRFDatabase.match(
            name: name,
            serviceUUIDs: serviceUUIDs,
            manufacturerID: manufacturerID
        ) else { return }

        let signal = RadioSignal(
            id: peripheral.identifier.uuidString,
            name: name,
            rssi: rssi.intValue,
            band: .ble,
            matchedProfile: profile.name,
            lastSeen: Date()
        )

        discoveredDevices[signal.id] = signal
        signals = discoveredDevices.values.sorted { $0.rssi > $1.rssi }
        statusMessage = "Drone-like RF detected: \(profile.name)"
    }
}

extension RadioScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            bluetoothState = central.state
            switch central.state {
            case .poweredOn:
                statusMessage = "BLE 2.4 GHz scan running..."
                central.scanForPeripherals(
                    withServices: nil,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
                )
            case .poweredOff:
                statusMessage = "Bluetooth is off — enable in Settings"
            case .unauthorized:
                statusMessage = "Bluetooth permission required"
            case .unsupported:
                statusMessage = "BLE not supported on this device"
            default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            handleDiscoveredPeripheral(
                peripheral: peripheral,
                advertisementData: advertisementData,
                rssi: RSSI
            )
        }
    }
}
