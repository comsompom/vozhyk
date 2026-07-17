# Drone Dataset Preparer

Standalone Flask application for preparing YOLO-ready `plane_drone` datasets from video.

## Features

- Upload a drone video.
- Extract sampled frames.
- Generate automatic mask and bounding-box proposals with OpenCV motion/contour analysis.
- Review every candidate frame with the mask overlay.
- Zoom the review image for precise manual mask drawing.
- Approve or reject frames.
- Replace any automatic mask with a manually drawn polygon mask.
- Add approved frames into one persistent master dataset across multiple videos.
- Export the full master dataset into YOLO-ready detection and segmentation datasets.
- Clear uploaded videos and per-project frame sources after building the master dataset.
- Preserve the iPhone app's current class order, where `plane_drone` is class ID `3`.

## Main Settings

- `Video file`: one source video to split into review frames.
- `Class name`: use `plane_drone` for the current iPhone model flow.
- `Sample FPS`: number of images extracted per second of video. Use `2-5` for most drone videos.
- `Min mask area`: smallest automatic motion region accepted as a drone proposal. Lower it for very far drones; raise it to reject tiny noise.
- `Max object area ratio`: largest proposal size as a fraction of the image. Keep near `0.02-0.06` for small flying objects.

## Run

```bash
lsof -nP -iTCP:5055 -sTCP:LISTEN
cd dataset_preparer
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

Open:

```text
http://127.0.0.1:5055
```

## Output

Exports are written under:

```text
dataset_preparer/workspace/master_dataset/exports/<export_name>/
```

Approved source frames and masks are accumulated under:

```text
dataset_preparer/workspace/master_dataset/
```

Each export contains:

- `detection/` with YOLO bounding-box labels.
- `segmentation/` with YOLO polygon labels.
- `masks/` with binary mask PNG files.
- `data_detection.yaml`
- `data_segmentation.yaml`

The automatic masks are proposals. Inspect them carefully before approving frames.

Approving a frame adds or updates it in the master dataset immediately. Changing an approved frame back to pending/rejected, or replacing its mask manually, removes the stale copy until you approve it again.

Zoom affects only the browser review view. Manual mask points are converted back to original image coordinates before saving, so exported masks and YOLO labels stay aligned with the normal image size.

After `Build Master Dataset` succeeds, `Clear Source Projects` removes `workspace/projects` and `workspace/uploads` while keeping `workspace/master_dataset`.
