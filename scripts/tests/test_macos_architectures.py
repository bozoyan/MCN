"""Exercise the packaging architecture check with real Mach-O binaries."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "macos/architectures.py"


@unittest.skipUnless(sys.platform == "darwin", "Requires Apple linker and codesign")
class ArchitectureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = tempfile.TemporaryDirectory(prefix="reveric-macho-")
        cls.root = Path(cls.fixture.name)
        source = cls.root / "probe.c"
        source.write_text("int main(void) { return 0; }\n")
        subprocess.run([
            "xcrun", "clang", "-arch", "arm64", str(source),
            "-o", str(cls.root / "Runner"),
        ], check=True, capture_output=True)
        subprocess.run([
            "xcrun", "clang", "-dynamiclib", "-arch", "arm64", "-arch", "x86_64",
            str(source), "-o", str(cls.root / "libprobe.dylib"),
        ], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.fixture.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="reveric-arm64-app-")
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / "Fixture.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        (self.app / "Contents/Frameworks").mkdir()
        shutil.copy2(self.root / "Runner", self.app / "Contents/MacOS/Runner")
        self.library = self.app / "Contents/Frameworks/libprobe.dylib"
        shutil.copy2(self.root / "libprobe.dylib", self.library)

    def run_check(self, prepare=False):
        return subprocess.run([
            sys.executable, str(SCRIPT), *(["--prepare"] if prepare else []),
            str(self.app),
        ], capture_output=True, text=True)

    def test_verification_rejects_universal_library(self):
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("x86_64", result.stderr)

    def test_preparation_thins_and_signs_then_verification_passes(self):
        executable = self.app / "Contents/MacOS/Runner"
        original = executable.read_bytes()
        result = self.run_check(prepare=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(executable.read_bytes(), original)
        subprocess.run(["codesign", "--verify", "--strict", str(self.library)], check=True)
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        before = self.library.read_bytes()
        self.assertEqual(self.run_check(prepare=True).returncode, 0)
        self.assertEqual(self.library.read_bytes(), before)

    def test_preparation_rejects_library_without_arm64(self):
        subprocess.run([
            "lipo", str(self.root / "libprobe.dylib"), "-thin", "x86_64",
            "-output", str(self.library),
        ], check=True)
        result = self.run_check(prepare=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no arm64 slice", result.stderr)


if __name__ == "__main__":
    unittest.main()
