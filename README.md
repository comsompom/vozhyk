## Built for

OpenAI Build Week 2026

## Powered by

- OpenAI Codex
- GPT-5
- SwiftUI
- Core ML
- Vision Framework
- YOLOv8

Feedback ID: 019f6a59-5a57-74a2-98dd-8c77f5f37a1a

# DroneDetector — iOS App

iPhone app for the **Vozhyk** anti-drone project. Uses the rear camera for visual drone detection and the phone's Bluetooth/Wi-Fi radios to spot drone-like RF signatures.

## Features

- **Live camera feed** with bounding-box overlays
- **AI detection** via Core ML YOLOv8n (optional) + motion heuristics fallback
- **BLE 2.4 GHz scanner** for DJI, Parrot, FPV controllers, and similar devices
- **Wi-Fi SSID check** for known drone network names (when iOS allows)
- **On-screen threat HUD**: CLEAR / POSSIBLE DRONE / DRONE DETECTED

## Requirements

- Mac with **Xcode 15+**
- iPhone running **iOS 16+** (iPhone 12+ recommended for Neural Engine)
- Free Apple ID or paid Apple Developer account

## Open in Xcode

```bash
open iphone_detector/DroneDetector.xcodeproj
```

1. Select your **Team** under Signing & Capabilities (target → DroneDetector).
2. Connect your iPhone via USB.
3. Choose your iPhone as the run destination.
4. Press **Run** (⌘R).

On first launch, allow **Camera**, **Bluetooth**, and **Location** (location is required by iOS for Wi-Fi SSID access).

## Optional: Add YOLOv8n AI Model

The app works immediately with motion-based aerial object detection. For better accuracy, add a YOLO model.

**Important:** use a project venv. Global NumPy 2.x breaks Core ML export (`Numpy is not available` / `_ARRAY_API not found`).

```bash
cd iphone_detector
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements.txt
python scripts/download_model.py
```

Then in Xcode: if the model is not already listed under `DroneDetector/Models`, drag `DroneDetector/Models/YOLOv8n.mlpackage` into the project and ensure **Target Membership → DroneDetector** is checked. After a successful Run, the HUD should show **AI Model Ready** / `YOLOv8n Core ML`.

### Branding

- **App icon:** `logo.png` → `Assets.xcassets/AppIcon` (1024×1024)
- **Launch / splash:** `app_start.png` → `LaunchScreen.storyboard` + in-app `SplashView` (~1.2s)
- **Home screen name:** **Vozhyk**

YOLOv8n detects COCO classes including **airplane**, **bird**, and **kite** — useful proxies for drones until you train a custom drone-only model. The HUD labels these as possible aerial/drone detections.

## Radio Detection Notes

iOS does **not** expose raw spectrum analysis (433 MHz LoRa, 5.8 GHz FPV video, etc.). This app uses what the iPhone can access:

| Method | Band | What it detects |
|--------|------|-----------------|
| CoreBluetooth BLE scan | 2.4 GHz | Drone controllers, DJI BLE, FPV gear |
| Wi-Fi SSID check | 2.4 / 5 GHz | Connected or visible drone Wi-Fi names |

For full RF coverage (433 MHz RC, 5.8 GHz VTX), you still need external hardware on the rover (e.g. SX1278 LoRa module) as described in `solution.md`.

## Project Structure

```
iphone_detector/
├── DroneDetector.xcodeproj
├── DroneDetector/
│   ├── Camera/          # AVFoundation + Vision
│   ├── Radio/           # BLE + Wi-Fi RF scanner
│   ├── Views/           # SwiftUI overlays & HUD
│   └── Models/          # Core ML model (after download)
└── scripts/
    └── download_model.py
```

## Next Steps (Part 2)

This app is the **eyes & brain** on the iPhone. Part 2 will connect the iPhone app to a **DOIT ESP32 DEVKIT V1** over Wi-Fi instead of BLE.

The planned hardware concept is:

```text
iPhone Vozhyk app
  |
  | Wi-Fi command: scan / target position
  v
ESP32 DOIT DEVKIT V1
  |
  | Servo PWM
  v
iPhone pan/tilt platform
  |
  | Camera searches the sky
  v
Drone detected by iPhone app
  |
  | Wi-Fi command: detected drone coordinates
  v
ESP32
  |
  | Servo PWM
  v
Positioning ray module points toward the detected drone
```

The ESP32 will create or join a Wi-Fi network and expose a small control API. The iPhone app will send commands such as:

```text
POST /scan/start
POST /scan/stop
POST /iphone/position
POST /ray/target
```

When the iPhone detects a `plane_drone`, it will send normalized target coordinates to the ESP32:

```json
{
  "cx": 0.62,
  "cy": 0.31,
  "confidence": 0.84,
  "zoom": 3.0,
  "label": "plane_drone"
}
```

The ESP32 will convert those coordinates into servo movement. One servo system can slowly rotate the iPhone so the camera scans outside, and another servo system can point the dedicated positioning ray toward the detected drone location.

Important hardware notes:

- Use a separate 5V power supply for servos.
- Connect ESP32 GND and servo power GND together.
- Do not power servos directly from the ESP32 3.3V pin.
- Add smoothing/dead-zone logic so the ray does not shake when detections move slightly.
- Auto-zoom on the iPhone will reset while the platform is moving and can zoom in again when the platform becomes stable.
