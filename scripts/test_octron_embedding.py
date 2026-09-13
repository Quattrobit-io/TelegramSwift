#!/usr/bin/env python3
"""Exercise native input ownership without starting an account or presenting a window."""

import argparse
import json
import platform
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--products", type=Path, required=True)
    parser.add_argument("--frameworks", type=Path)
    parser.add_argument("--arch", choices=("arm64", "x86_64"), default=platform.machine())
    args = parser.parse_args()
    products = args.products.resolve(strict=True)
    frameworks = args.frameworks.resolve(strict=True) if args.frameworks else products
    output = ROOT / "work/embedded-input-proof"
    output.mkdir(parents=True, exist_ok=True)
    header = (frameworks / "Telegram.framework/Headers/OctronTelegram.h").resolve(strict=True)
    (output / "module.modulemap").write_text(
        "module OctronTelegram {\n header " + json.dumps(str(header)) + "\n export *\n}\n")
    objc_module = products.parents[1] / "Intermediates.noindex/GeneratedModuleMaps/ObjcUtils.modulemap"
    compiler = subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()
    executable = output / "InputOwnershipProof"
    command = [
        compiler, "-parse-as-library", "-target", args.arch + "-apple-macosx15.0",
        "-I", str(products), "-I", str(output),
        "-Xcc", "-fmodule-map-file=" + str(objc_module),
        "-F", str(frameworks), "-framework", "Telegram",
        "-Xlinker", "-rpath", "-Xlinker", str(frameworks),
        str(ROOT / "OctronTelegram/Tests/InputOwnershipProof.swift"), "-o", str(executable),
    ]
    for name, invocation in [
        ("build", command),
        ("run", [str(executable), str(frameworks / "Telegram.framework/Telegram")]),
    ]:
        result = subprocess.run(invocation, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        (output / (name + ".log")).write_text(result.stdout)
        if result.returncode:
            print(result.stdout[-12000:])
            raise SystemExit(result.returncode)
        if name == "run":
            print(result.stdout)


if __name__ == "__main__":
    main()
