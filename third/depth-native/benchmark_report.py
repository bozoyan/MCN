"""Summarize sequential CPU/CoreML runs, numerical error and ORT placement."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

import numpy as np


def read_run(directory):
    log = (directory / "run.log").read_text()
    summaries = [json.loads(line) for line in log.splitlines() if line.startswith('{"frames":')]
    if len(summaries) != 1:
        raise ValueError(f"Expected one completed run in {directory.name}")
    result = summaries[0]
    for label in ["maximum resident set size", "peak memory footprint"]:
        match = re.search(r"(\d+)\s+" + label, log)
        if match:
            result[label.replace(" ", "_")] = int(match[1])
    profiles = sorted(directory.glob("profile_*.json"))
    if len(profiles) != 1:
        raise ValueError(f"Expected one profile in {directory.name}; use a fresh run directory")
    events = json.loads(profiles[0].read_text())
    calls, duration = Counter(), Counter()
    for event in events:
        provider = event.get("args", {}).get("provider")
        if event.get("cat") == "Node" and provider:
            calls[provider] += 1
            duration[provider] += event.get("dur", 0)
    result["executed_provider_calls"] = dict(calls)
    result["profile_provider_seconds"] = {k: v / 1e6 for k, v in duration.items()}
    devices = Counter(re.findall(r"Device Usage: <(ML\w+ComputeDevice)", log))
    if devices:
        result["compute_plan_operations_by_device"] = dict(devices)
    return result


def compare(reference, path):
    output = np.fromfile(path, dtype=np.float32)
    if output.shape != reference.shape or not np.isfinite(output).all():
        raise ValueError(f"Invalid native output: {path}")
    delta = output.astype(np.float64) - reference
    span = float(np.percentile(reference, 98) - np.percentile(reference, 2))
    metrics = {
        "mae": float(np.abs(delta).mean()),
        "max_absolute_error": float(np.abs(delta).max()),
        "normalized_rmse": float(np.sqrt(np.mean(delta ** 2)) / max(span, 1e-8)),
        "correlation": float(np.corrcoef(reference, output)[0, 1]),
    }
    metrics["passed"] = metrics["normalized_rmse"] < 0.001 and metrics["correlation"] > 0.999
    return metrics


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("work", type=Path)
    args = parser.parse_args()
    cpu = np.fromfile(args.work / "cpu/native.f32", dtype=np.float32)
    report = {}
    for name in ["cpu", "cold", "warm"]:
        report[name] = read_run(args.work / name)
        if name != "cpu":
            report[name]["against_cpu"] = compare(cpu, args.work / name / "native.f32")
    report["warm_end_to_end_speedup"] = report["cpu"]["seconds"] / report["warm"]["seconds"]
    report["warm_inference_speedup"] = report["cpu"]["inference_seconds"] / report["warm"]["inference_seconds"]
    (args.work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if not all(report[name]["against_cpu"]["passed"] for name in ["cold", "warm"]):
        raise SystemExit("CoreML numerical comparison did not pass the existing tolerance")


if __name__ == "__main__":
    main()
