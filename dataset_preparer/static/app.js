const root = document.querySelector(".shell");
const projectId = root?.dataset.projectId;

let project = null;
let frames = [];
let currentIndex = 0;
let drawMode = false;
let manualPolygon = [];
let canvasScale = 1;
let currentImage = null;

const canvas = document.getElementById("frame-canvas");
const ctx = canvas?.getContext("2d");
const filmstrip = document.getElementById("filmstrip");
const statusLine = document.getElementById("status-line");

function setStatus(message) {
  if (statusLine) statusLine.textContent = message || "";
}

function frameUrl(frame) {
  return `/media/${projectId}/frames/${frame.image}`;
}

function updateDrawControls() {
  document.body.classList.toggle("drawing-mask", drawMode);
  document.querySelectorAll(".draw-only").forEach((element) => {
    element.classList.toggle("hidden", !drawMode);
  });
}

function updateStats() {
  const total = frames.length;
  const approved = frames.filter((frame) => frame.decision === "approved").length;
  const rejected = frames.filter((frame) => frame.decision === "rejected").length;
  const masked = frames.filter((frame) => frame.has_mask).length;
  const masterTotal = project?.master_summary?.total || 0;

  document.getElementById("stat-total").textContent = total;
  document.getElementById("stat-approved").textContent = approved;
  document.getElementById("stat-rejected").textContent = rejected;
  document.getElementById("stat-masked").textContent = masked;
  document.getElementById("stat-master").textContent = masterTotal;
}

function drawOverlay(frame) {
  const polygon = drawMode ? manualPolygon : frame.polygon || [];

  if (polygon.length > 0) {
    ctx.beginPath();
    polygon.forEach((point, index) => {
      const x = point[0] * canvasScale;
      const y = point[1] * canvasScale;
      if (index === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });

    if (polygon.length >= 3) {
      ctx.closePath();
      ctx.fillStyle = "rgba(0, 229, 255, 0.28)";
      ctx.fill();
    }

    ctx.strokeStyle = drawMode ? "rgba(0, 229, 255, 0.98)" : "rgba(35, 255, 167, 0.95)";
    ctx.lineWidth = 2;
    ctx.stroke();
  }

  if (drawMode) {
    manualPolygon.forEach((point) => {
      ctx.beginPath();
      ctx.arc(point[0] * canvasScale, point[1] * canvasScale, 4, 0, Math.PI * 2);
      ctx.fillStyle = "rgba(255, 214, 102, 0.98)";
      ctx.fill();
      ctx.strokeStyle = "rgba(0, 0, 0, 0.8)";
      ctx.lineWidth = 1;
      ctx.stroke();
    });
    return;
  }

  if (frame.bbox) {
    ctx.strokeStyle = "rgba(255, 214, 102, 0.95)";
    ctx.lineWidth = 2;
    ctx.strokeRect(
      frame.bbox.x * canvasScale,
      frame.bbox.y * canvasScale,
      frame.bbox.width * canvasScale,
      frame.bbox.height * canvasScale
    );
  }
}

function redrawCanvas(frame) {
  if (!canvas || !ctx || !frame || !currentImage) return;

  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(currentImage, 0, 0, canvas.width, canvas.height);
  drawOverlay(frame);
}

function drawFrame(frame) {
  if (!canvas || !ctx || !frame) return;

  const image = new Image();
  const frameId = frame.id;
  image.onload = () => {
    if (frames[currentIndex]?.id !== frameId) return;

    const maxWidth = canvas.parentElement.clientWidth;
    const maxHeight = Math.max(320, window.innerHeight - 310);
    canvasScale = Math.min(maxWidth / image.width, maxHeight / image.height, 1);
    currentImage = image;

    canvas.width = Math.round(image.width * canvasScale);
    canvas.height = Math.round(image.height * canvasScale);
    redrawCanvas(frame);
  };
  image.src = frameUrl(frame);
}

function renderFilmstrip() {
  if (!filmstrip) return;
  filmstrip.innerHTML = "";

  frames.forEach((frame, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `thumb ${frame.decision} ${index === currentIndex ? "active" : ""}`;
    button.innerHTML = `
      <img src="${frameUrl(frame)}" alt="${frame.id}">
      <span>${index + 1}</span>
      <i>${frame.has_mask ? "mask" : "no mask"}</i>
    `;
    button.addEventListener("click", () => {
      currentIndex = index;
      renderCurrent();
    });
    filmstrip.appendChild(button);
  });
}

function renderCurrent() {
  const frame = frames[currentIndex];
  if (!frame) return;

  document.getElementById("frame-title").textContent = `${frame.id}`;
  document.getElementById("frame-meta").textContent =
    `time ${frame.timestamp}s | source frame ${frame.frame_index} | ${frame.decision}${frame.has_mask ? "" : " | no mask proposal"}${frame.mask_source === "manual" ? " | manual mask" : ""}`;

  drawFrame(frame);
  renderFilmstrip();
  updateStats();
  updateDrawControls();
}

async function setDecision(decision) {
  if (drawMode) {
    setStatus("Save or cancel the manual mask before changing this frame.");
    return;
  }

  const frame = frames[currentIndex];
  if (!frame) return;

  const response = await fetch(`/api/project/${projectId}/frame/${frame.id}/decision`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ decision }),
  });

  if (!response.ok) {
    const payload = await response.json();
    setStatus(payload.error || "Could not update frame decision.");
    return;
  }

  const payload = await response.json();
  frames[currentIndex] = payload.frame;
  if (payload.master_summary) project.master_summary = payload.master_summary;
  setStatus(decision === "approved" ? `${frame.id} added to the master dataset.` : `${frame.id} marked ${decision}.`);

  if (decision !== "pending" && currentIndex < frames.length - 1) {
    currentIndex += 1;
  }
  renderCurrent();
}

function startDrawMode() {
  const frame = frames[currentIndex];
  if (!frame) return;

  drawMode = true;
  manualPolygon = [];
  setStatus("Manual mask mode. Click around the drone outline, then save the mask.");
  updateDrawControls();
  redrawCanvas(frame);
}

function cancelDrawMode() {
  const frame = frames[currentIndex];
  drawMode = false;
  manualPolygon = [];
  setStatus("Manual mask cancelled.");
  updateDrawControls();
  redrawCanvas(frame);
}

function undoPoint() {
  if (!drawMode || manualPolygon.length === 0) return;
  manualPolygon.pop();
  setStatus(`${manualPolygon.length} mask points.`);
  redrawCanvas(frames[currentIndex]);
}

function canvasPointFromEvent(event) {
  const rect = canvas.getBoundingClientRect();
  const canvasX = (event.clientX - rect.left) * (canvas.width / rect.width);
  const canvasY = (event.clientY - rect.top) * (canvas.height / rect.height);
  const originalX = Math.round(canvasX / canvasScale);
  const originalY = Math.round(canvasY / canvasScale);
  const frame = frames[currentIndex];

  return [
    Math.max(0, Math.min(frame.width - 1, originalX)),
    Math.max(0, Math.min(frame.height - 1, originalY)),
  ];
}

function addManualPoint(event) {
  if (!drawMode || !canvas || !frames[currentIndex]) return;
  manualPolygon.push(canvasPointFromEvent(event));
  setStatus(`${manualPolygon.length} mask points.`);
  redrawCanvas(frames[currentIndex]);
}

async function saveManualMask() {
  const frame = frames[currentIndex];
  if (!drawMode || !frame) return;

  if (manualPolygon.length < 3) {
    setStatus("Manual mask needs at least three points.");
    return;
  }

  const response = await fetch(`/api/project/${projectId}/frame/${frame.id}/mask`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ polygon: manualPolygon }),
  });
  const payload = await response.json();

  if (!response.ok) {
    setStatus(payload.error || "Could not save manual mask.");
    return;
  }

  frames[currentIndex] = payload.frame;
  if (payload.master_summary) project.master_summary = payload.master_summary;
  drawMode = false;
  manualPolygon = [];
  setStatus(`${frame.id} manual mask saved. Approve it when the mask is correct.`);
  renderCurrent();
}

async function exportDataset() {
  if (drawMode) {
    setStatus("Save or cancel the manual mask before export.");
    return;
  }

  setStatus("Building YOLO dataset from all approved frames in the master dataset...");
  const response = await fetch(`/api/project/${projectId}/export`, { method: "POST" });
  const payload = await response.json();

  if (!response.ok) {
    setStatus(payload.error || "Dataset export failed.");
    return;
  }

  if (payload.total_items !== undefined) {
    project.master_summary = { ...(project.master_summary || {}), total: payload.total_items };
  }
  updateStats();
  setStatus(`Export ready: ${payload.path} | total ${payload.total_items}, train ${payload.counts.train}, val ${payload.counts.val}, test ${payload.counts.test}`);
}

function bindControls() {
  document.getElementById("prev-frame")?.addEventListener("click", () => {
    if (drawMode) return setStatus("Save or cancel the manual mask before changing frames.");
    currentIndex = Math.max(0, currentIndex - 1);
    renderCurrent();
  });
  document.getElementById("next-frame")?.addEventListener("click", () => {
    if (drawMode) return setStatus("Save or cancel the manual mask before changing frames.");
    currentIndex = Math.min(frames.length - 1, currentIndex + 1);
    renderCurrent();
  });
  document.getElementById("draw-mask")?.addEventListener("click", startDrawMode);
  document.getElementById("undo-point")?.addEventListener("click", undoPoint);
  document.getElementById("save-mask")?.addEventListener("click", saveManualMask);
  document.getElementById("cancel-mask")?.addEventListener("click", cancelDrawMode);
  document.getElementById("approve-frame")?.addEventListener("click", () => setDecision("approved"));
  document.getElementById("reject-frame")?.addEventListener("click", () => setDecision("rejected"));
  document.getElementById("pending-frame")?.addEventListener("click", () => setDecision("pending"));
  document.getElementById("export-dataset")?.addEventListener("click", exportDataset);
  canvas?.addEventListener("click", addManualPoint);

  window.addEventListener("keydown", (event) => {
    if (!projectId) return;
    if (drawMode && event.key === "Escape") return cancelDrawMode();
    if (drawMode && (event.key === "Backspace" || event.key === "Delete")) return undoPoint();
    if (drawMode && (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
      event.preventDefault();
      return saveManualMask();
    }
    if (drawMode) return;

    if (event.key === "ArrowLeft") {
      currentIndex = Math.max(0, currentIndex - 1);
      renderCurrent();
    }
    if (event.key === "ArrowRight") {
      currentIndex = Math.min(frames.length - 1, currentIndex + 1);
      renderCurrent();
    }
    if (event.key.toLowerCase() === "a") setDecision("approved");
    if (event.key.toLowerCase() === "r") setDecision("rejected");
  });

  window.addEventListener("resize", renderCurrent);
}

async function loadProject() {
  if (!projectId) return;
  const response = await fetch(`/api/project/${projectId}`);
  project = await response.json();
  frames = project.frames || [];
  const firstPending = frames.findIndex((frame) => frame.decision === "pending");
  currentIndex = firstPending >= 0 ? firstPending : 0;
  renderCurrent();
}

bindControls();
loadProject();
