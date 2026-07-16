#!/usr/bin/env python3
"""
Download a prompt-specialized YOLO-World model and export it to Core ML.

Use a dedicated venv (recommended) so global NumPy 2.x does not break the export:

  cd iphone_detector
  python3.11 -m venv .venv
  source .venv/bin/activate
  pip install -r scripts/requirements.txt
  python scripts/download_model.py
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
OUTPUT_DIR = PROJECT_DIR / "DroneDetector" / "Models"
WORK_DIR = PROJECT_DIR / ".model_export"


def check_numpy() -> None:
    try:
        import numpy as np
    except ImportError as exc:
        raise SystemExit(
            "numpy is not installed.\n"
            "Run: pip install -r scripts/requirements.txt"
        ) from exc

    major = int(np.__version__.split(".")[0])
    if major >= 2:
        raise SystemExit(
            f"Incompatible NumPy {np.__version__} detected.\n\n"
            "PyTorch / coremltools used for Core ML export require NumPy 1.x.\n"
            "Fix with a clean venv:\n\n"
            "  cd iphone_detector\n"
            "  python3.11 -m venv .venv\n"
            "  source .venv/bin/activate\n"
            "  pip install -r scripts/requirements.txt\n"
        "  python scripts/download_model.py\n"
        )


def find_exported_package(search_roots: list[Path]) -> Path | None:
    candidates = [
        "drone_detector.mlpackage",
        "DroneDetector.mlpackage",
    ]
    for root in search_roots:
        for name in candidates:
            path = root / name
            if path.exists():
                return path
        for path in root.glob("**/drone_detector.mlpackage"):
            return path
    return None


def main() -> None:
    check_numpy()

    try:
        from ultralytics import YOLOWorld
    except ImportError as exc:
        raise SystemExit(
            "ultralytics is not installed.\n"
            "Run: pip install -r scripts/requirements.txt"
        ) from exc

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / "DroneDetector.mlpackage"

    # Export into a stable work dir, not the caller's cwd / Desktop
    os.chdir(WORK_DIR)
    print(f"Working directory: {WORK_DIR}")
    print("Downloading YOLOv8s-World and specializing it for the app's classes...")

    # YOLO-World supports open-vocabulary detection. Restricting the vocabulary
    # prevents the app from reporting the full COCO object list while allowing a
    # real `drone` prompt without pretending that kites are drones.
    model = YOLOWorld("yolov8s-world.pt")
    model.set_classes([
        "car", "airplane", "drone", "bird", "person", "bus", "truck", "motorcycle"
    ])
    model.save("drone_detector.pt")
    model = YOLOWorld("drone_detector.pt")
    result = model.export(format="coreml", imgsz=640, nms=True)

    exported: Path | None = None
    if isinstance(result, (str, Path)):
        candidate = Path(result)
        if candidate.exists():
            exported = candidate

    if exported is None:
        exported = find_exported_package([WORK_DIR, Path.cwd(), PROJECT_DIR])

    if exported is None or not exported.exists():
        raise SystemExit(
            "Export finished but drone_detector.mlpackage was not found.\n"
            f"Checked under: {WORK_DIR}"
        )

    if output_path.exists():
        shutil.rmtree(output_path)

    if exported.resolve() != output_path.resolve():
        shutil.move(str(exported), str(output_path))

    print(f"Model saved to: {output_path}")
    print("The Xcode project is already configured to compile DroneDetector.mlpackage.")


if __name__ == "__main__":
    main()
