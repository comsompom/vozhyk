# Drone Model Improvements

## Current State

The project now has a custom Core ML object detection model trained to detect the uploaded flying fixed-wing object as `plane_drone`, shown in the app UI as `Plane Drone`.

The app build uses:

- Model: `iphone_detector/DroneDetector/Models/DroneDetector.mlpackage`
- Preserved COCO fallback model: `iphone_detector/DroneDetector/Models/YOLOv8n.mlpackage`
- Dataset: `iphone_detector/datasets/drone_video_draft/data.yaml`
- Training run: `iphone_detector/runs/drone_detector-2`
- Source videos: `video_sources/*.mp4`

The dataset, training run, export cache, and original uploaded video sources were removed after training to recover local disk space. The trained Core ML app model was kept.

Important: the custom `DroneDetector.mlpackage` was trained only from `plane_drone` draft labels. It includes metadata slots for `auto`, `plane`, `drone`, `bird`, `human`, `bus`, `truck`, and `motorcycle`, but those classes were not meaningfully trained in the first pass. To preserve the previously strong detections for `auto`, `truck`, `plane`, `human`, and the other retained COCO classes, the app intentionally runs the bundled `YOLOv8n.mlpackage` alongside the custom model.

## Implemented App Changes

- Added a new detectable object type:
  - Raw value: `plane_drone`
  - Swift case: `planeDrone`
  - UI title: `Plane Drone`
- Added `Plane Drone` to settings so it can be enabled/disabled and assigned a border color.
- Updated label mapping in `DroneVisionDetector.swift` so these model labels map to `Plane Drone`:
  - `plane_drone`
  - `plane drone`
  - `fixed-wing drone`
  - `fixed wing drone`
- Added a fallback class-name mapping for custom 9-class models. This protects the app if Core ML metadata is missing.
- Updated the training export script so future Core ML exports include the dataset class mapping in model metadata.
- Updated the app detector to run two Core ML pipelines:
  - `DroneDetector.mlpackage` for the new `Plane Drone` class.
  - `YOLOv8n.mlpackage` for the previously good COCO classes such as `auto`, `truck`, `plane`, and `human`.
- Added both mlpackages to the Xcode target so they are available in the app bundle.
- Scoped the custom model so it can only contribute drone-like detections. Normal object classes stay owned by the original YOLOv8n model.
- Kept the multi-frame confirmation gate only for `Drone` and `Plane Drone`. Reliable main-model objects such as `Auto`, `Truck`, `Plane`, and `Human` are published immediately.
- Added overlap deduplication so a custom `Plane Drone` detection wins over a generic overlapping `Plane` detection, while unrelated classes like `Auto` and `Human` are not suppressed.

## Dataset Creation

Uploaded videos were placed in:

```text
video_sources/
```

There were 12 MP4 files. A YOLO-format dataset was created at:

```text
iphone_detector/datasets/drone_video_draft/
```

Initial frame extraction was done with:

```sh
iphone_detector/.venv/bin/python iphone_detector/scripts/prepare_video_dataset.py \
  --source /Users/olegbourdo/Development/vozhyk/video_sources \
  --output iphone_detector/datasets/drone_video_draft \
  --class-name drone \
  --sample-every 0.5 \
  --max-frames-per-video 120 \
  --min-area 8 \
  --preview-count 48
```

The motion-based labels from this first pass were too noisy and were not used for training directly.

YOLO-World was then used for better draft auto-labeling:

```sh
iphone_detector/.venv/bin/python iphone_detector/scripts/auto_label_yolo_world.py \
  --dataset iphone_detector/datasets/drone_video_draft \
  --model iphone_detector/.model_export/yolov8s-world.pt \
  --imgsz 640 \
  --conf 0.05 \
  --progress-every 100 \
  --preview-count 48
```

The draft labels were remapped so aircraft-like detections became `plane_drone`. Ground-object false positives were mostly dropped. Final draft label summary:

- 616 images total
- 493 train images
- 123 validation images
- 480 labeled images
- 136 empty negative label files
- 512 `plane_drone` boxes

Final dataset class order:

```yaml
0: auto
1: plane
2: drone
3: plane_drone
4: bird
5: human
6: bus
7: truck
8: motorcycle
```

Useful preview files:

```text
iphone_detector/datasets/drone_video_draft/previews/yolo_world_sheet.jpg
iphone_detector/datasets/drone_video_draft/previews/plane_drone_sheet.jpg
```

## Training

MPS was not available in the Python environment:

```text
mps_available False
mps_built True
```

Training was done on CPU, so a short first-pass run was used:

```sh
iphone_detector/.venv/bin/python iphone_detector/scripts/train_drone_model.py \
  --data iphone_detector/datasets/drone_video_draft/data.yaml \
  --model iphone_detector/scripts/yolov8n.pt \
  --imgsz 416 \
  --epochs 5 \
  --batch 16 \
  --device cpu
```

Training output:

```text
iphone_detector/runs/drone_detector-2/
```

Final validation metrics from epoch 5:

```text
Precision: 0.802
Recall:    0.849
mAP50:     0.873
mAP50-95:  0.536
```

The trained PyTorch model was:

```text
iphone_detector/runs/drone_detector-2/weights/best.pt
```

The exported Core ML model was saved into the app at:

```text
iphone_detector/DroneDetector/Models/DroneDetector.mlpackage
```

Core ML metadata was verified to include:

```text
{0: 'auto', 1: 'plane', 2: 'drone', 3: 'plane_drone', 4: 'bird', 5: 'human', 6: 'bus', 7: 'truck', 8: 'motorcycle'}
```

Core ML model outputs were verified as:

```text
confidence
coordinates
```

These are the outputs expected by the app's Vision parser.

## Verification

The iOS app was built successfully with the trained model:

```sh
xcodebuild -project iphone_detector/DroneDetector.xcodeproj \
  -scheme DroneDetector \
  -configuration Debug \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/DroneDetectorDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Result:

```text
BUILD SUCCEEDED
```

A local Core ML sanity prediction returned class `3`, which is `plane_drone`.

## Known Limitations

- The dataset labels are still draft labels generated by auto-labeling, not fully manual annotations.
- Some false positives were visible in preview sheets, especially around people or ground objects near the horizon.
- The model was trained for only 5 epochs at 416 image size because the local Python environment had no MPS acceleration.
- The model is likely specialized to the uploaded fixed-wing flying object and similar sky/field footage.
- More manually reviewed labels and more diverse videos are needed before treating the model as robust.

## Recommended Next Improvements

- Manually clean labels in `iphone_detector/datasets/drone_video_draft`.
- Add more footage with:
  - Different sky/cloud conditions
  - Different distances
  - Different camera zoom levels
  - More backgrounds
  - More negative frames without flying objects
- Train longer on GPU/MPS-capable environment.
- Try `imgsz=640` or `imgsz=960` after label cleanup for better small-object detection.
- Run validation on videos not used for training.
- Consider class-specific datasets for `drone`, `plane`, and `plane_drone` so these classes do not collapse into one another.

## Future Agent Runbook

Use this process when improving the model from new video sources.

### 1. Add Video Sources

Place new videos in:

```text
video_sources/
```

Prefer original video files, not screen recordings or heavily compressed exports. Keep useful source naming, for example:

```text
video_sources/plane_drone_001.mp4
video_sources/negative_sky_001.mp4
video_sources/bird_001.mp4
```

Before processing, inspect videos:

```sh
find video_sources -maxdepth 1 -type f -name '*.mp4' \
  -exec ffprobe -v error \
  -select_streams v:0 \
  -show_entries format=filename,duration,size \
  -show_entries stream=width,height,avg_frame_rate \
  -of default=noprint_wrappers=1 {} \;
```

### 2. Extract Draft Dataset Frames

Use the dataset prep script:

```sh
iphone_detector/.venv/bin/python iphone_detector/scripts/prepare_video_dataset.py \
  --source /Users/olegbourdo/Development/vozhyk/video_sources \
  --output iphone_detector/datasets/drone_video_draft \
  --class-name plane_drone \
  --sample-every 0.5 \
  --max-frames-per-video 120 \
  --min-area 8 \
  --preview-count 48
```

Notes:

- This creates YOLO folders under `images/train`, `images/val`, `labels/train`, and `labels/val`.
- The motion-generated labels are only a rough bootstrap and are usually noisy.
- Do not train directly from motion labels unless the preview proves they are clean.

Check preview:

```text
iphone_detector/datasets/drone_video_draft/previews/draft_sheet.jpg
```

### 3. Auto-Label With YOLO-World

Use YOLO-World for better draft labels:

```sh
iphone_detector/.venv/bin/python iphone_detector/scripts/auto_label_yolo_world.py \
  --dataset iphone_detector/datasets/drone_video_draft \
  --model iphone_detector/.model_export/yolov8s-world.pt \
  --imgsz 640 \
  --conf 0.05 \
  --progress-every 100 \
  --preview-count 48
```

If testing first, limit the run:

```sh
iphone_detector/.venv/bin/python iphone_detector/scripts/auto_label_yolo_world.py \
  --dataset iphone_detector/datasets/drone_video_draft \
  --model iphone_detector/.model_export/yolov8s-world.pt \
  --imgsz 640 \
  --conf 0.05 \
  --max-images 96 \
  --progress-every 16 \
  --preview-count 48
```

Check preview:

```text
iphone_detector/datasets/drone_video_draft/previews/yolo_world_sheet.jpg
```

### 4. Remap Aircraft-Like Labels To `plane_drone`

If the footage is a fixed-wing drone-like aircraft and should be trained as `Plane Drone`, remap labels so the final YOLO class is `3`, which is `plane_drone`.

Current class order:

```yaml
0: auto
1: plane
2: drone
3: plane_drone
4: bird
5: human
6: bus
7: truck
8: motorcycle
```

Use this one-off remap pattern if needed:

```sh
iphone_detector/.venv/bin/python - <<'PY'
from pathlib import Path

root = Path('iphone_detector/datasets/drone_video_draft')
convert_to_plane_drone = {1, 2, 3, 4}
plane_drone_index = 3

def iou(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    ax1, ay1, ax2, ay2 = ax - aw / 2, ay - ah / 2, ax + aw / 2, ay + ah / 2
    bx1, by1, bx2, by2 = bx - bw / 2, by - bh / 2, bx + bw / 2, by + bh / 2
    x1, y1 = max(ax1, bx1), max(ay1, by1)
    x2, y2 = min(ax2, bx2), min(ay2, by2)
    intersection = max(0, x2 - x1) * max(0, y2 - y1)
    union = aw * ah + bw * bh - intersection
    return intersection / union if union else 0

converted_images = 0
converted_boxes = 0

for label_path in sorted((root / 'labels').glob('*/*.txt')):
    boxes = []
    for line in label_path.read_text(encoding='utf-8').splitlines():
        parts = line.split()
        if len(parts) != 5:
            continue
        old_class = int(float(parts[0]))
        if old_class not in convert_to_plane_drone:
            continue
        box = tuple(float(value) for value in parts[1:])
        if any(iou(box, kept) > 0.45 for kept in boxes):
            continue
        boxes.append(box)

    rows = [f"{plane_drone_index} {' '.join(f'{value:.6f}' for value in box)}" for box in boxes]
    label_path.write_text('\n'.join(rows) + ('\n' if rows else ''), encoding='utf-8')
    if boxes:
        converted_images += 1
        converted_boxes += len(boxes)

names = ['auto', 'plane', 'drone', 'plane_drone', 'bird', 'human', 'bus', 'truck', 'motorcycle']
(root / 'data.yaml').write_text(
    f"path: {root.resolve()}\n"
    "train: images/train\n"
    "val: images/val\n"
    "names:\n" + ''.join(f"  {index}: {name}\n" for index, name in enumerate(names)),
    encoding='utf-8',
)

print(f"converted_images={converted_images}")
print(f"converted_boxes={converted_boxes}")
PY
```

### 5. Review Labels Before Training

Do not skip this for serious model improvements.

Open preview sheets and inspect:

```text
iphone_detector/datasets/drone_video_draft/previews/*.jpg
```

Look for:

- Boxes not covering the flying object.
- Boxes on people, buildings, horizon, trees, clouds, or grass.
- Duplicate boxes on one object.
- Missing objects.
- Incorrect class IDs.

For a higher-quality model, manually edit YOLO labels with a labeling tool such as CVAT, Label Studio, Roboflow, or any local YOLO label editor.

### 6. Check Dataset Counts

Before training:

```sh
find iphone_detector/datasets/drone_video_draft/images/train -type f | wc -l
find iphone_detector/datasets/drone_video_draft/images/val -type f | wc -l
find iphone_detector/datasets/drone_video_draft/labels -name '*.txt' \
  -exec awk '{count[$1]++} END {for (class in count) print class, count[class]}' {} + | sort -n
```

Expected for the current first-pass dataset:

```text
493 train images
123 val images
class 3 only, where 3 = plane_drone
```

### 7. Train

Check acceleration first:

```sh
iphone_detector/.venv/bin/python - <<'PY'
import torch
print('torch', torch.__version__)
print('mps_available', torch.backends.mps.is_available())
print('mps_built', torch.backends.mps.is_built())
PY
```

CPU first-pass command:

```sh
iphone_detector/.venv/bin/python iphone_detector/scripts/train_drone_model.py \
  --data iphone_detector/datasets/drone_video_draft/data.yaml \
  --model iphone_detector/scripts/yolov8n.pt \
  --imgsz 416 \
  --epochs 5 \
  --batch 16 \
  --device cpu
```

Better GPU/MPS training command after label cleanup:

```sh
iphone_detector/.venv/bin/python iphone_detector/scripts/train_drone_model.py \
  --data iphone_detector/datasets/drone_video_draft/data.yaml \
  --model iphone_detector/scripts/yolov8n.pt \
  --imgsz 640 \
  --epochs 50 \
  --batch 8 \
  --device mps
```

Use `--device 0` on CUDA machines.

### 8. Confirm Exported Model

Training script should export to:

```text
iphone_detector/DroneDetector/Models/DroneDetector.mlpackage
```

Verify Core ML metadata and outputs:

```sh
iphone_detector/.venv/bin/python - <<'PY'
import coremltools as ct
m = ct.models.MLModel('iphone_detector/DroneDetector/Models/DroneDetector.mlpackage', skip_model_load=True)
spec = m.get_spec()
print('outputs:', [o.name for o in spec.description.output])
print('classes:', m.user_defined_metadata.get('classes'))
PY
```

Expected outputs:

```text
confidence
coordinates
```

Expected classes include:

```text
3: 'plane_drone'
```

### 9. Sanity Predict

Run a local prediction on a known validation image:

```sh
iphone_detector/.venv/bin/yolo predict \
  model=iphone_detector/DroneDetector/Models/DroneDetector.mlpackage \
  source=iphone_detector/datasets/drone_video_draft/images/val/03_001755.jpg \
  imgsz=416 \
  conf=0.25 \
  save_txt=True \
  save_conf=True \
  project=/private/tmp/vozhyk_model_check \
  name=plane_drone_coreml \
  exist_ok=True
```

Expected label output should start with class `3`:

```text
3 ...
```

### 10. Build The iOS App

Build after replacing the model:

```sh
xcodebuild -project iphone_detector/DroneDetector.xcodeproj \
  -scheme DroneDetector \
  -configuration Debug \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/DroneDetectorDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
BUILD SUCCEEDED
```

### 11. App-Side Checks

After installing/running the app:

- Confirm `Plane Drone` appears in Settings.
- Confirm `Plane Drone` can be enabled/disabled.
- Confirm border color can be changed.
- Confirm detections show the label `Plane Drone`.
- Confirm disabling `Plane Drone` suppresses detections of that class.

### 12. What To Preserve

For every future model iteration, keep:

- Source videos or a list of source videos.
- Dataset YAML.
- Preview sheets.
- Training command.
- Training run directory.
- Final validation metrics.
- Exported Core ML package.
- Any manual label cleanup notes.
