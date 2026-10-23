#!/usr/bin/env python3
"""Repackage the QGroundControl-Bastion AppImage as a .deb without rebuilding.

The AppImage bundles Qt, GStreamer with its plugins and the codecs, so its contents are installed
as a private runtime under /opt/QGroundControl-Bastion and started through the AppImage's AppRun.
Only libraries the AppImage deliberately leaves to the host (glibc, the GL/EGL drivers, X11/XCB,
fonts, ...) become package dependencies, so one .deb installs on Ubuntu 22.04, 24.04 and 26.04.

Usage: deb_from_appimage.py <AppImage> <output-dir> <version> [--commit <sha>] [--pipeline <n>]
Needs readelf (binutils), dpkg-deb and unsquashfs (squashfs-tools); without unsquashfs the
AppImage extracts itself, which only works on a matching CPU architecture.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

PACKAGE = "qgroundcontrol-bastion"
APP_NAME = "QGroundControl-Bastion"
APP_ID = "org.mavlink.qgroundcontrol.bastion"
PREFIX = Path("opt") / APP_NAME
MAINTAINER = "Dronecode <dev@dronecode.org>"
HOMEPAGE = "https://qgroundcontrol.com/"

# Host libraries the AppImage expects from the system, by soname. Package names are the same on
# Ubuntu 22.04-26.04 except where 24.04 renamed them for the 64-bit time_t transition (t64).
REQUIRED = {
    "ld-linux-x86-64.so.2": "libc6 (>= 2.35)",
    "libc.so.6": "libc6 (>= 2.35)",
    "libdl.so.2": "libc6 (>= 2.35)",
    "libm.so.6": "libc6 (>= 2.35)",
    "libpthread.so.0": "libc6 (>= 2.35)",
    "libresolv.so.2": "libc6 (>= 2.35)",
    "librt.so.1": "libc6 (>= 2.35)",
    "libgcc_s.so.1": "libgcc-s1",
    "libstdc++.so.6": "libstdc++6",
    "libz.so.1": "zlib1g",
    "libEGL.so.1": "libegl1",
    "libGL.so.1": "libgl1",
    "libGLX.so.0": "libglx0",
    "libGLdispatch.so.0": "libglvnd0",
    "libOpenGL.so.0": "libopengl0",
    "libdrm.so.2": "libdrm2",
    "libgbm.so.1": "libgbm1",
    "libX11.so.6": "libx11-6",
    "libX11-xcb.so.1": "libx11-xcb1",
    "libXext.so.6": "libxext6",
    "libXrandr.so.2": "libxrandr2",
    "libxcb.so.1": "libxcb1",
    "libxcb-glx.so.0": "libxcb-glx0",
    "libwayland-client.so.0": "libwayland-client0",
    "libfontconfig.so.1": "libfontconfig1",
    "libfreetype.so.6": "libfreetype6",
    "libharfbuzz.so.0": "libharfbuzz0b",
    "libfribidi.so.0": "libfribidi0",
    "libasound.so.2": "libasound2 | libasound2t64",
    "libcom_err.so.2": "libcom-err2",
    "libgmp.so.10": "libgmp10",
    "libgpg-error.so.0": "libgpg-error0",
}
# Only needed by optional plugins (Qt GTK theme, speech-dispatcher text to speech, GStreamer PulseAudio
# for camera audio, which falls back to ALSA).
OPTIONAL = {
    "libpulse.so.0": "libpulse0",
    "libpulse-simple.so.0": "libpulse0",
    "libgtk-3.so.0": "libgtk-3-0 | libgtk-3-0t64",
    "libgdk-3.so.0": "libgtk-3-0 | libgtk-3-0t64",
    "libatk-1.0.so.0": "libatk1.0-0 | libatk1.0-0t64",
    "libspeechd.so.2": "libspeechd2",
}
# Development files the AppImage carries but a runtime package does not need.
DROP = ("usr/include", "usr/lib/cmake")


def squashfs_offset(appimage: Path) -> int:
    """The squashfs image starts right after the AppImage runtime's ELF section headers."""
    header = appimage.read_bytes()[:64]
    if header[:4] != b"\x7fELF" or header[4] != 2:
        raise ValueError(f"{appimage} is not a 64-bit ELF AppImage")
    section_offset = struct.unpack_from("<Q", header, 0x28)[0]
    entry_size, entry_count = struct.unpack_from("<HH", header, 0x3A)
    return section_offset + entry_size * entry_count


def extract(appimage: Path, destination: Path) -> None:
    if not shutil.which("unsquashfs"):
        # Fallback: let the AppImage runtime unpack itself (needs to run on this machine).
        work = destination.parent / "appimage-extract"
        work.mkdir()
        subprocess.run(
            [str(appimage), "--appimage-extract"], cwd=work, check=True, stdout=subprocess.DEVNULL
        )
        (work / "squashfs-root").rename(destination)
        work.rmdir()
        return
    subprocess.run(
        [
            "unsquashfs",
            "-quiet",
            "-no-xattrs",
            "-offset",
            str(squashfs_offset(appimage)),
            "-dest",
            str(destination),
            str(appimage),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def normalize(tree: Path) -> None:
    """Root-owned package files: directories 755, executables 755, everything else 644."""
    for path in [tree, *tree.rglob("*")]:
        if path.is_symlink():
            continue
        mode = path.stat().st_mode
        executable = path.is_dir() or mode & stat.S_IXUSR
        path.chmod(0o755 if executable else 0o644)


def elf_files(tree: Path):
    for path in tree.rglob("*"):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as handle:
                if handle.read(4) == b"\x7fELF":
                    yield path


def host_dependencies(runtime: Path) -> tuple[list[str], list[str]]:
    bundled = {path.name for path in runtime.rglob("*")}
    needed: dict[str, Path] = {}
    for path in elf_files(runtime):
        dynamic = subprocess.run(
            ["readelf", "--dynamic", str(path)], capture_output=True, text=True, check=False
        ).stdout
        for soname in re.findall(r"\(NEEDED\)\s+Shared library: \[(.+?)\]", dynamic):
            if soname not in bundled:
                needed.setdefault(soname, path)
    unknown = sorted(name for name in needed if name not in REQUIRED and name not in OPTIONAL)
    if unknown:
        details = ", ".join(
            f"{name} (from {needed[name].relative_to(runtime)})" for name in unknown
        )
        raise ValueError(
            f"no package mapping for host libraries: {details}; add them to {__file__}"
        )
    depends = sorted({REQUIRED[name] for name in needed if name in REQUIRED})
    recommends = sorted({OPTIONAL[name] for name in needed if name in OPTIONAL})
    return depends, recommends


def installed_size_kib(tree: Path) -> int:
    total = sum(path.lstat().st_size for path in tree.rglob("*") if not path.is_dir())
    return (total + 1023) // 1024


def build(appimage: Path, output: Path, version: str, commit: str, pipeline: str) -> Path:
    with tempfile.TemporaryDirectory() as work_dir:
        root = Path(work_dir) / "pkg"
        runtime = root / PREFIX
        runtime.parent.mkdir(parents=True)
        extract(appimage, runtime)

        for name in (".DirIcon", f"{APP_NAME}.svg", f"{APP_ID}.desktop"):
            (runtime / name).unlink(missing_ok=True)
        for relative in DROP:
            shutil.rmtree(runtime / relative, ignore_errors=True)
        for archive in runtime.rglob("*.a"):
            archive.unlink()
        if not (runtime / "AppRun").is_file() or not (runtime / "usr/bin" / APP_NAME).is_file():
            raise ValueError("the AppImage has no AppRun or usr/bin executable")

        share = root / "usr/share"
        for name in ("applications", "icons", "metainfo"):
            source = runtime / "usr/share" / name
            if not source.is_dir():
                raise ValueError(f"the AppImage has no usr/share/{name}")
            shutil.copytree(source, share / name, symlinks=True)
        (root / "usr/bin").mkdir(parents=True)
        (root / "usr/bin" / APP_NAME).symlink_to(Path("../..") / PREFIX / "AppRun")
        normalize(root)

        depends, recommends = host_dependencies(runtime)
        upstream = version.split("+", 1)[0]
        built_from = ", ".join(
            part
            for part in (
                f"commit {commit}" if commit else "",
                f"pipeline #{pipeline}" if pipeline else "",
            )
            if part
        )
        control = [
            f"Package: {PACKAGE}",
            f"Version: {version}",
            "Architecture: amd64",
            f"Maintainer: {MAINTAINER}",
            f"Installed-Size: {installed_size_kib(root)}",
            f"Depends: {', '.join(depends)}",
            *([f"Recommends: {', '.join(recommends)}"] if recommends else []),
            "Section: electronics",
            "Priority: optional",
            f"Homepage: {HOMEPAGE}",
            "Description: QGroundControl-Bastion ground control station",
            " QGroundControl with multi-camera support for several vehicles, installed",
            " alongside the original QGroundControl. Based on QGroundControl "
            f"{upstream.replace('~', '-')}.",
            *([f" Built from {built_from}."] if built_from else []),
        ]
        debian = root / "DEBIAN"
        debian.mkdir(mode=0o755)
        (debian / "control").write_text("\n".join(control) + "\n")

        output.mkdir(parents=True, exist_ok=True)
        deb = output / f"{PACKAGE}_{version}_amd64.deb"
        subprocess.run(
            ["dpkg-deb", "--root-owner-group", "-Zxz", "--build", str(root), str(deb)],
            check=True,
            stdout=subprocess.DEVNULL,
        )
    return deb


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("appimage", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("version")
    parser.add_argument("--commit", default=os.environ.get("CI_COMMIT_SHORT_SHA", ""))
    parser.add_argument("--pipeline", default=os.environ.get("CI_PIPELINE_IID", ""))
    args = parser.parse_args(argv)
    try:
        deb = build(
            args.appimage.resolve(), args.output.resolve(), args.version, args.commit, args.pipeline
        )
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"Built {deb.name}")
    print(
        subprocess.run(
            ["dpkg-deb", "--info", str(deb)], capture_output=True, text=True, check=True
        ).stdout
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
