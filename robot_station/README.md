# Vozhyk Robot Station

Robot-side code and hardware integration notes for the Vozhyk drone protector system.

## Folders

- `esp_connector/` - PlatformIO firmware for the DOIT ESP32 DEVKIT V1 connector that receives iPhone target data over Wi-Fi.

The first ESP32 firmware starts a Wi-Fi access point, accepts HTTP messages from the iPhone detector app, and logs received object target packets over USB serial for testing.
