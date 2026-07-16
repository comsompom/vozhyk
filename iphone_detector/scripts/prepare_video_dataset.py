#!/usr/bin/env python3
"""Extract YOLO-format training frames from source videos.

The script creates a first-pass dataset from videos by sampling frames and using
motion segmentation to create draft bounding boxes. These labels are useful for
bootstrapping annotation, but they should be reviewed before final training.
"""

from __future__ import annotations

import argparse
import random
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np


CLASS_NAMES = [
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


@dataclass
class Sample:
    image: np.ndarray
    boxes: list[tuple[int, int, int, int]]
    video_stem: str
    frame_index: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True, help="Folder with input videos")
    parser.add_argument("--output", type=Path, required=True, help="Output YOLO dataset folder")
    parser.add_argument("--class-name", choices=CLASS_NAMES, default="drone")
    parser.add_argument("--sample-every", type=float, default=0.5, help="Seconds between sampled frames")
    parser.add_argument("--val-ratio", type=float, default=0.2)
    parser.add_argument("--max-frames-per-video", type=int, default=120)
    parser.add_argument("--min-area", type=int, default=8)
    parser.add_argument("--preview-count", type=int, default=48)
    parser.add_argument("--save-empty", action="store_true", help="Save sampled frames without draft boxes")
    parser.add_argument("--seed", type=int, default=7)
    return parser.parse_args()


def video_files(source: Path) -> list[Path]:
    extensions = {".mp4", ".mov", ".m4v", ".avi", ".mkv"}
    return sorted(path for path in source.iterdir() if path.suffix.lower() in extensions)


def detect_motion_boxes(frame: np.ndarray, subtractor: cv2.BackgroundSubtractor) -> list[tuple[int, int, int, int]]:
    mask = subtractor.apply(frame)
    mask = cv2.GaussianBlur(mask, (5, 5), 0)
    _, mask = cv2.threshold(mask, 220, 255, cv2.THRESH_BINARY)

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)
    mask = cv2.dilate(mask, kernel, iterations=2)

    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    boxes: list[tuple[int, int, int, int]] = []
    height, width = frame.shape[:2]
    max_area = width * height * 0.15

    for contour in contours:
        x, y, box_width, box_height = cv2.boundingRect(contour)
        area = box_width * box_height
        if area < 1 or area > max_area:
            continue
        boxes.append((x, y, box_width, box_height))

    return merge_boxes(boxes)


def merge_boxes(boxes: list[tuple[int, int, int, int]]) -> list[tuple[int, int, int, int]]:
    if not boxes:
        return []

    boxes = sorted(boxes, key=lambda box: box[2] * box[3], reverse=True)
    merged: list[tuple[int, int, int, int]] = []

    for box in boxes:
        if any(intersection_over_union(box, existing) > 0.15 for existing in merged):
            continue
        merged.append(box)

    return merged[:3]


def intersection_over_union(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> float:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    x1 = max(ax, bx)
    y1 = max(ay, by)
    x2 = min(ax + aw, bx + bw)
    y2 = min(ay + ah, by + bh)
    intersection = max(0, x2 - x1) * max(0, y2 - y1)
    union = aw * ah + bw * bh - intersection
    return intersection / union if union else 0


def extract_samples(video: Path, sample_every: float, max_frames: int, min_area: int, save_empty: bool) -> list[Sample]:
    capture = cv2.VideoCapture(str(video))
    if not capture.isOpened():
        raise RuntimeError(f"Could not open video: {video}")

    fps = capture.get(cv2.CAP_PROP_FPS) or 30
    stride = max(1, round(fps * sample_every))
    subtractor = cv2.createBackgroundSubtractorMOG2(history=90, varThreshold=14, detectShadows=False)
    samples: list[Sample] = []
    frame_index = 0

    while len(samples) < max_frames:
        ok, frame = capture.read()
        if not ok:
            break

        boxes = [
            box for box in detect_motion_boxes(frame, subtractor)
            if box[2] * box[3] >= min_area
        ]

        if frame_index % stride == 0 and (boxes or save_empty):
            samples.append(
                Sample(
                    image=frame,
                    boxes=boxes,
                    video_stem=video.stem,
                    frame_index=frame_index,
                )
            )

        frame_index += 1

    capture.release()
    return samples


def write_dataset(
    samples: list[Sample],
    output: Path,
    class_name: str,
    val_ratio: float,
    seed: int,
    preview_count: int,
) -> None:
    class_index = CLASS_NAMES.index(class_name)
    random.Random(seed).shuffle(samples)
    split_index = round(len(samples) * (1 - val_ratio))
    splits = {
        "train": samples[:split_index],
        "val": samples[split_index:],
    }

    for split_name in splits:
        (output / "images" / split_name).mkdir(parents=True, exist_ok=True)
        (output / "labels" / split_name).mkdir(parents=True, exist_ok=True)

    for split_name, split_samples in splits.items():
        for sample in split_samples:
            filename = f"{sample.video_stem}_{sample.frame_index:06d}"
            image_path = output / "images" / split_name / f"{filename}.jpg"
            label_path = output / "labels" / split_name / f"{filename}.txt"
            cv2.imwrite(str(image_path), sample.image, [int(cv2.IMWRITE_JPEG_QUALITY), 94])
            label_path.write_text(yolo_labels(sample.image, sample.boxes, class_index), encoding="utf-8")

    write_yaml(output)
    write_preview_sheet(samples, output, seed, preview_count)


def yolo_labels(image: np.ndarray, boxes: list[tuple[int, int, int, int]], class_index: int) -> str:
    height, width = image.shape[:2]
    rows: list[str] = []
    for x, y, box_width, box_height in boxes:
        center_x = (x + box_width / 2) / width
        center_y = (y + box_height / 2) / height
        normalized_width = box_width / width
        normalized_height = box_height / height
        rows.append(
            f"{class_index} {center_x:.6f} {center_y:.6f} "
            f"{normalized_width:.6f} {normalized_height:.6f}"
        )
    return "\n".join(rows) + ("\n" if rows else "")


def write_yaml(output: Path) -> None:
    names = "\n".join(f"  {index}: {name}" for index, name in enumerate(CLASS_NAMES))
    content = (
        f"path: {output.resolve()}\n"
        "train: images/train\n"
        "val: images/val\n"
        f"names:\n{names}\n"
    )
    (output / "data.yaml").write_text(content, encoding="utf-8")


def write_preview_sheet(samples: list[Sample], output: Path, seed: int, count: int = 48) -> None:
    selected = samples[:]
    random.Random(seed).shuffle(selected)
    selected = selected[:count]
    if not selected:
        return

    tile_width = 240
    tile_height = 160
    columns = 4
    rows = int(np.ceil(len(selected) / columns))
    sheet = np.full((rows * tile_height, columns * tile_width, 3), 24, dtype=np.uint8)

    for index, sample in enumerate(selected):
        row = index // columns
        column = index % columns
        tile = sample.image.copy()
        image_height, image_width = tile.shape[:2]

        for x, y, box_width, box_height in sample.boxes:
            cv2.rectangle(tile, (x, y), (x + box_width, y + box_height), (0, 255, 0), 2)

        cv2.putText(
            tile,
            f"{sample.video_stem}:{sample.frame_index}",
            (8, 18),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (255, 255, 255),
            1,
            cv2.LINE_AA,
        )

        scale = min(tile_width / image_width, tile_height / image_height)
        resized_width = round(image_width * scale)
        resized_height = round(image_height * scale)
        resized = cv2.resize(tile, (resized_width, resized_height), interpolation=cv2.INTER_AREA)
        x_offset = column * tile_width + (tile_width - resized_width) // 2
        y_offset = row * tile_height + (tile_height - resized_height) // 2
        sheet[y_offset:y_offset + resized_height, x_offset:x_offset + resized_width] = resized

    preview_dir = output / "previews"
    preview_dir.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(preview_dir / "draft_sheet.jpg"), sheet, [int(cv2.IMWRITE_JPEG_QUALITY), 92])


def main() -> None:
    args = parse_args()
    all_samples: list[Sample] = []

    for video in video_files(args.source):
        samples = extract_samples(
            video=video,
            sample_every=args.sample_every,
            max_frames=args.max_frames_per_video,
            min_area=args.min_area,
            save_empty=args.save_empty,
        )
        print(f"{video.name}: {len(samples)} samples")
        all_samples.extend(samples)

    if not all_samples:
        raise SystemExit("No samples extracted. Try --save-empty or lower --min-area.")

    write_dataset(
        samples=all_samples,
        output=args.output,
        class_name=args.class_name,
        val_ratio=args.val_ratio,
        seed=args.seed,
        preview_count=args.preview_count,
    )
    print(f"Saved {len(all_samples)} images to {args.output}")
    print(f"Dataset config: {args.output / 'data.yaml'}")


if __name__ == "__main__":
    main()
