"""Validate one dynamic profile against the unmodified upstream PyTorch model."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import sys

import numpy as np

WORK = Path(__file__).resolve().parents[2] / "build/depth-native"
parser = argparse.ArgumentParser()
parser.add_argument("mode", choices=["prepare", "reference", "onnx", "compare"])
parser.add_argument("width", type=int)
parser.add_argument("height", type=int)
args = parser.parse_args()
width, height = args.width, args.height
if min(width, height) < 14 or width % 14 or height % 14 or width * height > 504 * 280:
    raise SystemExit("Validation profile exceeds the CPU pixel budget or patch alignment")
case = WORK / "dynamic" / f"{width}x{height}"
case.mkdir(parents=True, exist_ok=True)
started = time.monotonic()
if args.mode == "prepare":
    import cv2
    # Reuse real video frames. Transpose for portrait to avoid severe distortion;
    # all engines see exactly the same resized/normalized input for each profile.
    frames = np.fromfile(WORK / "second-video/input.rgb", dtype=np.uint8,
                         count=32 * 448 * 252 * 3).reshape(32, 252, 448, 3)
    if height > width:
        frames = frames.transpose(0, 2, 1, 3)
    rgb = np.stack([cv2.resize(frame, (width, height), interpolation=cv2.INTER_CUBIC) for frame in frames])
    rgb.tofile(case / "input.rgb")
    x = rgb.astype(np.float32) / 255.0
    x = (x - np.array([.485, .456, .406], dtype=np.float32)) / np.array([.229, .224, .225], dtype=np.float32)
    np.save(case / "input.npy", np.ascontiguousarray(x.transpose(0, 3, 1, 2)[None]))
elif args.mode == "reference":
    import torch
    torch.set_num_threads(4)
    source = WORK / "Video-Depth-Anything-4f5ae23172ba60fd7bc11ef671cca678842c7072"
    sys.path.insert(0, str(source))
    from video_depth_anything.video_depth import VideoDepthAnything
    checkpoint = WORK / "video_depth_anything_vits.pth"
    if hashlib.sha256(checkpoint.read_bytes()).hexdigest() != "13379300b739e659f076a59d52e9801bd8d38c541a7e71f73bbca4dcfb013609":
        raise ValueError("Reference checkpoint checksum mismatch")
    model = VideoDepthAnything(encoder="vits", features=64, out_channels=[48, 96, 192, 384])
    model.load_state_dict(torch.load(checkpoint, map_location="cpu", weights_only=True), strict=True)
    model.eval()
    with torch.inference_mode():
        result = model(torch.from_numpy(np.load(case / "input.npy"))).numpy()
    assert result.shape == (1, 32, height, width) and np.isfinite(result).all()
    np.save(case / "reference.npy", result)
elif args.mode == "onnx":
    import onnxruntime as ort
    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(WORK / "dynamic/video-depth-anything-small-dynamic-fp32.onnx"),
                                   options, providers=["CPUExecutionProvider"])
    result, = session.run(["depth"], {"frames": np.load(case / "input.npy")})
    assert result.shape == (1, 32, height, width) and np.isfinite(result).all()
    np.save(case / "onnx.npy", result)
else:
    reference = np.load(case / "reference.npy").astype(np.float64)
    output = np.load(case / "onnx.npy").astype(np.float64)
    assert output.shape == reference.shape and np.isfinite(output).all()
    delta = output - reference
    span = float(np.percentile(reference, 98) - np.percentile(reference, 2))
    rmse = float(np.sqrt(np.mean(delta ** 2)) / max(span, 1e-8))
    correlation = float(np.corrcoef(reference.ravel(), output.ravel())[0, 1])
    report = {"width": width, "height": height, "normalized_rmse": rmse,
              "correlation": correlation, "max_absolute_error": float(np.abs(delta).max()),
              "passed": rmse < 0.001 and correlation > 0.999}
    (case / "comparison.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))
    if not report["passed"]:
        raise SystemExit("Dynamic ONNX does not match upstream")
print(json.dumps({"mode": args.mode, "seconds": time.monotonic() - started}), flush=True)
