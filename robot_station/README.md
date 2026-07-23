# Vozhyk Robot Station

Robot-side code and hardware integration notes for the Vozhyk drone protector system.

## Folders

- `esp_connector/` - PlatformIO firmware for the DOIT ESP32 DEVKIT V1 connector that receives iPhone target data over Wi-Fi HTTP.
- `3d_printer_parts/` - printable mechanical part notes for the iPhone platform, ESP32 mount, three-servo ray module, battery holder, and future STL/CAD files.

## 3D Printable iPhone Holder

The first robot-station printable part is:

```text
robot_station/3d_printer_parts/iphone_holder.scad
```

This OpenSCAD source defines the iPhone holder that will be printed on a 3D printer and mounted on the robot station platform. The current prototype includes the main holder plate, angled phone support walls, ESP32/pillar box area, servo mounting plate and holes, rounded rear base corners, and raised `VOZHYK` text on the front wall.

The first ESP32 firmware starts a Wi-Fi access point, accepts HTTP messages from the iPhone detector app, logs received object target packets over USB serial for testing, and drives three servo signal lines:

- main horizontal platform servo,
- ray module X-axis servo,
- ray module Y-axis servo.

The servos must use a separate power source. The ESP32 provides only the signal wires, and ESP32 ground must be tied to the servo battery ground.

Current iPhone test workflow:

- Manually connect the iPhone to ESP32 Wi-Fi `Vozhyk-Robot`.
- Press the robot button in the iPhone app.
- When the button turns green, the app sends detected `auto` and `human` targets to the ESP32 `/target` endpoint.
- The payload includes object name, normalized screen position, estimated object GPS coordinates, altitude field, distance, confidence, phone GPS, phone altitude, and bearing.

The iPhone app cannot auto-join the ESP32 Wi-Fi AP when signed with a personal Apple development team because Apple does not provide the required Hotspot Configuration entitlement for personal teams.
