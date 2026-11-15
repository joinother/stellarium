import argparse
import os
from pathlib import Path
import re
import runpy
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--qt-prefix", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    extract = runpy.run_path(str(root / "scripts/test-painter-streaming.py"))["function"]
    source = (root / "src/core/StelPainter.cpp").read_text()
    signatures = [
        "void StelPainter::drawFromArray(",
        "void StelPainter::drawTrianglesWithDepthPrepass(",
        "void StelPainter::drawFromArrayImpl(",
        "size_t StelPainter::ArrayDesc::vertexSizeInBytes(",
        "void StelPainter::setDepthMask(",
        "void StelPainter::setBlending(",
    ]
    functions = "\n\n".join(extract(source, signature) for signature in signatures)
    shader_sources = []
    for name in ("vshaderInterpolatedColorSrc", "fshaderInterpolatedColorSrc"):
        declaration = re.search(r"const auto " + name + r' =.*?";', source, re.S)
        assert declaration, name
        shader_sources.append(declaration.group())
    model = extract((root / "src/core/modules/Constellation.cpp").read_text(), "void Constellation::drawArtModel(")
    assert model.count("drawTrianglesWithDepthPrepass(") == 1
    assert "drawFromArray(" not in model
    assert model.count("glClear(GL_DEPTH_BUFFER_BIT)") == 2
    assert "glDepthFunc(oldDepthFunction)" in model
    with tempfile.TemporaryDirectory(prefix="stellarium-depth-prepass-") as directory:
        temporary = Path(directory)
        implementation = temporary / "painter-depth-prepass.inc"
        implementation.write_text(functions)
        (temporary / "painter-color-shaders.inc").write_text("\n".join(shader_sources))
        executable = temporary / "test-depth-prepass"
        frameworks = args.qt_prefix / "lib"
        command = [
            os.environ.get("CXX", "c++"), "-std=c++17", "-g", "-O1",
            "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-Wall", "-Wextra",
            "-I" + str(root / "src/core"), "-I" + str(temporary), "-F" + str(frameworks),
        ]
        for framework in ("QtCore", "QtGui", "QtOpenGL"):
            command += ["-I" + str(frameworks / f"{framework}.framework/Headers"), "-framework", framework]
        command += [str(root / "scripts/test-painter-depth-prepass.cpp"),
                    str(root / "src/core/VecMath.cpp"),
                    "-Wl,-rpath," + str(frameworks), "-o", str(executable)]
        subprocess.run(command, check=True)
        subprocess.run([str(executable)], check=True)
        broken = functions.replace(
            "setDepthMask(false);\n\t\tsetBlending(true, GL_SRC_ALPHA, GL_ONE);",
            "setDepthMask(false);\n\t\tverticesVBO->allocate(16);\n\t\tsetBlending(true, GL_SRC_ALPHA, GL_ONE);",
        )
        assert broken != functions
        implementation.write_text(broken)
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        regression = subprocess.run([str(executable)], capture_output=True, text=True)
        assert regression.returncode != 0, "Regression accepted a second upload between passes"
        assert "uploads" in regression.stderr, regression.stderr
        print("Re-upload mutation rejected; constellation external depth cleanup contract passed")


if __name__ == "__main__":
    main()
