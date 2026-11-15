import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile


def function(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--qt-prefix", type=Path, required=True)
    parser.add_argument("--baseline-ref", default="b420c96952c8e9a3bd43bdae2f43f583e8d451a3")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source = (root / "src/core/StelPainter.cpp").read_text()
    signature = "void StelPainter::drawFixedColorWideLinesAsQuads("
    current = function(source, signature)
    baseline_source = subprocess.check_output(
        ["git", "show", f"{args.baseline_ref}:src/core/StelPainter.cpp"], cwd=root, text=True
    )
    baseline = function(baseline_source, signature).replace(
        "StelPainter::drawFixedColorWideLinesAsQuads(", "StelPainter::drawLegacyWideLines(", 1
    )
    atmosphere = (root / "src/core/modules/AtmospherePreetham.cpp").read_text()
    upload = function(atmosphere, "if (gridChanged)")
    assert "colorGridBuffer.allocate(colorGrid.constData()," in upload
    assert "colorGridBuffer.write(" not in upload
    assert "static_cast<int>((1+skyResolutionX)*(1+skyResolutionY)*4*4)" in upload
    with tempfile.TemporaryDirectory(prefix="stellarium-wide-lines-") as directory:
        temporary = Path(directory)
        (temporary / "wide-lines-current.inc").write_text(current)
        (temporary / "wide-lines-legacy.inc").write_text(baseline)
        executable = temporary / "test-wide-lines"
        framework_path = args.qt_prefix / "lib"
        command = [
            os.environ.get("CXX", "c++"), "-std=c++17", "-g", "-O1",
            "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-Wall", "-Wextra",
            "-Wno-sign-compare", "-DQT_NO_DEBUG", "-I" + str(root / "src/core"),
            "-I" + str(temporary), "-F" + str(framework_path),
            "-I" + str(framework_path / "QtCore.framework/Headers"),
            "-I" + str(framework_path / "QtGui.framework/Headers"),
            str(root / "scripts/test-painter-streaming.cpp"),
            str(root / "src/core/VecMath.cpp"),
            "-framework", "QtCore", "-framework", "QtGui",
            "-Wl,-rpath," + str(framework_path), "-o", str(executable),
        ]
        subprocess.run(command, check=True)
        subprocess.run([str(executable)], check=True)
        broken = re.sub(
            r"void StelPainter::drawLegacyWideLines\(", signature, baseline, count=1
        )
        (temporary / "wide-lines-current.inc").write_text(broken)
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        regression = subprocess.run([str(executable)], capture_output=True, text=True)
        assert regression.returncode != 0, "Regression check unexpectedly accepts the old sparse Lines implementation"
        assert "actual.size()" in regression.stderr, regression.stderr
        print("Old Lines implementation rejected by vertex-count regression assertion")
        print("Preetham changed-grid upload contract passed; no GPU performance claim")


if __name__ == "__main__":
    main()
