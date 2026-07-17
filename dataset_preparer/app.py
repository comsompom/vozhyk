import json
import math
import shutil
import uuid
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np
import yaml
from flask import Flask, jsonify, redirect, render_template, request, send_from_directory, url_for
from werkzeug.utils import secure_filename


BASE_DIR = Path(__file__).resolve().parent
WORKSPACE_DIR = BASE_DIR / "workspace"
UPLOADS_DIR = WORKSPACE_DIR / "uploads"
PROJECTS_DIR = WORKSPACE_DIR / "projects"
MASTER_DIR = WORKSPACE_DIR / "master_dataset"
MASTER_IMAGES_DIR = MASTER_DIR / "images"
MASTER_MASKS_DIR = MASTER_DIR / "masks"
MASTER_METADATA_PATH = MASTER_DIR / "dataset.json"
ALLOWED_EXTENSIONS = {".mp4", ".mov", ".m4v", ".avi", ".mkv"}
APP_CLASS_NAMES = [
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


app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 8 * 1024 * 1024 * 1024


def utc_now():
    return datetime.utcnow().replace(microsecond=0).isoformat() + "Z"


def allowed_video(filename):
    return Path(filename).suffix.lower() in ALLOWED_EXTENSIONS


def project_dir(project_id):
    return PROJECTS_DIR / project_id


def metadata_path(project_id):
    return project_dir(project_id) / "project.json"


def load_project(project_id):
    with metadata_path(project_id).open("r", encoding="utf-8") as file:
        return json.load(file)


def save_project(project):
    path = metadata_path(project["id"])
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as file:
        json.dump(project, file, indent=2)


def list_projects():
    projects = []
    if not PROJECTS_DIR.exists():
        return projects

    for path in sorted(PROJECTS_DIR.iterdir(), reverse=True):
        meta = path / "project.json"
        if not meta.exists():
            continue
        try:
            with meta.open("r", encoding="utf-8") as file:
                projects.append(json.load(file))
        except json.JSONDecodeError:
            continue
    return projects


def empty_master_dataset():
    return {
        "created_at": utc_now(),
        "updated_at": utc_now(),
        "class_names": APP_CLASS_NAMES,
        "items": [],
        "exports": [],
    }


def load_master_dataset():
    if not MASTER_METADATA_PATH.exists():
        return empty_master_dataset()

    with MASTER_METADATA_PATH.open("r", encoding="utf-8") as file:
        dataset = json.load(file)

    dataset.setdefault("class_names", APP_CLASS_NAMES)
    dataset.setdefault("items", [])
    dataset.setdefault("exports", [])
    return dataset


def save_master_dataset(dataset):
    MASTER_DIR.mkdir(parents=True, exist_ok=True)
    dataset["updated_at"] = utc_now()
    with MASTER_METADATA_PATH.open("w", encoding="utf-8") as file:
        json.dump(dataset, file, indent=2)


def master_summary():
    dataset = load_master_dataset()
    return {
        "total": len(dataset["items"]),
        "exports": dataset.get("exports", []),
        "updated_at": dataset.get("updated_at"),
    }


def master_key(project_id, frame_id):
    return f"{project_id}_{frame_id}"


def remove_master_item(project_id, frame_id):
    dataset = load_master_dataset()
    key = master_key(project_id, frame_id)
    old_count = len(dataset["items"])
    dataset["items"] = [item for item in dataset["items"] if item["id"] != key]

    if len(dataset["items"]) == old_count:
        return False

    save_master_dataset(dataset)
    return True


def upsert_master_item(project, frame):
    if not frame.get("has_mask") or not frame.get("bbox") or not frame.get("polygon_normalized"):
        raise ValueError("Only frames with a valid mask can be added to the master dataset.")

    dataset = load_master_dataset()
    key = master_key(project["id"], frame["id"])
    image_name = f"{key}.jpg"
    mask_name = f"{key}.png"
    MASTER_IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    MASTER_MASKS_DIR.mkdir(parents=True, exist_ok=True)

    shutil.copy2(project_dir(project["id"]) / "frames" / frame["image"], MASTER_IMAGES_DIR / image_name)
    shutil.copy2(project_dir(project["id"]) / "masks" / frame["mask"], MASTER_MASKS_DIR / mask_name)

    item = {
        "id": key,
        "source_project_id": project["id"],
        "source_project_name": project["name"],
        "source_frame_id": frame["id"],
        "source_frame_index": frame["frame_index"],
        "source_timestamp": frame["timestamp"],
        "image": image_name,
        "mask": mask_name,
        "width": frame["width"],
        "height": frame["height"],
        "class_name": project["class_name"],
        "class_names": project.get("class_names") or APP_CLASS_NAMES,
        "bbox": frame["bbox"],
        "polygon": frame["polygon"],
        "polygon_normalized": frame["polygon_normalized"],
        "mask_source": frame.get("mask_source", "auto"),
        "added_at": utc_now(),
    }

    dataset["items"] = [existing for existing in dataset["items"] if existing["id"] != key]
    dataset["items"].append(item)
    dataset["items"].sort(key=lambda value: (value["source_project_id"], value["source_frame_index"], value["id"]))
    save_master_dataset(dataset)
    return item


def normalize_points(points, width, height):
    normalized = []
    for x, y in points:
        normalized.append(round(max(0, min(1, x / width)), 6))
        normalized.append(round(max(0, min(1, y / height)), 6))
    return normalized


def sanitize_polygon(points, width, height):
    polygon = []
    for point in points:
        if not isinstance(point, (list, tuple)) or len(point) != 2:
            continue

        try:
            x = int(round(float(point[0])))
            y = int(round(float(point[1])))
        except (TypeError, ValueError):
            continue

        polygon.append((max(0, min(width - 1, x)), max(0, min(height - 1, y))))

    return polygon


def polygon_from_contour(contour, width, height):
    epsilon = max(1.5, 0.01 * cv2.arcLength(contour, True))
    approx = cv2.approxPolyDP(contour, epsilon, True)
    points = [(int(point[0][0]), int(point[0][1])) for point in approx]

    if len(points) < 3:
        x, y, w, h = cv2.boundingRect(contour)
        points = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]

    clipped = []
    for x, y in points:
        clipped.append((max(0, min(width - 1, x)), max(0, min(height - 1, y))))
    return clipped


def choose_drone_contour(contours, width, height, min_area, max_area_ratio):
    frame_area = width * height
    max_area = frame_area * max_area_ratio
    candidates = []

    for contour in contours:
        area = cv2.contourArea(contour)
        if area < min_area or area > max_area:
            continue

        x, y, w, h = cv2.boundingRect(contour)
        if w < 4 or h < 4:
            continue

        bbox_area = w * h
        fill_ratio = area / max(1, bbox_area)
        aspect = w / max(1, h)
        if aspect > 8 or aspect < 0.125:
            continue

        center_y = y + h / 2
        size_score = 1 / (1 + abs(math.sqrt(area) - 28))
        fill_score = min(fill_ratio, 1)
        sky_bias = 1 - (center_y / height)
        score = area * 0.35 + size_score * 250 + fill_score * 80 + sky_bias * 40
        candidates.append((score, contour))

    if not candidates:
        return None

    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1]


def write_mask(mask_path, polygon, width, height):
    mask = np.zeros((height, width), dtype=np.uint8)
    mask[:] = 0
    if polygon:
        cv2.fillPoly(mask, [np.array(polygon, dtype=np.int32)], 255)
    cv2.imwrite(str(mask_path), mask)


def frame_label_from_polygon(polygon, width, height):
    if not polygon:
        return None

    polygon = sanitize_polygon(polygon, width, height)
    if len(polygon) < 3:
        return None

    xs = [point[0] for point in polygon]
    ys = [point[1] for point in polygon]
    x_min = max(0, min(xs))
    y_min = max(0, min(ys))
    x_max = min(width - 1, max(xs))
    y_max = min(height - 1, max(ys))
    box_width = x_max - x_min
    box_height = y_max - y_min

    if box_width <= 0 or box_height <= 0:
        return None

    bbox = {
        "x": x_min,
        "y": y_min,
        "width": box_width,
        "height": box_height,
        "normalized": [
            round((x_min + box_width / 2) / width, 6),
            round((y_min + box_height / 2) / height, 6),
            round(box_width / width, 6),
            round(box_height / height, 6),
        ],
    }

    return {
        "bbox": bbox,
        "polygon": polygon,
        "polygon_normalized": normalize_points(polygon, width, height),
    }


def process_video(project, sample_fps, min_area, max_area_ratio):
    video_path = Path(project["video_path"])
    frames_dir = project_dir(project["id"]) / "frames"
    masks_dir = project_dir(project["id"]) / "masks"
    frames_dir.mkdir(parents=True, exist_ok=True)
    masks_dir.mkdir(parents=True, exist_ok=True)

    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise RuntimeError("Could not open uploaded video.")

    source_fps = capture.get(cv2.CAP_PROP_FPS) or 30
    frame_total = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    interval = max(1, int(round(source_fps / sample_fps)))
    subtractor = cv2.createBackgroundSubtractorMOG2(history=240, varThreshold=20, detectShadows=False)

    frames = []
    frame_index = -1
    saved_index = 0

    while True:
        ok, frame = capture.read()
        if not ok:
            break

        frame_index += 1
        fg_mask = subtractor.apply(frame)

        if frame_index % interval != 0:
            continue

        height, width = frame.shape[:2]
        _, threshold = cv2.threshold(fg_mask, 220, 255, cv2.THRESH_BINARY)
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        threshold = cv2.morphologyEx(threshold, cv2.MORPH_OPEN, kernel)
        threshold = cv2.dilate(threshold, kernel, iterations=2)
        contours, _ = cv2.findContours(threshold, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        contour = choose_drone_contour(contours, width, height, min_area, max_area_ratio)
        polygon = polygon_from_contour(contour, width, height) if contour is not None else []
        label = frame_label_from_polygon(polygon, width, height)

        frame_id = f"frame_{saved_index:06d}"
        image_name = f"{frame_id}.jpg"
        mask_name = f"{frame_id}.png"
        cv2.imwrite(str(frames_dir / image_name), frame, [int(cv2.IMWRITE_JPEG_QUALITY), 94])
        write_mask(masks_dir / mask_name, polygon, width, height)

        timestamp = frame_index / source_fps if source_fps else 0
        frames.append(
            {
                "id": frame_id,
                "frame_index": frame_index,
                "timestamp": round(timestamp, 3),
                "image": image_name,
                "mask": mask_name,
                "width": width,
                "height": height,
                "decision": "pending",
                "has_mask": label is not None,
                "bbox": label["bbox"] if label else None,
                "polygon": label["polygon"] if label else [],
                "polygon_normalized": label["polygon_normalized"] if label else [],
            }
        )
        saved_index += 1

    capture.release()

    project["status"] = "ready"
    project["updated_at"] = utc_now()
    project["source_fps"] = round(source_fps, 3)
    project["source_frame_count"] = frame_total
    project["sample_fps"] = sample_fps
    project["min_area"] = min_area
    project["max_area_ratio"] = max_area_ratio
    project["frames"] = frames
    save_project(project)


def split_dataset_items(items):
    approved = list(items)
    approved.sort(key=lambda item: (item.get("source_project_id", ""), item.get("source_frame_index", 0), item["id"]))

    if not approved:
        return {"train": [], "val": [], "test": []}

    if len(approved) == 1:
        return {"train": approved, "val": [], "test": []}

    if len(approved) == 2:
        return {"train": approved[:1], "val": approved[1:], "test": []}

    if len(approved) == 3:
        return {"train": approved[:2], "val": approved[2:], "test": []}

    train_end = max(1, round(len(approved) * 0.7))
    val_count = max(1, round(len(approved) * 0.2))
    train_end = min(train_end, len(approved) - 2)
    val_end = min(len(approved) - 1, train_end + val_count)

    return {
        "train": approved[:train_end],
        "val": approved[train_end:val_end],
        "test": approved[val_end:],
    }


def write_yolo_label(path, class_id, values):
    with path.open("w", encoding="utf-8") as file:
        file.write(str(class_id) + " " + " ".join(str(value) for value in values) + "\n")


def export_master_dataset():
    dataset = load_master_dataset()
    splits = split_dataset_items(dataset["items"])
    export_name = "yolo_dataset_" + datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    export_dir = MASTER_DIR / "exports" / export_name
    class_names = dataset.get("class_names") or APP_CLASS_NAMES

    for dataset_type in ("detection", "segmentation"):
        for split_name in ("train", "val", "test"):
            (export_dir / dataset_type / "images" / split_name).mkdir(parents=True, exist_ok=True)
            (export_dir / dataset_type / "labels" / split_name).mkdir(parents=True, exist_ok=True)

    for split_name in ("train", "val", "test"):
        (export_dir / "masks" / split_name).mkdir(parents=True, exist_ok=True)

    for split_name, frames in splits.items():
        for item in frames:
            image_source = MASTER_IMAGES_DIR / item["image"]
            mask_source = MASTER_MASKS_DIR / item["mask"]
            label_name = Path(item["image"]).with_suffix(".txt").name
            class_name = item["class_name"]
            class_id = class_names.index(class_name) if class_name in class_names else 0

            for dataset_type in ("detection", "segmentation"):
                shutil.copy2(image_source, export_dir / dataset_type / "images" / split_name / item["image"])

            shutil.copy2(mask_source, export_dir / "masks" / split_name / item["mask"])
            write_yolo_label(
                export_dir / "detection" / "labels" / split_name / label_name,
                class_id,
                item["bbox"]["normalized"],
            )
            write_yolo_label(
                export_dir / "segmentation" / "labels" / split_name / label_name,
                class_id,
                item["polygon_normalized"],
            )

    for dataset_type in ("detection", "segmentation"):
        data = {
            "path": str((export_dir / dataset_type).resolve()),
            "train": "images/train",
            "val": "images/val",
            "test": "images/test",
            "names": {index: name for index, name in enumerate(class_names)},
        }
        with (export_dir / f"data_{dataset_type}.yaml").open("w", encoding="utf-8") as file:
            yaml.safe_dump(data, file, sort_keys=False)

    summary = {
        "name": export_name,
        "created_at": utc_now(),
        "path": str(export_dir.resolve()),
        "source": "master_dataset",
        "total_items": len(dataset["items"]),
        "counts": {split_name: len(frames) for split_name, frames in splits.items()},
    }
    with (export_dir / "export_summary.json").open("w", encoding="utf-8") as file:
        json.dump(summary, file, indent=2)

    dataset.setdefault("exports", []).append(summary)
    save_master_dataset(dataset)
    return summary


def clear_source_projects():
    removed_projects = PROJECTS_DIR.exists()
    removed_uploads = UPLOADS_DIR.exists()
    shutil.rmtree(PROJECTS_DIR, ignore_errors=True)
    shutil.rmtree(UPLOADS_DIR, ignore_errors=True)
    PROJECTS_DIR.mkdir(parents=True, exist_ok=True)
    UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    return {
        "removed_projects": removed_projects,
        "removed_uploads": removed_uploads,
        "master_summary": master_summary(),
    }


@app.route("/")
def index():
    return render_template("index.html", projects=list_projects(), active_project=None)


@app.route("/project/<project_id>")
def project_view(project_id):
    return render_template("index.html", projects=list_projects(), active_project=load_project(project_id))


@app.route("/projects", methods=["POST"])
def create_project():
    video = request.files.get("video")
    if not video or not video.filename:
        return redirect(url_for("index"))

    if not allowed_video(video.filename):
        return redirect(url_for("index"))

    project_id = uuid.uuid4().hex[:12]
    clean_name = secure_filename(video.filename)
    upload_dir = UPLOADS_DIR / project_id
    upload_dir.mkdir(parents=True, exist_ok=True)
    video_path = upload_dir / clean_name
    video.save(video_path)

    class_name = request.form.get("class_name", "plane_drone").strip() or "plane_drone"
    if class_name not in APP_CLASS_NAMES:
        class_name = "plane_drone"
    sample_fps = float(request.form.get("sample_fps", 4) or 4)
    min_area = int(request.form.get("min_area", 20) or 20)
    max_area_ratio = float(request.form.get("max_area_ratio", 0.04) or 0.04)

    project = {
        "id": project_id,
        "name": Path(clean_name).stem,
        "video_filename": clean_name,
        "video_path": str(video_path.resolve()),
        "class_name": class_name,
        "class_names": APP_CLASS_NAMES,
        "status": "processing",
        "created_at": utc_now(),
        "updated_at": utc_now(),
        "frames": [],
        "exports": [],
    }
    save_project(project)
    process_video(project, sample_fps, min_area, max_area_ratio)
    return redirect(url_for("project_view", project_id=project_id))


@app.route("/api/project/<project_id>")
def project_api(project_id):
    project = load_project(project_id)
    project["master_summary"] = master_summary()
    return jsonify(project)


@app.route("/api/project/<project_id>/frame/<frame_id>/decision", methods=["POST"])
def frame_decision(project_id, frame_id):
    project = load_project(project_id)
    decision = request.get_json(force=True).get("decision")
    if decision not in {"approved", "rejected", "pending"}:
        return jsonify({"error": "Invalid decision"}), 400

    for frame in project["frames"]:
        if frame["id"] == frame_id:
            frame["decision"] = decision
            if decision == "approved":
                try:
                    upsert_master_item(project, frame)
                except ValueError as error:
                    return jsonify({"error": str(error)}), 400
            else:
                remove_master_item(project_id, frame_id)

            project["updated_at"] = utc_now()
            save_project(project)
            return jsonify({"ok": True, "frame": frame, "master_summary": master_summary()})

    return jsonify({"error": "Frame not found"}), 404


@app.route("/api/project/<project_id>/frame/<frame_id>/mask", methods=["POST"])
def frame_mask(project_id, frame_id):
    project = load_project(project_id)
    payload = request.get_json(force=True)
    points = payload.get("polygon", [])

    for frame in project["frames"]:
        if frame["id"] != frame_id:
            continue

        polygon = sanitize_polygon(points, frame["width"], frame["height"])
        label = frame_label_from_polygon(polygon, frame["width"], frame["height"])
        if label is None:
            return jsonify({"error": "Manual mask needs at least three valid points."}), 400

        frame["has_mask"] = True
        frame["bbox"] = label["bbox"]
        frame["polygon"] = label["polygon"]
        frame["polygon_normalized"] = label["polygon_normalized"]
        frame["decision"] = "pending"
        frame["mask_source"] = "manual"
        write_mask(project_dir(project_id) / "masks" / frame["mask"], frame["polygon"], frame["width"], frame["height"])
        remove_master_item(project_id, frame_id)
        project["updated_at"] = utc_now()
        save_project(project)
        return jsonify({"ok": True, "frame": frame, "master_summary": master_summary()})

    return jsonify({"error": "Frame not found"}), 404


@app.route("/api/project/<project_id>/export", methods=["POST"])
def export_api(project_id):
    project = load_project(project_id)
    for frame in project["frames"]:
        if frame["decision"] == "approved" and frame["has_mask"]:
            upsert_master_item(project, frame)

    if not load_master_dataset()["items"]:
        return jsonify({"error": "Approve at least one frame with a saved mask before export."}), 400

    summary = export_master_dataset()
    return jsonify(summary)


@app.route("/api/sources/clear", methods=["POST"])
def clear_sources_api():
    return jsonify(clear_source_projects())


@app.route("/media/<project_id>/frames/<filename>")
def media_frame(project_id, filename):
    return send_from_directory(project_dir(project_id) / "frames", filename)


@app.route("/media/<project_id>/masks/<filename>")
def media_mask(project_id, filename):
    return send_from_directory(project_dir(project_id) / "masks", filename)


if __name__ == "__main__":
    UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    PROJECTS_DIR.mkdir(parents=True, exist_ok=True)
    MASTER_DIR.mkdir(parents=True, exist_ok=True)
    app.run(host="127.0.0.1", port=5055, debug=True)
