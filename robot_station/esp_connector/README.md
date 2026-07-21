# Vozhyk ESP32 Connector

PlatformIO firmware for the DOIT ESP32 DEVKIT V1 robot-side connector.

The ESP32 starts a Wi-Fi access point and exposes a small HTTP API for the iPhone detector app. Serial logs are printed at `115200` baud so they can be checked from the PlatformIO monitor while the ESP32 is connected to the PC.

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
