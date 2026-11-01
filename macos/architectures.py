#!/usr/bin/env python3
"""Prepare embedded frameworks for arm64 and verify macOS package architectures."""

from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile


def verify(app: Path, prepare=False):
    if not (app / "Contents/MacOS").is_dir():
        raise SystemExit(f"Not a macOS app bundle: {app}")
    # Mach-O and universal headers, in both byte orders.
    magic = {bytes.fromhex(value) for value in (
        "feedface", "cefaedfe", "feedfacf", "cffaedfe",
        "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
    )}
    count = 0
    frameworks = app / "Contents/Frameworks"
    changed_frameworks = set()
    identity = os.environ.get("EXPANDED_CODE_SIGN_IDENTITY") or "-"

    def sign(path):
        subprocess.run([
            "codesign", "--force", "--sign", identity,
            "--preserve-metadata=identifier,entitlements,flags,runtime", str(path),
        ], check=True)

    for binary in app.rglob("*"):
        if binary.is_symlink() or not binary.is_file():
            continue
        with binary.open("rb") as source:
            if source.read(4) not in magic:
                continue
        architectures = subprocess.check_output(
            ["lipo", "-archs", str(binary)], text=True,
        ).split()
        if prepare and architectures != ["arm64"] and binary.is_relative_to(frameworks):
            if "arm64" not in architectures:
                raise SystemExit(f"Framework has no arm64 slice: {binary}")
            with tempfile.TemporaryDirectory(prefix=".arm64-", dir=binary.parent) as temp:
                thin = Path(temp) / binary.name
                subprocess.run([
                    "lipo", str(binary), "-thin", "arm64", "-output", str(thin),
                ], check=True)
                shutil.copystat(binary, thin)
                thin.replace(binary)
            sign(binary)
            changed_frameworks.update(
                parent for parent in binary.parents
                if parent.suffix == ".framework" and parent.is_relative_to(frameworks)
            )
            architectures = subprocess.check_output(
                ["lipo", "-archs", str(binary)], text=True,
            ).split()
        if architectures != ["arm64"]:
            raise SystemExit(f"Expected arm64, found {architectures}: {binary}")
        count += 1
    if not count:
        raise SystemExit(f"No native binaries found: {app}")
    # Seal enclosing frameworks after their nested libraries have been signed.
    # Xcode signs the enclosing app after its embed build phase completes.
    for framework in sorted(changed_frameworks, key=lambda p: len(p.parts), reverse=True):
        sign(framework)
    print(f"Verified {count} arm64 native binaries: {app}")


if __name__ == "__main__":
    args = sys.argv[1:]
    prepare = bool(args and args[0] == "--prepare")
    if prepare:
        args = args[1:]
    if len(args) != 1:
        raise SystemExit("usage: architectures.py [--prepare] APP")
    verify(Path(args[0]), prepare=prepare)
