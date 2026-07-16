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

This app is the **eyes & brain** on the iPhone. The next integration step is sending targeting coordinates to the STM32 rover over **Bluetooth BLE** (`T:-120,45\n` format from `solution.md`).
