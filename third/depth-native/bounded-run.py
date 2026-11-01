"""Run one macOS validation process with a physical-footprint budget."""
import ctypes
import json
from pathlib import Path
import subprocess
import sys
import time


class Usage(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64) for name in
        ("user", "system", "idle", "interrupt", "pageins", "wired", "resident", "footprint", "start", "exit")
    ]


if sys.platform != "darwin" or len(sys.argv) < 3:
    raise SystemExit("Usage (macOS): python bounded-run.py LOG COMMAND [ARG ...]")
log = Path(sys.argv[1])
log.parent.mkdir(parents=True, exist_ok=True)
libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
limit = 6 * 1024 ** 3
peak = 0
reason = None
started = time.monotonic()
with log.open("w") as output:
    process = subprocess.Popen(sys.argv[2:], stdout=output, stderr=subprocess.STDOUT)
    try:
        while process.poll() is None:
            usage = Usage()
            if libproc.proc_pid_rusage(process.pid, 0, ctypes.byref(usage)) == 0:
                peak = max(peak, usage.footprint)
                if usage.footprint > limit:
                    reason = "physical_footprint_limit"
            if time.monotonic() - started > 900:
                reason = "timeout"
            if reason:
                process.terminate()
                break
            time.sleep(0.1)
        try:
            code = process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            code = process.wait()
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
report = {"exit_code": code, "stopped_reason": reason,
          "sampled_peak_physical_footprint_bytes": peak,
          "physical_footprint_limit_bytes": limit, "sampling_seconds": 0.1,
          "seconds": time.monotonic() - started}
log.with_suffix(".usage.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report), flush=True)
raise SystemExit(1 if reason else code)
