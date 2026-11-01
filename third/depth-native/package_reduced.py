"""Package the native SDK and measure size; this does not run inference."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def measure(path, compressed):
    digest = hashlib.sha256()
    with path.open("rb") as source, gzip.open(compressed, "wb", compresslevel=9) as target:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
            target.write(chunk)
    return {"bytes": path.stat().st_size, "gzip_bytes": compressed.stat().st_size, "sha256": digest.hexdigest()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("work", type=Path)
    args = parser.parse_args()
    work = args.work.resolve()
    reduced = work / "ort-reduced-1.31.0"
    original = work / "onnxruntime-osx-arm64-1.31.0"
    name = "libonnxruntime.1.31.0.dylib"
    built = reduced / "build/MinSizeRel" / name
    if not built.is_file():
        raise FileNotFoundError("The reduced runtime must finish building before packaging")
    dist = reduced / "dist"
    (dist / "lib").mkdir(parents=True, exist_ok=True)
    shutil.copytree(original / "include", dist / "include", dirs_exist_ok=True)
    for license in ["LICENSE", "ThirdPartyNotices.txt"]:
        shutil.copyfile(original / license, dist / license)
    library = dist / "lib" / name
    shutil.copyfile(built, library)
    subprocess.run(["/usr/bin/strip", "-x", str(library)], check=True)
    subprocess.run(["/usr/bin/install_name_tool", "-id", "@rpath/" + name, str(library)], check=True)
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(library)], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(library)], check=True)
    link = dist / "lib/libonnxruntime.dylib"
    if not link.exists():
        link.symlink_to(name)
    dependencies = subprocess.check_output(["/usr/bin/otool", "-L", str(library)], text=True)
    for line in dependencies.splitlines()[1:]:
        path = line.strip().split(" (")[0]
        if path != "@rpath/" + name and not path.startswith(("/usr/lib/", "/System/Library/")):
            raise RuntimeError(f"Unexpected non-system dependency: {path}")
    (reduced / "dependencies.txt").write_text(dependencies)
    stripped = reduced / "reference-stripped.dylib"
    shutil.copyfile(original / "lib" / name, stripped)
    subprocess.run(["/usr/bin/strip", "-x", str(stripped)], check=True)
    report = {
        "platform": "macOS arm64", "onnxruntime": "1.31.0",
        "full": measure(original / "lib" / name, reduced / "full.dylib.gz"),
        "full_stripped": measure(stripped, reduced / "full-stripped.dylib.gz"),
        "reduced_unstripped_bytes": built.stat().st_size,
        "reduced": measure(library, reduced / "reduced.dylib.gz"),
        "preserved": ["ONNX model loading", "CPU", "C/C++ API", "exceptions"],
        "inference_verified": False,
    }
    report["reduction_percent"] = 100 * (1 - report["reduced"]["bytes"] / report["full"]["bytes"])
    (reduced / "size-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
