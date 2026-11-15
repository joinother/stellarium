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
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--qt-prefix", type=Path, default=Path("/Users/jiexuanyang/Qt/6.12.0/macos"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    movement = (root / "src/core/StelMovementMgr.cpp").read_text()
    source = (root / "src/StelMainView.cpp").read_text()
    solver = function(movement, "bool StelMovementMgr::solveMountFrameAnchor(")
    anchor = function(source, "static void ohosAnchorSkyDirection(")
    assert "const bool freezeRoll = s_ohosPinchActive || s_ohosPinchSettleActive" in anchor
    assert "if (!freezeRoll)" in anchor and "solveMountFrameAnchor" in anchor
    assert "ohosMountCanonicalUp(viewMount, previousUpMount, true)" in anchor
    assert anchor.index("movementMgr->setViewUpVector(upMount)") < anchor.index("movementMgr->setViewDirectionJ2000(")
    maintain = function(source, "static void ohosMaintainSelectedZoomAnchor()")
    for guard in ("s_gyroViewActive", "scriptIsRunning()", "getFlagTracking()", "getFlagAutoMove()"):
        assert re.search(r"if \([^\n]*" + re.escape(guard) + r"[^\n]*\)\s*return;", maintain)
    for command in ('if (commandName == "advanceTime")', 'if (commandName == "setJD")',
                    'if (commandName == "setJulianDate" || commandName == "setTimeToJD")'):
        handler = function(source, command)
        assert "setJD(" in handler
        assert "setView" not in handler and "setFlagTracking" not in handler
    tracking = function(movement, "void StelMovementMgr::updateVisionVector(")
    tracking = tracking[tracking.index("if (flagTracking &&"):]
    assert tracking.index("setViewUpVector(") < tracking.index("setViewDirectionJ2000(")
    zoom = function(movement, "void StelMovementMgr::updateAutoZoom(")
    assert zoom.index("setViewUpVectorJ2000(") < zoom.index("setViewDirectionJ2000(")
    diagnostics = function(source, 'if (commandName == "getLandscapeInfo")')
    for key in ("atmosphereVisualStrength", "starLimitMagnitude", "limitMagnitude", "extinctionCoefficient"):
        assert f'result["{key}"]' in diagnostics
    diagnostics = function(source, 'if (commandName == "setViewAnchorProbe" || commandName == "getViewAnchorState")')
    for key in ("viewMount", "upMount", "viewAltAz", "upAltAz", "horizonRollDefined", "horizonRollDeg",
                "selectedProjectable", "selectedVisible", "selectedXRatio", "selectedYRatio"):
        assert f'result["{key}"]' in diagnostics
    with tempfile.TemporaryDirectory(prefix="stellarium-time-camera-") as directory:
        temporary = Path(directory)
        implementation = temporary / "selected-time-camera.inc"
        implementation.write_text(solver)
        executable = temporary / "test-camera"
        frameworks = args.qt_prefix / "lib"
        command = [os.environ.get("CXX", "clang++"), "-std=c++17", "-g", "-O1",
                   "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-Wall", "-Wextra",
                   "-I" + str(root / "src/core"), "-I" + str(temporary), "-F" + str(frameworks)]
        for framework in ("QtCore", "QtGui"):
            command += ["-I" + str(frameworks / f"{framework}.framework/Headers"), "-framework", framework]
        command += [str(root / "scripts/test-selected-time-camera.cpp"), "-Wl,-rpath," + str(frameworks),
                    "-o", str(executable)]
        subprocess.run(command, check=True)
        subprocess.run([str(executable)], check=True)
        broken = solver.replace("up = bestUp;", "up = -bestUp;")
        assert broken != solver
        implementation.write_text(broken)
        subprocess.run(command, check=True, capture_output=True)
        failure = subprocess.run([str(executable)], capture_output=True, text=True)
        assert failure.returncode != 0 and "up[2] > 0." in failure.stderr
        print("Inverted-horizon mutation rejected; ownership/time/diagnostic source contracts passed")


if __name__ == "__main__":
    main()
