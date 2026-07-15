import Foundation

struct DroneRFProfile {
    let name: String
    let patterns: [String]
    let serviceUUIDs: [String]
    let manufacturerIDs: [UInt16]
}

enum DroneRFDatabase {
    /// Known BLE / Wi-Fi fingerprints for common consumer drones and RC gear.
    static let profiles: [DroneRFProfile] = [
        DroneRFProfile(
            name: "DJI",
            patterns: ["dji", "mavic", "phantom", "mini", "air", "avata", "fpv", "inspire", "matrice"],
            serviceUUIDs: ["FFF0", "FEE7"],
            manufacturerIDs: [0x0157, 0x004C]
        ),
        DroneRFProfile(
            name: "Parrot",
            patterns: ["parrot", "anafi", "bebop", "mambo"],
            serviceUUIDs: [],
            manufacturerIDs: []
        ),
        DroneRFProfile(
            name: "Skydio",
            patterns: ["skydio"],
            serviceUUIDs: [],
            manufacturerIDs: []
        ),
        DroneRFProfile(
            name: "Autel",
            patterns: ["autel", "evo"],
            serviceUUIDs: [],
            manufacturerIDs: []
        ),
        DroneRFProfile(
            name: "FPV / RC Controller",
            patterns: ["radiomaster", "tbs", "crossfire", "elrs", "betafpv", "iflight", "frsky", "flysky", "drone", "uav", "quad"],
            serviceUUIDs: ["FFE0", "FFE1"],
            manufacturerIDs: []
        ),
        DroneRFProfile(
            name: "Generic Wi-Fi Drone",
            patterns: ["wifi-uav", "uav-", "drone-", "quadcopter", "holy stone", "syma", "hubsan"],
            serviceUUIDs: [],
            manufacturerIDs: []
        )
    ]

    static func match(name: String?, serviceUUIDs: [String] = [], manufacturerID: UInt16? = nil) -> DroneRFProfile? {
        let normalizedName = (name ?? "").lowercased()
        let normalizedUUIDs = serviceUUIDs.map { $0.uppercased() }

        for profile in profiles {
            if profile.patterns.contains(where: { normalizedName.contains($0) }) {
                return profile
            }
            if profile.serviceUUIDs.contains(where: { uuid in normalizedUUIDs.contains(where: { $0.contains(uuid) }) }) {
                return profile
            }
            if let manufacturerID, profile.manufacturerIDs.contains(manufacturerID) {
                return profile
            }
        }
        return nil
    }

    static func matchWiFiSSID(_ ssid: String) -> DroneRFProfile? {
        match(name: ssid)
    }
}
