# Vozhyk ESP32 Connector

PlatformIO firmware for the DOIT ESP32 DEVKIT V1 robot-side connector.

The ESP32 starts a Wi-Fi access point and exposes a small HTTP API for the iPhone detector app. Serial logs are printed at `115200` baud so they can be checked from the PlatformIO monitor while the ESP32 is connected to the PC.

The firmware also controls three servo signal lines:

- main horizontal platform scan servo
- ray module X-axis servo
- ray module Y-axis servo

The servos must be powered from a separate battery. The ESP32 only provides the PWM signal wires.

## Wi-Fi

- SSID: `Vozhyk-Robot`
- Password: `vozhyk-esp32`
- ESP32 IP: `192.168.4.1`

## Upload

Open this folder in Visual Studio Code with the PlatformIO extension:

```sh
robot_station/esp_connector
```

Then run:

```sh
pio run --target upload
pio device monitor --baud 115200
```

## Servo Wiring

Default signal pins:

| Servo | ESP32 signal pin | Purpose |
|-------|------------------|---------|
| Main platform | GPIO 25 | Rotates the iPhone/ESP32/ray platform horizontally |
| Ray X axis | GPIO 26 | Moves the ray module left/right |
| Ray Y axis | GPIO 27 | Moves the ray module up/down |

Power wiring:

- Power the servos from the separate 7V battery.
- Connect the servo battery ground to ESP32 `GND`.
- Connect each servo signal wire to the ESP32 signal pin above.
- Do not power the servos from the ESP32 `3V3` pin.

Main platform scan behavior:

- Starts enabled by default.
- Sweeps from `0` to `180` degrees and back.
- Moves in `5` degree steps.
- Waits `2` seconds between each step.

Ray module behavior:

- When `/target` receives object screen coordinates, `screen_x` maps to the ray X servo angle.
- `screen_y` maps to the ray Y servo angle with the Y axis inverted, so top-screen targets aim upward.
- Both ray servos currently map normalized screen coordinates `0.0...1.0` to servo angles `0...180`.

## API

### Status

```http
GET http://192.168.4.1/status
```

### iPhone Connect

```http
POST http://192.168.4.1/iphone/connect
Content-Type: application/json
```

```json
{
  "device": "iPhone Vozhyk"
}
```

### Target Packet

```http
POST http://192.168.4.1/target
Content-Type: application/json
```

Flat payload:

```json
{
  "device": "iPhone Vozhyk",
  "object_name": "plane_drone",
  "screen_x": 0.62,
  "screen_y": 0.31,
  "latitude": 54.687157,
  "longitude": 25.279652,
  "altitude_m": 143.2,
  "distance_m": 82.5,
  "confidence": 0.84
}
```

Nested payload is also accepted:

```json
{
  "iphone": {
    "device": "iPhone Vozhyk"
  },
  "screen": {
    "x": 0.62,
    "y": 0.31
  },
  "object": {
    "name": "plane_drone",
    "latitude": 54.687157,
    "longitude": 25.279652,
    "altitude_m": 143.2,
    "distance_m": 82.5,
    "confidence": 0.84
  }
}
```

The firmware logs each target packet with object name, screen coordinates, GPS coordinates, altitude, distance, confidence, iPhone device name, and remote IP.

### Main Platform Scan Control

```http
POST http://192.168.4.1/scan/start
```

```http
POST http://192.168.4.1/scan/stop
```

Use these endpoints to start or stop the automatic horizontal scan servo.
