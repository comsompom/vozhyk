## Built for

OpenAI Build Week 2026

## Powered by

- OpenAI Codex
- GPT-5
- SwiftUI
- Core ML
- Vision Framework
- YOLO-World

feedback id: 019f6a59-5a57-74a2-98dd-8c77f5f37a1a

<p align="center">
  <img src="../logo.png" alt="Vozhyk iOS logo" width="220">
</p>

# DroneDetector — iOS App

iPhone app for the **Vozhyk** anti-drone project. Uses the rear camera for visual drone detection and the phone's Bluetooth/Wi-Fi radios to spot drone-like RF signatures.

The app runs live on the iPhone and automatically analyzes the camera stream. It detects common visible objects such as autos, humans, trucks, buses, motorcycles, birds, and planes with the bundled YOLO model, while a separate custom Core ML model detects `plane_drone` objects from our own fine-tuned training data. This dual-model setup keeps normal object recognition available while improving detection of the drone/plane target class.

For long-distance objects, the camera uses automatic zoom assistance. When the user holds the iPhone stable for a short moment, the app gradually zooms the real camera feed up to 5x so small distant flying objects become easier for the model to inspect. If the phone moves or turns again, zoom resets back to the default view.

The app can also show an estimated distance for supported detected objects. This is controlled from Settings and applies only to `human`, `auto`, and `plane_drone` detections, using preset real-world sizes. When several supported objects are visible, the top-right distance badge shows the nearest estimated object. The estimate is adjusted using the camera's current real zoom factor, including automatic zoom ramps.

The app can optionally save object tracks for `auto`, `drone`, and `plane_drone` detections. Track logging is off by default and can be enabled per object in Settings. When enabled, Vozhyk combines the phone GPS coordinate, compass heading, camera field of view, current zoom, detected box offset, and visual distance estimate to save estimated object coordinates and movement history. Barometer pressure and relative altitude are saved as phone sensor context.

The app also performs radio-side checks that are available on iPhone. It scans Bluetooth Low Energy signals and checks Wi-Fi SSID patterns where iOS permits access, looking for known drone/controller signatures such as DJI, Parrot, FPV, and similar radio names. The visual and radio signals are combined into the on-screen threat state.

## Presentation Video

https://youtu.be/UbPek3CEMGw

## About Project

Read the full hackathon project description in [about.md](about.md).

## Features

- **Live camera feed** with bounding-box overlays
- **General object detection** for autos, humans, trucks, buses, motorcycles, birds, and planes
- **Fine-tuned plane-drone detection** using our custom Core ML model trained from reviewed video data
- **Dual-model pipeline**: custom `plane_drone` model plus preserved YOLO general detector
- **Automatic camera zoom** when the iPhone is stable, up to 5x for distant object inspection
- **Optional distance estimates** for humans, autos, and plane-drone targets, adjusted for current camera zoom
- **Optional object track logging** for autos, drones, and plane-drone targets with estimated coordinates and movement history
- **BLE 2.4 GHz scanner** for DJI, Parrot, FPV controllers, and similar known drone/controller signals
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

On first launch, allow **Camera**, **Bluetooth**, and **Location**. Location is used for object coordinate estimates and is also required by iOS for Wi-Fi SSID access.

## Object Track Logging

Track logging is disabled by default. Open **Settings → Tracks** to enable it separately for:

- `auto`
- `drone`
- `plane_drone`

The app saves logs as JSON-lines records in the app support directory and shows recent entries in the Tracks tab. Each record includes:

- recognized object type and confidence
- detection time and tracking/sensor snapshot time
- estimated object latitude/longitude
- phone latitude/longitude and GPS horizontal accuracy
- visual distance estimate
- compass heading and heading accuracy
- phone altitude when available
- barometer relative altitude and pressure when available
- movement from the previous matched point
- predicted next latitude/longitude from the last observed speed and bearing

The estimate is a ground-coordinate prediction based on phone GPS, compass, detected box position, camera field of view, zoom, and object distance. The iPhone barometer measures the phone's pressure altitude, not the target object's true altitude.

## Drone-aware model

The app works immediately with motion-based aerial object detection. For better accuracy, add a YOLO model.

**Important:** use a project venv. Global NumPy 2.x breaks Core ML export (`Numpy is not available` / `_ARRAY_API not found`).

```bash
cd iphone_detector
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements.txt
python scripts/download_model.py
```

The project uses `DroneDetector/Models/DroneDetector.mlpackage`, a YOLO-World model configured only for: Auto (car), Plane, Drone, Bird, Human, Bus, Truck, and Motorcycle. After a successful Run, the HUD should show **AI Model Ready** / `YOLO-World Core ML`.

### Branding

- **App icon:** `logo.png` → `Assets.xcassets/AppIcon` (1024×1024)
- **Launch / splash:** `app_start.png` → `LaunchScreen.storyboard` + in-app `SplashView` (~1.2s)
- **Home screen name:** **Vozhyk**

YOLO-World supports a real `drone` prompt without treating kites as drones. The model is intentionally restricted to the app's existing object list, and the app requires three spatially consistent model detections before it displays an alert.

To make a real detector, collect and label images with these classes: `drone`, `bird`, `aircraft`, and `kite`. Include clouds, branches, glare, insects, and moving-camera scenes as unlabelled hard negatives. Keep each video/flight recording entirely within one of train, validation, or test splits.

```bash
cd iphone_detector
source .venv/bin/activate
cp datasets/drone.yaml.example datasets/drone.yaml
# Edit the dataset path in datasets/drone.yaml
python scripts/train_drone_model.py --data datasets/drone.yaml --device mps
```

The script exports `DroneDetector/Models/DroneDetector.mlpackage`. Drag it into the Xcode target. The app automatically prefers this custom model over the bundled COCO model.

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

This app is the **eyes & brain** on the iPhone. The next integration step is sending targeting coordinates to a **DOIT ESP32 DEVKIT V1** over Wi-Fi.

The planned hardware extension is to mount the iPhone on a mobile system, use the camera model to detect a drone in the air, then send the detected target position, confidence, and zoom level over Wi-Fi to the ESP32. The ESP32 will control servos that rotate the iPhone scanning platform and point a dedicated positioning ray toward the detected drone location.
