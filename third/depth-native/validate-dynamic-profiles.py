"""Run profile checks serially, each inference in a memory-bounded process."""
import argparse
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("profiles", nargs="*", default=["504x280", "280x504", "280x280", "448x252", "266x154", "420x280"])
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
tools = root / "third/depth-native"
work = root / "build/depth-native"
python = work / "venv/bin/python"
for profile in args.profiles:
    width, height = profile.split("x")
    for mode in ["prepare", "reference", "onnx", "compare"]:
        command = [str(python), str(tools / "dynamic-validate.py"), mode, width, height]
        if mode in ("reference", "onnx"):
            command = [sys.executable, str(tools / "bounded-run.py"),
                       str(work / "dynamic" / profile / f"{mode}.log"), *command]
        print(profile, mode, flush=True)
        subprocess.run(command, check=True)
