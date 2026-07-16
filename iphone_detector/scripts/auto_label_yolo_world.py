#!/usr/bin/env python3
"""Create draft YOLO labels for an extracted dataset using YOLO-World.

This is intended to accelerate annotation, not replace review. It maps
YOLO-World prompts into the app's eight supported object classes.
"""

from __future__ import annotations

import argparse
import random
from pathlib import Path

import cv2
import numpy as np
from ultralytics import YOLOWorld


DATASET_NAMES = [
    "auto",
    "plane",
    "drone",
    "plane_drone",
    "bird",
    "human",
    "bus",
    "truck",
    "motorcycle",
]

PROMPTS = [
    "car",
    "airplane",
    "drone",
    "fixed wing drone",
    "bird",
    "person",
    "bus",
    "truck",
    "motorcycle",
]

PROMPT_TO_DATASET_INDEX = {
    0: 0,
    1: 1,
    2: 2,
    3: 3,
    4: 4,
    5: 5,
    6: 6,
    7: 7,
    8: 8,
}

CLASS_PRIORITY = {
    3: 110,  # plane_drone
    2: 100,  # drone
    1: 90,   # plane
    4: 80,   # bird
    0: 50,   # auto
    6: 45,   # bus
    7: 45,   # truck
    8: 45,   # motorcycle
    5: 30,   # human
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, required=True, help="YOLO dataset folder")
    parser.add_argument("--model", type=Path, default=Path("iphone_detector/.model_export/yolov8s-world.pt"))
    parser.add_argument("--imgsz", type=int, default=960)
    parser.add_argument("--conf", type=float, default=0.05)
    parser.add_argument("--iou", type=float, default=0.45)
    parser.add_argument("--max-images", type=int, default=0, help="Limit processed images; 0 means all")
    parser.add_argument("--progress-every", type=int, default=25)
    parser.add_argument("--preview-count", type=int, default=48)
    parser.add_argument("--seed", type=int, default=11)
    return parser.parse_args()


def image_files(dataset: Path) -> list[Path]:
    files: list[Path] = []
    for split in ("train", "val"):
        split_dir = dataset / "images" / split
        if split_dir.is_dir():
            files.extend(sorted(split_dir.glob("*.jpg")))
    return files


def label_path_for(dataset: Path, image_path: Path) -> Path:
    split = image_path.parent.name
    return dataset / "labels" / split / f"{image_path.stem}.txt"


def filter_overlaps(
    detections: list[tuple[int, float, list[float]]],
    iou_threshold: float,
) -> list[tuple[int, float, list[float]]]:
    detections = sorted(
        detections,
        key=lambda item: (CLASS_PRIORITY.get(item[0], 0), item[1]),
        reverse=True,
    )
    kept: list[tuple[int, float, list[float]]] = []

    for detection in detections:
        if any(iou_xywhn(detection[2], existing[2]) > iou_threshold for existing in kept):
            continue
        kept.append(detection)

    return kept


def iou_xywhn(a: list[float], b: list[float]) -> float:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    a_x1, a_y1 = ax - aw / 2, ay - ah / 2
    a_x2, a_y2 = ax + aw / 2, ay + ah / 2
    b_x1, b_y1 = bx - bw / 2, by - bh / 2
    b_x2, b_y2 = bx + bw / 2, by + bh / 2

    x1 = max(a_x1, b_x1)
    y1 = max(a_y1, b_y1)
    x2 = min(a_x2, b_x2)
    y2 = min(a_y2, b_y2)
    intersection = max(0, x2 - x1) * max(0, y2 - y1)
    union = aw * ah + bw * bh - intersection
    return intersection / union if union else 0


def write_dataset_yaml(dataset: Path) -> None:
    names = "\n".join(f"  {index}: {name}" for index, name in enumerate(DATASET_NAMES))
    content = (
        f"path: {dataset.resolve()}\n"
        "train: images/train\n"
        "val: images/val\n"
        f"names:\n{names}\n"
    )
    (dataset / "data.yaml").write_text(content, encoding="utf-8")


def write_preview(dataset: Path, image_paths: list[Path], seed: int, count: int) -> None:
    selected = image_paths[:]
    random.Random(seed).shuffle(selected)
    selected = selected[:count]
    if not selected:
        return

    tile_width = 240
    tile_height = 160
    columns = 4
    rows = int(np.ceil(len(selected) / columns))
    sheet = np.full((rows * tile_height, columns * tile_width, 3), 24, dtype=np.uint8)

    for index, image_path in enumerate(selected):
        image = cv2.imread(str(image_path))
        if image is None:
            continue
        height, width = image.shape[:2]
        label_path = label_path_for(dataset, image_path)

        if label_path.is_file():
            for line in label_path.read_text(encoding="utf-8").splitlines():
                parts = line.split()
                if len(parts) != 5:
                    continue
                class_index = int(parts[0])
                center_x, center_y, box_width, box_height = map(float, parts[1:])
                x1 = round((center_x - box_width / 2) * width)
                y1 = round((center_y - box_height / 2) * height)
                x2 = round((center_x + box_width / 2) * width)
                y2 = round((center_y + box_height / 2) * height)
                cv2.rectangle(image, (x1, y1), (x2, y2), (0, 255, 0), 2)
                cv2.putText(
                    image,
                    DATASET_NAMES[class_index],
                    (x1, max(14, y1 - 4)),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.45,
                    (0, 255, 0),
                    1,
                    cv2.LINE_AA,
                )

        row = index // columns
        column = index % columns
        scale = min(tile_width / width, tile_height / height)
        resized_width = round(width * scale)
        resized_height = round(height * scale)
        resized = cv2.resize(image, (resized_width, resized_height), interpolation=cv2.INTER_AREA)
        x_offset = column * tile_width + (tile_width - resized_width) // 2
        y_offset = row * tile_height + (tile_height - resized_height) // 2
        sheet[y_offset:y_offset + resized_height, x_offset:x_offset + resized_width] = resized

    preview_dir = dataset / "previews"
    preview_dir.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(preview_dir / "yolo_world_sheet.jpg"), sheet, [int(cv2.IMWRITE_JPEG_QUALITY), 92])


def main() -> None:
    args = parse_args()
    paths = image_files(args.dataset)
    if args.max_images > 0:
        paths = paths[:args.max_images]
    if not paths:
        raise SystemExit(f"No dataset images found under {args.dataset}")

    model = YOLOWorld(str(args.model))
    model.set_classes(PROMPTS)
    counts = {name: 0 for name in DATASET_NAMES}
    labeled_images = 0

    for index, image_path in enumerate(paths, start=1):
        result = model.predict(
            str(image_path),
            imgsz=args.imgsz,
            conf=args.conf,
            verbose=False,
        )[0]
        detections: list[tuple[int, float, list[float]]] = []
        if result.boxes is not None:
            classes = result.boxes.cls.cpu().tolist()
            confidences = result.boxes.conf.cpu().tolist()
            boxes = result.boxes.xywhn.cpu().tolist()
            for prompt_index, confidence, box in zip(classes, confidences, boxes):
                dataset_index = PROMPT_TO_DATASET_INDEX[int(prompt_index)]
                detections.append((dataset_index, float(confidence), [float(value) for value in box]))

        filtered = filter_overlaps(detections, args.iou)
        label_path = label_path_for(args.dataset, image_path)
        label_path.parent.mkdir(parents=True, exist_ok=True)
        rows = []
        for class_index, _, box in filtered:
            rows.append(f"{class_index} {' '.join(f'{value:.6f}' for value in box)}")
            counts[DATASET_NAMES[class_index]] += 1
        label_path.write_text("\n".join(rows) + ("\n" if rows else ""), encoding="utf-8")
        if rows:
            labeled_images += 1

        if args.progress_every > 0 and index % args.progress_every == 0:
            print(f"Processed {index}/{len(paths)} images")

    write_dataset_yaml(args.dataset)
    write_preview(args.dataset, paths, args.seed, args.preview_count)

    print(f"Processed {len(paths)} images")
    print(f"Labeled images: {labeled_images}")
    for name, count in counts.items():
        if count:
            print(f"{name}: {count}")
    print(f"Preview: {args.dataset / 'previews' / 'yolo_world_sheet.jpg'}")


if __name__ == "__main__":
    main()
