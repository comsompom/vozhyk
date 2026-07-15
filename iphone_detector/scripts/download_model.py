#!/usr/bin/env python3
"""
Download YOLOv8n and export to Core ML for DroneDetector.

Requirements:
  pip install ultralytics coremltools

Usage:
  python3 scripts/download_model.py
"""

from pathlib import Path

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "DroneDetector" / "Models"


def main() -> None:
    try:
        from ultralytics import YOLO
    except ImportError as exc:
        raise SystemExit(
            "Install dependencies first: pip install ultralytics coremltools"
        ) from exc

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / "YOLOv8n.mlpackage"

    print("Downloading YOLOv8n and exporting to Core ML...")
    model = YOLO("yolov8n.pt")
    model.export(format="coreml", imgsz=640, nms=True)

    # ultralytics writes yolov8n.mlpackage next to cwd
    exported = Path("yolov8n.mlpackage")
    if not exported.exists():
        raise SystemExit("Export failed: yolov8n.mlpackage not found")

    if output_path.exists():
        import shutil
        shutil.rmtree(output_path)

    exported.rename(output_path)
    print(f"Model saved to: {output_path}")
    print("Open DroneDetector.xcodeproj and add YOLOv8n.mlpackage to the target if needed.")


if __name__ == "__main__":
    main()
