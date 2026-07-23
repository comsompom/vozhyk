# Vozhyk Robot Station 3D Printer Parts

This folder is for printable mechanical parts used by the Vozhyk robot station.

The current robot-station concept uses:

- iPhone detector app as the camera and object-recognition unit
- ESP32 controller mounted near the phone
- three servo signal outputs from the ESP32
- separate servo battery power
- horizontal scanning platform
- ray module that can be aimed toward a detected object

## Planned Parts

### Main Horizontal Platform

Purpose:

- Holds the iPhone.
- Holds the ESP32 module.
- Holds the ray module base.
- Rotates horizontally to scan the outside sky.

Servo:

- Controlled by ESP32 GPIO `25`.
- Expected movement range: `0` to `180` degrees.
- Current firmware moves in `5` degree steps with a `2` second delay between steps.

Design notes:

- Keep the platform stiff enough so the iPhone camera does not shake during scanning.
- Leave space for USB cable access to the iPhone and ESP32.
- Add holes or slots for zip ties or small screws.
- Provide a clear center of rotation near the platform balance point.

### iPhone Holder

Purpose:

- Keeps the iPhone stable on the main platform.
- Allows vertical and horizontal phone placement.
- Keeps the rear camera unobstructed.

Current source file:

- `iphone_holder.scad`

Current first prototype:

- simple rectangular base plate
- length: `100 mm`
- width: `80 mm`
- height: `3 mm`
- rear base corners:
  - radius: `30 mm`
  - only the two rear corners are rounded
- front top wall:
  - width: `78 mm`
  - height/length upward from plate: `55 mm`
  - thickness: `3 mm`
  - angle: `7 degrees` backward from vertical over the plate
  - raised front label:
    - text: `VOZHYK`
    - size: `10 mm`
    - depth: `0.8 mm`
    - centered on the outside face of the wall
- two side walls:
  - depth: `17 mm`
  - thickness: `3 mm`
  - height: `55 mm`
  - angle: same `7 degrees` as the front wall
- rear wall connecting the open side-wall ends:
  - width: `78 mm`
  - height: `40 mm`
  - thickness: `3 mm`
  - angle: same `7 degrees` as the front wall
- four bottom-plate pillars:
  - diameter: `2 mm`
  - height: `17 mm`
  - first row distance from holder rear wall: `10 mm`
  - center spacing across plate width: `46 mm`
  - center spacing along plate length: `23.5 mm`
- rectangular box around all four pillars:
  - inner wall distance from outer pillar centers: `3 mm`
  - wall width/thickness: `2 mm`
  - height: `22 mm`
  - front centered slot:
    - width: `9 mm`
    - height: `3.5 mm`
    - top edge: `2 mm` below box top
- rear center raised plate:
  - width: `11.5 mm`
  - length: `22.5 mm`
  - height: `1 mm`
  - centered across the main plate width
  - back edge distance from main plate back edge: `7 mm`
  - box walls around the raised servo plate:
    - wall height: `4.5 mm`
    - wall thickness: `2 mm`
    - walls rise from the main plate and surround the servo plate instead of sitting on top of it
  - extra side blocks on the servo frame:
    - one block on each top/bottom side of the servo frame
    - width outward from each side: `4 mm`
    - height: `4.5 mm`
    - one hole in each block:
      - diameter: `2 mm`
      - centered in the block
      - vertical through-hole from top to bottom
  - rear-side through-hole:
    - diameter: `11.5 mm`
    - centered across the raised plate width
    - tangent to the rear side of the raised plate
    - cuts through the raised plate and main base plate
  - smaller through-hole near the large hole:
    - diameter: `7 mm`
    - center distance from large hole center: `7 mm`
    - positioned forward from the large hole toward the inside of the plate
    - cuts through the raised plate and main base plate

Design notes:

- Do not cover the rear camera lenses.
- Do not press side buttons.
- Leave charging cable space.
- Use soft pads or printed flexible inserts if available.
- The holder should allow quick removal of the phone.

### ESP32 Mount

Purpose:

- Holds the DOIT ESP32 DEVKIT V1 on the main platform.
- Keeps GPIO signal wires accessible.

Design notes:

- Leave access to USB for flashing and serial monitor logs.
- Leave airflow around the board.
- Add standoff holes or clips.
- Keep servo signal wires strain-relieved.

### Ray Module X-Axis Bracket

Purpose:

- Moves the ray module left/right toward the detected object screen X position.

Servo:

- Controlled by ESP32 GPIO `26`.
- Current firmware maps normalized `screen_x` from `0.0...1.0` to servo angle `0...180`.

Design notes:

- Mount this bracket on the main horizontal platform.
- Keep the rotation axis aligned with the ray module center as much as possible.
- Add mechanical stops if needed to protect the servo.

### Ray Module Y-Axis Bracket

Purpose:

- Moves the ray module up/down toward the detected object screen Y position.

Servo:

- Controlled by ESP32 GPIO `27`.
- Current firmware maps normalized `screen_y` from `0.0...1.0` to servo angle `0...180`, with Y inverted so top-screen targets aim upward.

Design notes:

- Mount this bracket on the X-axis bracket.
- Keep the ray module lightweight.
- Avoid cable pull that can move the bracket or overload the servo.

### Battery And Wiring Holders

Purpose:

- Holds the separate servo battery.
- Routes servo power and signal wires safely.

Power notes:

- Servos are powered from a separate `7V` battery.
- ESP32 provides only PWM signal wires.
- ESP32 `GND` must be connected to servo battery ground.
- Do not power servos from the ESP32 `3V3` pin.

Design notes:

- Add cable channels or tie points.
- Keep battery weight near the platform center when possible.
- Keep wiring away from moving servo arms.

## Suggested Folder Layout

Use this structure as parts are added:

```text
robot_station/3d_printer_parts/
├── README.md
├── source/        # CAD source files, for example .f3d, .step, .scad
├── stl/           # Ready-to-print STL files
├── previews/      # Rendered images or photos of printed parts
└── notes/         # Print settings, measurements, assembly notes
```

## File Naming

Use clear names with version numbers:

```text
main_platform_v1.stl
iphone_holder_vertical_horizontal_v1.stl
esp32_mount_doit_devkit_v1.stl
ray_x_axis_bracket_v1.stl
ray_y_axis_bracket_v1.stl
battery_holder_7v_v1.stl
```

## Print Notes

- Prefer PETG or ABS for outdoor/heat exposure.
- PLA is acceptable for quick indoor prototypes.
- Use enough wall thickness for servo mounts.
- Increase infill around screw holes and servo mounting points.
- Test servo travel by hand before powering the servos.
- Check that the iPhone camera view is not blocked in both vertical and horizontal placement.

## Current Firmware Reference

ESP32 firmware folder:

```text
robot_station/esp_connector
```

Current servo signal pins:

| Servo | ESP32 signal pin | Purpose |
|-------|------------------|---------|
| Main platform | GPIO 25 | Rotates the whole scanning platform |
| Ray X axis | GPIO 26 | Aims ray module left/right |
| Ray Y axis | GPIO 27 | Aims ray module up/down |

The iPhone app sends detected target screen coordinates and estimated object GPS data to the ESP32. The ESP32 then maps screen coordinates to the ray X/Y servo angles.
