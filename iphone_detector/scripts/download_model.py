#!/usr/bin/env python3
"""
Download YOLOv8n and export to Core ML for DroneDetector.

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
        "yolov8n.mlpackage",
        "YOLOv8n.mlpackage",
    ]
    for root in search_roots:
        for name in candidates:
            path = root / name
            if path.exists():
                return path
        for path in root.glob("**/yolov8n.mlpackage"):
            return path
    return None


def main() -> None:
    check_numpy()

    try:
        from ultralytics import YOLO
    except ImportError as exc:
        raise SystemExit(
            "ultralytics is not installed.\n"
            "Run: pip install -r scripts/requirements.txt"
        ) from exc

    try:
        import coremltools  # noqa: F401
    except ImportError as exc:
        raise SystemExit(
            "coremltools is not installed.\n"
            "Run: pip install -r scripts/requirements.txt"
        ) from exc

    WORK_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / "YOLOv8n.mlpackage"

    # Export into a stable work dir, not the caller's cwd / Desktop
    os.chdir(WORK_DIR)
    print(f"Working directory: {WORK_DIR}")
    print("Downloading YOLOv8n and exporting to Core ML...")

    model = YOLO("yolov8n.pt")
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
            "Export finished but yolov8n.mlpackage was not found.\n"
            f"Checked under: {WORK_DIR}"
        )

    if output_path.exists():
        shutil.rmtree(output_path)

    if exported.resolve() != output_path.resolve():
        shutil.move(str(exported), str(output_path))

    print(f"Model saved to: {output_path}")
    print("In Xcode, drag YOLOv8n.mlpackage into the DroneDetector target if it is not already listed.")


if __name__ == "__main__":
    main()
