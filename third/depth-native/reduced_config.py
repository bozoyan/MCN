"""Derive a reduced ORT operator set, including operators introduced by optimization."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

import onnxruntime as ort


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if ort.__version__ != "1.31.0":
        raise ValueError("Configuration generation must match ONNX Runtime 1.31.0")
    output = args.output.resolve()
    models = output / "config-models"
    models.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.model, models / "original.onnx")
    # Runtime optimizers can introduce fused operators absent from the source
    # graph. Include both graphs so CPU fallback retains those kernels too.
    options = ort.SessionOptions()
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    options.optimized_model_filepath = str(models / "optimized.onnx")
    options.intra_op_num_threads = 4
    session = ort.InferenceSession(str(args.model.resolve()), options, providers=["CPUExecutionProvider"])
    del session
    config = output / "required_operators.config"
    subprocess.run([
        sys.executable, str(args.source.resolve() / "tools/python/create_reduced_build_config.py"),
        str(models), str(config),
    ], check=True)
    data = args.model.read_bytes()
    manifest = {
        "onnxruntime": ort.__version__,
        "source_commit": "402979ac1bef89dcd55add41eaa7277c407599eb",
        "model_sha256": hashlib.sha256(data).hexdigest(),
        "model_bytes": len(data),
        "operator_config": config.read_text(),
    }
    (output / "config-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(config.read_text())


if __name__ == "__main__":
    main()
