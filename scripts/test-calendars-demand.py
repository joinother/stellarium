import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile


def function(source, signature):
    start = source.index(signature)
    cursor = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--qt-prefix", type=Path, default=Path("/Users/jiexuanyang/Qt/6.12.0/macos"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source = (root / "plugins/Calendars/src/Calendars.cpp").read_text()
    header = (root / "plugins/Calendars/src/Calendars.hpp").read_text()
    functions = "\n\n".join(function(source, signature) for signature in (
        "Calendar* Calendars::getCal(", "void Calendars::refreshConversionInputs(",
        "void Calendars::updateCalendar(", "void Calendars::update("))
    for name in ("refreshConversionInputs", "updateCalendar"):
        assert re.search(r"void " + name + r"\([^;]*\);", header)
    for signal in ("locationChanged", "currentTimeZoneChanged", "useCustomTimeZoneChanged",
                   "flagUseDSTChanged", "ephemAlgorithmChanged", "languageChanged", "mayaCorrelationJDChanged"):
        assert re.search(r"connect\([^\n]*::" + signal + r", this, invalidateConversions\)", source)
    assert "const auto invalidateConversions = [this]() { conversionInputsValid = false; };" in source
    assert "connect(cal, &Calendar::jdChanged, this, [this]() { conversionInputsValid = false; });" in source
    assert re.search(r"CalendarsDialog::visibleChanged[\s\S]*?conversionInputsValid = false;\s*if \(visible\) update\(0\.0\);", source)
    assert re.search(r"StelScriptMgr::scriptRunning[\s\S]*?refreshConversionInputs\(\);[\s\S]*?updateCalendar\(calendar\);", source)
    table = function(source, "QString Calendars::createTableToDraw(")
    assert "calendars.value" not in table and "getCal(" in table
    with tempfile.TemporaryDirectory(prefix="stellarium-calendars-demand-") as directory:
        temporary = Path(directory)
        implementation = temporary / "calendars-demand.inc"
        implementation.write_text(functions)
        executable = temporary / "test-calendars"
        frameworks = args.qt_prefix / "lib"
        command = [os.environ.get("CXX", "clang++"), "-std=c++17", "-g", "-O1",
                   "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-Wall", "-Wextra",
                   "-I" + str(root / "src/core"), "-I" + str(temporary), "-F" + str(frameworks)]
        for framework in ("QtCore", "QtGui"):
            command += ["-I" + str(frameworks / f"{framework}.framework/Headers"), "-framework", framework]
        command += [str(root / "scripts/test-calendars-demand.cpp"), "-Wl,-rpath," + str(frameworks),
                    "-o", str(executable)]
        for defines in ([], ["-DNO_GUI"], ["-DENABLE_SCRIPTING"], ["-DNO_GUI", "-DENABLE_SCRIPTING"]):
            subprocess.run(command + defines, check=True)
            subprocess.run([str(executable)], check=True)
            print("Configuration:", " ".join(defines) or "GUI, no scripting", flush=True)
        for label, broken in (
            ("hidden eager conversion", functions.replace("if (!liveConsumer)", "if (false)")),
            ("stale on-demand read", functions.replace("\t\trefreshConversionInputs();", "")),
        ):
            assert broken != functions
            implementation.write_text(broken)
            subprocess.run(command, check=True, capture_output=True)
            failure = subprocess.run([str(executable)], capture_output=True, text=True)
            assert failure.returncode != 0 and "Assertion failed" in failure.stderr, label
            print("Rejected mutation:", label)


if __name__ == "__main__":
    main()
