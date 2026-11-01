"""Compare matched full-buffer/streaming runs without loading their outputs."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            result.update(chunk)
    return result.hexdigest()


def read_run(path):
    log = (path / "run.log").read_text()
    rows = [json.loads(line) for line in log.splitlines() if line.startswith('{"frames":')]
    if len(rows) != 1:
        raise ValueError(f"Run did not finish exactly once: {path.name}")
    row = rows[0]
    for label in ["maximum resident set size", "peak memory footprint"]:
        match = re.search(r"(\d+)\s+" + label, log)
        if not match:
            raise ValueError(f"Missing memory measurement: {path.name}")
        row[label.replace(" ", "_")] = int(match[1])
    for name, bytes_per_value in [("native.f32", 4), ("native.gray", 1)]:
        file = path / name
        if file.stat().st_size != row["frames"] * 448 * 252 * bytes_per_value:
            raise ValueError(f"Wrong output size: {path.name}/{name}")
        row[name + "_sha256"] = digest(file)
    return row


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("work", type=Path)
    args = parser.parse_args()
    runs = {name: read_run(args.work / name) for name in
            ["baseline-6", "baseline-30", "stream-6", "stream-30"]}
    checks = {}
    for length in [6, 30]:
        before, after = runs[f"baseline-{length}"], runs[f"stream-{length}"]
        checks[str(length)] = {
            "float_bytes_identical": before["native.f32_sha256"] == after["native.f32_sha256"],
            "gray_bytes_identical": before["native.gray_sha256"] == after["native.gray_sha256"],
            "peak_reduction_bytes": before["peak_memory_footprint"] - after["peak_memory_footprint"],
        }
    report = {
        "provider": "CoreML ALL, warm disk cache, separate processes, no ORT profiler",
        "input": "Same 30-second source: first 144 frames versus all 720 frames, 448x252 at 24 fps",
        "runs": runs,
        "checks": checks,
        "baseline_growth_bytes": runs["baseline-30"]["peak_memory_footprint"] - runs["baseline-6"]["peak_memory_footprint"],
        "stream_growth_bytes": runs["stream-30"]["peak_memory_footprint"] - runs["stream-6"]["peak_memory_footprint"],
    }
    (args.work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if not all(check["float_bytes_identical"] and check["gray_bytes_identical"] for check in checks.values()):
        raise SystemExit("Streaming output changed relative to the baseline")


if __name__ == "__main__":
    main()
