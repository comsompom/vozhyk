# Vozhyk Robot Station

Robot-side code and hardware integration notes for the Vozhyk drone protector system.

## Folders

- `esp_connector/` - PlatformIO firmware for the DOIT ESP32 DEVKIT V1 connector that receives iPhone target data over Wi-Fi.

The first ESP32 firmware starts a Wi-Fi access point, accepts HTTP messages from the iPhone detector app, logs received object target packets over USB serial for testing, and drives three servo signal lines:

- main horizontal platform servo,
- ray module X-axis servo,
- ray module Y-axis servo.

The servos must use a separate power source. The ESP32 provides only the signal wires, and ESP32 ground must be tied to the servo battery ground.
