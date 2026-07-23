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
- **Vertical and horizontal screen support** with camera preview, detection boxes, and controls adjusted for phone rotation
- **AI detection** via a dual Core ML pipeline: fine-tuned `plane_drone` model plus preserved YOLOv8n general detector
- **Automatic camera zoom** when the iPhone is stable, up to 5x for distant object inspection
- **Optional distance estimates** for humans, autos, and plane-drone targets, adjusted for current camera zoom
- **Optional object track logging** for autos, drones, and plane-drone targets using GPS, compass, barometer context, and visual distance estimates
- **ESP32 robot-station target transfer** for test detections after the iPhone is connected to the robot Wi-Fi
- **BLE 2.4 GHz scanner** for DJI, Parrot, FPV controllers, and similar devices
- **Wi-Fi SSID check** for known drone network names (when iOS allows)
- **On-screen threat HUD**: CLEAR / POSSIBLE DRONE / DRONE DETECTED

## Requirements

- Mac with **Xcode 15+**
- iPhone running **iOS 16+** (iPhone 12+ recommended for Neural Engine)
- Free Apple ID or paid Apple Developer account
- Visual Studio Code with the **PlatformIO** extension for ESP32 robot-station firmware

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

Track logging is disabled by default. In **Settings → Tracks**, logging can be enabled separately for:

- `auto`
- `drone`
- `plane_drone`

When enabled, the app stores JSON-lines records containing the recognized object, detection time, tracking/sensor time, estimated object coordinates, phone GPS coordinates, compass heading, distance estimate, barometer context, movement from the previous point, and a simple predicted next coordinate.

The coordinate estimate is calculated from the phone GPS location, compass heading, detected box offset, camera field of view, current zoom, and visual distance estimate. This is a ground-coordinate estimate. The iPhone barometer records phone pressure-altitude context; it does not provide the target object's true altitude.

## Screen Orientation

The app supports both vertical and horizontal iPhone placement. When the phone is rotated onto its side for a wider sky view, the camera preview and video output rotate together, so Vision receives frames in the same orientation shown on screen. Detection boxes, HUD controls, the ESP32 robot button, and the bottom Settings/Start controls adjust to the active orientation.

## Drone Plane Model

The app currently uses two Core ML models:

- `DroneDetector/Models/DroneDetector.mlpackage` for the custom `plane_drone` detector.
- `DroneDetector/Models/YOLOv8n.mlpackage` for general COCO detections such as autos, humans, trucks, buses, motorcycles, birds, and planes.

The latest accepted fine-tune is:

```text
iphone_detector/runs/drone_detector-4/weights/best.pt
```

It was exported into the iOS app as:

```text
iphone_detector/DroneDetector/Models/DroneDetector.mlpackage
```

The previous app model was backed up at:

```text
iphone_detector/DroneDetector/Models/model_backups/DroneDetector_before_finetune_20260723.mlpackage
```

Latest comparison against the previous checkpoint:

| Split | Model | Precision | Recall | mAP50 | mAP50-95 |
|-------|-------|-----------|--------|-------|----------|
| validation | previous | `0.391` | `0.250` | `0.157` | `0.0421` |
| validation | new | `0.779` | `0.295` | `0.328` | `0.109` |
| test | previous | `0.605` | `0.532` | `0.532` | `0.181` |
| test | new | `0.912` | `0.522` | `0.536` | `0.173` |

The new checkpoint is kept in the app because validation improved strongly and test precision/mAP50 improved slightly. The fine-tune dataset was cleaned after export and build verification. Future fine-tunes should start from `iphone_detector/runs/drone_detector-4/weights/best.pt`.

## Dataset Preparer

The project includes a standalone Flask dataset-preparer tool for creating YOLO-ready datasets used to fine-tune the drone recognition models:

```text
dataset_preparer
```

It helps upload drone videos, extract frames, generate automatic mask and bounding-box proposals, review/approve frames, manually fix masks, accumulate a persistent master dataset, and export detection/segmentation datasets with the app-compatible `plane_drone` class mapping.

Use this tool when collecting new drone-plane training data before running the next fine-tune from the current accepted checkpoint.

## Optional: Recreate General YOLOv8n Model

The app works immediately with motion-based aerial object detection. For better accuracy, add a YOLO model.

**Important:** use a project venv. Global NumPy 2.x breaks Core ML export (`Numpy is not available` / `_ARRAY_API not found`).

```bash
cd iphone_detector
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements.txt
python scripts/download_model.py
```

Then in Xcode: if the model is not already listed under `DroneDetector/Models`, drag `DroneDetector/Models/YOLOv8n.mlpackage` into the project and ensure **Target Membership → DroneDetector** is checked.

### Branding

- **App icon:** `logo.png` → `Assets.xcassets/AppIcon` (1024×1024)
- **Launch / splash:** `app_start.png` → `LaunchScreen.storyboard` + in-app `SplashView` (~1.2s)
- **Home screen name:** **Vozhyk**

YOLOv8n detects COCO classes used by the general detector. The custom `DroneDetector.mlpackage` remains responsible for `plane_drone`.

## Radio Detection Notes

iOS does **not** expose raw spectrum analysis (433 MHz LoRa, 5.8 GHz FPV video, etc.). This app uses what the iPhone can access:

| Method | Band | What it detects |
|--------|------|-----------------|
| CoreBluetooth BLE scan | 2.4 GHz | Drone controllers, DJI BLE, FPV gear |
| Wi-Fi SSID check | 2.4 / 5 GHz | Connected or visible drone Wi-Fi names |

For full RF coverage (433 MHz RC, 5.8 GHz VTX), you still need external hardware on the rover (e.g. SX1278 LoRa module) as described in `solution.md`.

## Project Structure

```
.
├── README.md
├── dataset_preparer/        # Flask tool for building YOLO fine-tune datasets
├── iphone_detector/
│   ├── DroneDetector.xcodeproj
│   ├── DroneDetector/
│   │   ├── Camera/          # AVFoundation + Vision
│   │   ├── Radio/           # BLE + Wi-Fi RF scanner
│   │   ├── Views/           # SwiftUI overlays & HUD
│   │   └── Models/          # Core ML models and backups
│   └── scripts/
│       ├── download_model.py
│       └── train_drone_model.py
└── robot_station/
    ├── 3d_printer_parts/    # Printable robot-station mechanical parts
    └── esp_connector/       # PlatformIO ESP32 connector firmware
        ├── platformio.ini
        └── src/main.cpp
```

## Next Steps (Part 2)

This app is the **eyes & brain** on the iPhone. Part 2 has started with a PlatformIO firmware project for a **DOIT ESP32 DEVKIT V1** over Wi-Fi:

```text
robot_station/esp_connector
```

The first ESP32 connector firmware is for testing the iPhone-to-ESP32 link. It starts a Wi-Fi access point, exposes a small HTTP API, and prints serial logs at `115200` baud so received packets can be checked while the ESP32 is connected to a PC.

Current ESP32 test Wi-Fi:

- SSID: `Vozhyk-Robot`
- Password: `vozhyk-esp32`
- IP: `192.168.4.1`

Current ESP32 test API:

```text
GET  /status
POST /iphone/connect
POST /target
POST /scan/start
POST /scan/stop
```

The `POST /target` endpoint receives target data from the iPhone, including screen coordinates, object GPS coordinates, object name, object altitude, distance to object, and confidence. See `robot_station/esp_connector/README.md` for exact JSON examples.

Current iPhone-to-ESP32 connection behavior:

- The iPhone app uses local HTTP to `192.168.4.1`.
- With a personal Apple development team, iOS cannot programmatically join the ESP32 Wi-Fi AP because the required Hotspot Configuration capability is not available.
- For testing, manually connect the iPhone Wi-Fi to `Vozhyk-Robot`, then press the small robot button in the app.
- The robot button is red when disconnected, yellow while connecting, and green after `POST /iphone/connect` succeeds.
- After the button is green, the app sends detected `auto` and `human` targets to `POST /target` at most once per second.

Current flat target payload from the iPhone:

```json
{
  "device": "iPhone Vozhyk",
  "object_name": "human",
  "screen_x": 0.52,
  "screen_y": 0.43,
  "latitude": 54.687157,
  "longitude": 25.279652,
  "altitude_m": 143.2,
  "distance_m": 18.7,
  "confidence": 0.84,
  "phone_latitude": 54.687011,
  "phone_longitude": 25.279501,
  "phone_altitude_m": 143.2,
  "bearing_degrees": 72.4
}
```

`altitude_m` is currently the phone GPS altitude when available, or the phone barometer relative altitude fallback. It is not a true independent object altitude.

Current ESP32 servo test wiring:

- GPIO 25: main horizontal platform servo signal
- GPIO 26: ray module X-axis servo signal
- GPIO 27: ray module Y-axis servo signal

The three servos are powered from a separate 7V battery. The ESP32 provides only PWM signal wires, and ESP32 `GND` must be connected to the servo battery ground. The main platform servo scans horizontally from `0` to `180` degrees in `5` degree steps with `2` seconds between steps. The ray X/Y servos move toward the latest detected object screen point received from the iPhone.

Current 3D-printable robot-station part:

```text
robot_station/3d_printer_parts/iphone_holder.scad
```

This OpenSCAD part is the first iPhone holder prototype for the robot station. It is intended for 3D printing and includes the holder plate, angled phone support walls, ESP32/pillar box area, servo mounting plate, rounded rear base corners, and raised `VOZHYK` text on the front wall. See `robot_station/3d_printer_parts/README.md` for dimensions and print notes.

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

Later, the ESP32 API can be expanded from the current test endpoints into more servo-control commands such as:

```text
POST /ray/target
```

During the current test phase, when the iPhone detects an `auto` or `human` and the robot button is green, it sends normalized target coordinates and estimated GPS position to the ESP32:

```json
{
  "object_name": "auto",
  "screen_x": 0.62,
  "screen_y": 0.31,
  "latitude": 54.687157,
  "longitude": 25.279652,
  "altitude_m": 143.2,
  "distance_m": 82.5,
  "confidence": 0.84,
  "bearing_degrees": 74.1
}
```

The ESP32 will convert those coordinates into servo movement. One servo system can slowly rotate the iPhone so the camera scans outside, and another servo system can point the dedicated positioning ray toward the detected drone location.

Important hardware notes:

- Use a separate 5V power supply for servos.
- Connect ESP32 GND and servo power GND together.
- Do not power servos directly from the ESP32 3.3V pin.
- Add smoothing/dead-zone logic so the ray does not shake when detections move slightly.
- Auto-zoom on the iPhone will reset while the platform is moving and can zoom in again when the platform becomes stable.
