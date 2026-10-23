#!/usr/bin/env python3
"""Build a configured Docker variant, or run an existing builder image."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from _variants import load_variants

BUILD_TYPES = ("Release", "Debug", "RelWithDebInfo", "MinSizeRel")
REPO_ROOT = Path(__file__).resolve().parents[2]


def run_image(image: str, build_type: str, *, fuse: bool = False) -> None:
    source = Path(os.environ.get("SOURCE_DIR", Path.cwd())).resolve()
    build = Path(os.environ.get("BUILD_DIR", source / "build")).resolve()
    build.mkdir(parents=True, exist_ok=True)
    command = [
        "docker",
        "run",
        "--rm",
        "--user",
        f"{os.getuid()}:{os.getgid()}",
        # A mapped UID need not exist in the container's passwd database.
        "--env",
        "HOME=/tmp",
        "--env",
        f"CLEAN_BUILD={os.environ.get('CLEAN_BUILD', '0')}",
        "--env",
        f"JOBS={os.environ.get('JOBS', '')}",
    ]
    # Paths are translated inside the container; only portable cache settings cross this boundary.
    for name in ("CCACHE_MAXSIZE", "CCACHE_NOFILECLONE", "MOCCACHE_MAX_SIZE", "MOCCACHE_STATS"):
        if name in os.environ:
            command += ["--env", f"{name}={os.environ[name]}"]
    # AppImage tools fall back to extract-and-run, so CI can skip FUSE where /dev/fuse is unavailable.
    if fuse and os.environ.get("QGC_DOCKER_FUSE", "1") != "0":
        command += [
            "--cap-add",
            "SYS_ADMIN",
            "--device",
            "/dev/fuse",
            "--security-opt",
            "apparmor:unconfined",
        ]
    command += [
        "-v",
        f"{source}:/project/source",
        "-v",
        f"{build}:/project/build",
        image,
        build_type,
    ]
    subprocess.run(command, check=True)


def build_variant(variant_id: str, build_type: str) -> None:
    variant = next(variant for variant in load_variants() if variant["id"] == variant_id)
    image = os.environ.get("IMAGE_NAME", variant["image"])
    command = [
        "docker",
        "build",
        "--file",
        str(REPO_ROOT / "deploy/docker/Dockerfile"),
        "--target",
        variant["target"],
    ]
    for key, value in variant["build_args"].items():
        command += ["--build-arg", f"{key}={value}"]
    # Optional shared cache in a registry (used by GitLab CI): DOCKER_CACHE_FROM lists images whose
    # layers may be reused, DOCKER_PUSH_IMAGE=1 pushes the result so other runners can reuse it.
    cache_from = os.environ.get("DOCKER_CACHE_FROM", "").split()
    if cache_from:
        command += ["--build-arg", "BUILDKIT_INLINE_CACHE=1"]
        for ref in cache_from:
            command += ["--cache-from", ref]
    # Keep the variant's own name as well: helper scripts (e.g. deploy/ci/sign-apk-docker.sh) use it.
    tags = ["-t", image] + (["-t", variant["image"]] if image != variant["image"] else [])
    subprocess.run([*command, *tags, str(REPO_ROOT)], check=True)
    if os.environ.get("DOCKER_PUSH_IMAGE") == "1":
        if subprocess.run(["docker", "push", image]).returncode != 0:
            print(f"warning: could not push {image}; continuing without updating the cache", file=sys.stderr)
    os.environ["SOURCE_DIR"] = str(REPO_ROOT)
    if variant_id == "aarch64":
        os.environ.setdefault("BUILD_DIR", str(REPO_ROOT / "build-aarch64"))
        os.environ.setdefault("JOBS", str(max(1, (os.cpu_count() or 1) // 2)))
    run_image(image, build_type, fuse=variant["fuse"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("build", help="Build and run a repository variant")
    build.add_argument("variant", choices=[variant["id"] for variant in load_variants()])
    build.add_argument("build_type", nargs="?", default="Release", choices=BUILD_TYPES)
    run = commands.add_parser("run", help="Run an existing builder image")
    run.add_argument("image")
    run.add_argument("build_type", nargs="?", default="Release", choices=BUILD_TYPES)
    run.add_argument("--fuse", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.command == "build":
            build_variant(args.variant, args.build_type)
        else:
            run_image(args.image, args.build_type, fuse=args.fuse)
        return 0
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"Docker build failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
