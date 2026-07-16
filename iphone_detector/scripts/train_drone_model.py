#!/usr/bin/env python3
"""Fine-tune a drone-aware YOLO model and export it to the iOS app's Core ML package.

Usage (inside iphone_detector/.venv):
  cp datasets/drone.yaml.example datasets/drone.yaml
  # Edit drone.yaml, then:
  python scripts/train_drone_model.py --data datasets/drone.yaml --device mps

The output is DroneDetector/Models/DroneDetector.mlpackage. Add that package to
the Xcode target, then change the resource name in DroneVisionDetector if needed.
"""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from ultralytics import YOLO


PROJECT_DIR = Path(__file__).resolve().parents[1]
OUTPUT_DIR = PROJECT_DIR / "DroneDetector" / "Models"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, required=True, help="YOLO dataset YAML")
    parser.add_argument("--model", default="yolov8n.pt", help="Pretrained starting weights")
    parser.add_argument("--imgsz", type=int, default=960, help="Use 960+ for small distant drones")
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--batch", type=int, default=-1, help="-1 automatically fits available memory")
    parser.add_argument("--device", default="", help="e.g. mps, 0, or cpu")
    args = parser.parse_args()

    if not args.data.is_file():
        raise SystemExit(f"Dataset config not found: {args.data}")

    model = YOLO(args.model)
    results = model.train(
        data=str(args.data),
        imgsz=args.imgsz,
        epochs=args.epochs,
        batch=args.batch,
        device=args.device,
        patience=20,
        close_mosaic=10,
        project=str(PROJECT_DIR / "runs"),
        name="drone_detector",
    )

    best = Path(results.save_dir) / "weights" / "best.pt"
    if not best.is_file():
        raise SystemExit(f"Training completed but best weights were not found: {best}")

    exported = Path(YOLO(str(best)).export(format="coreml", imgsz=args.imgsz, nms=True))
    if not exported.is_dir():
        raise SystemExit(f"Core ML export was not found: {exported}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    destination = OUTPUT_DIR / "DroneDetector.mlpackage"
    if destination.exists():
        shutil.rmtree(destination)
    shutil.move(str(exported), destination)
    print(f"Saved custom drone model to: {destination}")


if __name__ == "__main__":
    main()
