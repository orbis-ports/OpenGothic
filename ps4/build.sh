#!/usr/bin/env bash
# Cross-build OpenGothic for the PlayStation 4.
#
#   ps4/build.sh [--work <dir>] [--jobs N] [--orbis-compat <dir>] [--mesa-bundle <dir>] [--sound-null]
#
# Mesa: a mesa-ps4 checkout with build-orbis/ (found by orbis-env.sh), or a release bundle
# (orbis-ports/mesa-ps4 orbis-mesa-<sha>.tar.gz: include/ + build-orbis/src/...) given by
# --mesa-bundle <dir> or by ORBIS_MESA_SRC + ORBIS_MESA_BUILD in the environment, which is what
# .github/actions/orbis-toolchain exports.
#
# Builds THIS checkout in place. lib/Tempest and lib/ZenKit are expected to be the forks
# carrying the PS4 work; everything the build produces lives under --work, nothing under
# the repository.
#
# ⚠ THERE IS NO PATCH QUEUE ANY MORE, AND NO SCRATCH CLONE. Both existed because the PS4
# changes to OpenGothic had nowhere to live: the previous script cloned an untouched
# checkout and applied a patch queue to it, "until the maintainer decides
# how the OpenGothic side of this port is tracked". That is decided - there are forks - so
# the changes are commits here and the build reads them directly.
#
# ⚠ THE GNM SIDE IS GONE WITH IT. --tune, --diag and AMDLLPC selected shader-bake and
# backend knobs for the GNM route, which this branch does not carry: RADV compiles the
# SPIR-V at run time through ACO, so there is nothing to bake and no compiler to pin.
#
# WHAT IS NOT PACKAGED: game data. Not by this script, not by the .pkg it produces. The
# title finds an installation at run time - ps4/og_ps4_boot.h.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${HOME}/.cache/opengothic-ps4"
# ⚠ NOT `nproc`. It is GNU coreutils and macOS does not ship it, so this line exited 127 and
# took the whole script with it under `set -e`:
#
#     ./ps4/build.sh: line 31: nproc: command not found
#
# Measured by bundle-gate.sh stage 5, 2026-09-17. getconf is POSIX and answers on both Linux
# and macOS; nproc and sysctl are kept behind it for the platforms where it does not.
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
SOUND_NULL=OFF
# orbis-env.sh only knows mesa-ps4 checkouts and overwrites ORBIS_MESA_BUILD - keep a bundle given by
# the environment.
MESA_BUNDLE_SRC=""
MESA_BUNDLE_BUILD=""
if [[ -n "${ORBIS_MESA_SRC:-}" && -n "${ORBIS_MESA_BUILD:-}" ]]; then
  MESA_BUNDLE_SRC="${ORBIS_MESA_SRC}"
  MESA_BUNDLE_BUILD="${ORBIS_MESA_BUILD}"
fi
# The platform overlay: the toolchain file, the SDK corrections, the Vulkan C ABI and the log
# channel.
#
# ⚠ The six lines that cannot be shared - see orbis-compat/scripts/ps4/orbis-env.sh. Sibling
# directory before the old personal default, because that is what a fresh clone of the orbis-ports
# organisation looks like: the repositories next to each other.
# ⚠ TWO REPOSITORIES SINCE 2026-09-18. orbis-compat is include/ and the archive; the porting kit is
# the toolchain file, the loader shim and these scripts. The overlay is found by a HEADER it owns -
# probing for scripts/ps4/orbis-env.sh would now find nothing, and before that it would have found
# the kit and called it the overlay.
for _c in "${ORBIS_COMPAT_DIR:-}" "$(dirname "${BASH_SOURCE[0]}")/../../orbis-compat" "${HOME}/src-ps4/orbis-compat"; do
  [[ -n "$_c" && -f "$_c/include/orbis_prefix.h" ]] && { ORBIS_COMPAT_DIR="$_c"; break; }
done
[[ -n "${ORBIS_COMPAT_DIR:-}" ]] || {
  echo "!! orbis-compat not found - clone https://github.com/orbis-ports/orbis-compat next to this" >&2
  echo "   repository, or set ORBIS_COMPAT_DIR / pass --orbis-compat <dir>" >&2
  exit 1
}
# ⚠ ABSOLUTE, BECAUSE A RELATIVE ONE REACHES cmake AND cmake RESOLVES IT SOMEWHERE ELSE. The sibling
# candidates above are relative - "$(dirname "${BASH_SOURCE[0]}")/../../..." - so invoked as
# `bash OpenGothic/ps4/build.sh` from one directory up, ORBIS_KIT_DIR becomes
# OpenGothic/ps4/../../orbis-porting-kit and lands on `cmake -DCMAKE_TOOLCHAIN_FILE=`, which resolves
# a relative path against the SOURCE directory rather than the caller's. MEASURED 2026-09-20 by
# review: "Could not find toolchain file: OpenGothic/ps4/../../orbis-porting-kit/cmake/ps4-openorbis.cmake",
# exit 1. Run as `cd OpenGothic && ./ps4/build.sh` it passed - by coincidence, because the two
# resolutions happen to agree from there. Same defect and same day as RetroArch's ps4/build-cores.sh,
# where it made every core in a sweep report a failed patch.
ORBIS_COMPAT_DIR="$(cd "$ORBIS_COMPAT_DIR" && pwd -P)"
export ORBIS_COMPAT_DIR

# The kit, the same way. The last candidate is the overlay itself, which carried these scripts until
# 2026-09-18 - so a pinned checkout older than that still works, and that is the arm in use whenever
# ORBIS_COMPAT_REF predates the move.
for _k in "${ORBIS_KIT_DIR:-}" "$(dirname "${BASH_SOURCE[0]}")/../../orbis-porting-kit" "${HOME}/src-ps4/orbis-porting-kit" "${ORBIS_COMPAT_DIR}"; do
  [[ -n "$_k" && -f "$_k/scripts/ps4/orbis-env.sh" ]] && { ORBIS_KIT_DIR="$_k"; break; }
done
[[ -n "${ORBIS_KIT_DIR:-}" ]] || {
  echo "!! orbis-porting-kit not found - clone https://github.com/orbis-ports/orbis-porting-kit next" >&2
  echo "   to this repository, or set ORBIS_KIT_DIR" >&2
  exit 1
}
# Absolute for the same reason as the overlay above: this one is handed to cmake as the toolchain
# file, and a relative toolchain path is resolved against the source directory.
ORBIS_KIT_DIR="$(cd "$ORBIS_KIT_DIR" && pwd -P)"
export ORBIS_KIT_DIR
. "${ORBIS_KIT_DIR}/scripts/ps4/orbis-env.sh"
ORBIS_COMPAT="${ORBIS_COMPAT_DIR}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work) WORK="$2"; shift 2 ;;
    --orbis-compat) ORBIS_COMPAT="$2"; ORBIS_COMPAT_DIR="$2"; export ORBIS_COMPAT_DIR; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    # The silent control rung. Not a fallback for when something sounds wrong: it is the build that
    # separates "the defect is in the audio path" from "the defect is beside it".
    --sound-null) SOUND_NULL=ON; shift ;;
    --mesa-bundle) MESA_BUNDLE_SRC="$(cd "$2" && pwd)"; MESA_BUNDLE_BUILD="${MESA_BUNDLE_SRC}/build-orbis"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

BUILD="${WORK}/build"

if [[ -n "${MESA_BUNDLE_SRC}" ]]; then
  [[ -f "${MESA_BUNDLE_SRC}/include/vulkan/vulkan.h" ]] || orbis_die "Mesa bundle ${MESA_BUNDLE_SRC} has no include/vulkan/vulkan.h"
  [[ -f "${MESA_BUNDLE_BUILD}/src/amd/vulkan/libvulkan_radeon.a" ]] || orbis_die "Mesa bundle has no ${MESA_BUNDLE_BUILD}/src/amd/vulkan/libvulkan_radeon.a"
  export ORBIS_MESA_DIR="${MESA_BUNDLE_SRC}"
  export ORBIS_MESA_BUILD="${MESA_BUNDLE_BUILD}"
  export ORBIS_RADV_ARCHIVE="${MESA_BUNDLE_BUILD}/src/amd/vulkan/libvulkan_radeon.a"
  [[ -f "${MESA_BUNDLE_SRC}/manifest.txt" ]] && orbis_note "Mesa bundle: $(grep -E '^(bundle|mesa-commit)=' "${MESA_BUNDLE_SRC}/manifest.txt" | tr '\n' ' ')"
fi

# ⚠ THE THREE TREES THAT CARRY THE PORT ARE CHECKED, BECAUSE A STALE ONE BUILDS CLEANLY.
#
# ⚠ AND THIS BLOCK WAS ITSELF STALE FOR A DAY. It checked lib/Tempest/ps4/vkloader/vkloader.h,
# which moved to the overlay on 2026-08-20, so every run of this script exited 1 before compiling
# anything - and the toolchain path below named a Tempest cmake/ directory that is now empty. A
# guard that names a moved file is worse than no guard: it fails builds that are correct. When a
# file moves, its guard moves with it.
#
# orbis-compat must carry the loader and the toolchain file - the C ABI in front of RADV, because
# there is no Vulkan loader on this console and there cannot be one. lib/Tempest must be the fork
# with the Orbis SystemApi backend, without which there is no window, no input and no clock.
# lib/ZenKit must be the one with VfsMountMode, without which resources.cpp does not compile; and
# were it to compile, the mount would fall back to mmap, which populates eagerly here and hangs the
# machine on ~2.7 GiB of archives.
#
# Checked by a file each rather than by a revision: any of them may be a symlink to a working tree,
# a checked-out branch or a fork's commit, and the build cares only that the code is there.
# ⚠ THE TOOLCHAIN FILE AND THE LOADER ARE THE KIT'S SINCE 2026-09-18, and the overlay keeps
# include/ and the archive. ORBIS_KIT_DIR comes from the kit's setup-orbis action or from an SDK
# bundle's env.sh; the fallback is the overlay, which still carries both in any bundle cut before
# that day and in any pinned checkout older than it.
ORBIS_KIT="${ORBIS_KIT_DIR:-}"
[[ -n "$ORBIS_KIT" && -f "$ORBIS_KIT/cmake/ps4-openorbis.cmake" ]] || ORBIS_KIT="${ORBIS_COMPAT}"
ORBIS_TOOLCHAIN_FILE="${ORBIS_KIT}/cmake/ps4-openorbis.cmake"

[[ -f "${ORBIS_TOOLCHAIN_FILE}" && -f "${ORBIS_KIT}/vkloader/vkloader.h" ]] || {
  echo "!! no orbis-compat at ${ORBIS_COMPAT} - clone it, or pass --orbis-compat <dir>" >&2
  exit 1
}

# ⚠ THE KIT'S RUNTIME LIBRARY, AND THIS TITLE IS ONE OF THE THREE THAT CALLS IT. game/main.cpp says
# `#include <orbis_boot.h>` and calls orbis::installCrashHandlers(); ps4/og_ps4_boot.cpp calls
# orbis::probeCtype(). Both names were members of liborbis-compat.a and arrived through
# --whole-archive until 2026-09-20 - which is why this script never had to know about them - and they
# are liborbis-runtime.a's now, linked ON DEMAND, because orbis_boot.cpp defines two orbis:: names and
# no libc name. Measured with `ld.lld --why-extract` on this build: orbis_boot.o is extracted and the
# other three members of that archive are not.
#
# ⚠ BUILT HERE RATHER THAN DEMANDED, because a missing archive is a link error 30 000 lines into an
# OpenGothic build and this is the script people run. runtime/build.sh is idempotent, takes seconds,
# and needs only the overlay and the SDK that this script has already checked for. The toolchain file
# finds the result on its own - it looks in <kit>/runtime/build first and in the portlibs prefix
# second - so nothing below has to name a path.
ORBIS_RUNTIME_DIR="${ORBIS_KIT}/runtime"
if [[ -f "${ORBIS_RUNTIME_DIR}/build.sh" ]]; then
  if [[ ! -f "${ORBIS_RUNTIME_DIR}/build/liborbis-runtime.a" ]]; then
    echo "== building the kit's runtime library (jit, boot, ime, data)"
    "${ORBIS_RUNTIME_DIR}/build.sh" >/dev/null || {
      echo "!! ${ORBIS_RUNTIME_DIR}/build.sh failed - run it directly to see why" >&2; exit 1; }
  fi
else
  # A kit or bundle from before 2026-09-20, where orbis_boot.cpp is still a member of the overlay's
  # archive and arrives force-loaded. Nothing to build, and nothing to say about it.
  :
fi
[[ -f "${ROOT}/lib/Tempest/Engine/system/api/ps4api.h" ]] || {
  echo "!! lib/Tempest has no Orbis SystemApi backend - point it at the Tempest fork" >&2
  exit 1
}
grep -q "VfsMountMode" "${ROOT}/lib/ZenKit/include/zenkit/Vfs.hh" 2>/dev/null || {
  echo "!! lib/ZenKit has no VfsMountMode - point it at the ZenKit fork" >&2
  exit 1
}

# ⚠ CMAKE_POLICY_VERSION_MINIMUM IS FOR A DEPENDENCY, NOT FOR THIS PROJECT.
#
# ZenKit's vendor/CMakeLists.txt fetches doctest unconditionally - not gated on
# ZK_BUILD_TESTS - and doctest 2.4.9 declares a cmake_minimum_required that CMake 4 refuses
# outright, so the configure stops before anything of ours is read. ZK_BUILD_TESTS=OFF is
# passed anyway so the suite is not built for a console that cannot run it.
#
# The flag lowers the policy floor for the whole tree, which is blunt; it is here rather
# than in ZenKit because a cross-build should not be the thing that changes how a library
# fetches its test framework.
mkdir -p "${BUILD}"

# ⚠ THE DRIVER IS PASSED, NOT LEFT TO A DEFAULT. vkloader/CMakeLists.txt defaults
# ORBIS_MESA_BUILD to ~/.cache/orbis-mesa/mesa/build-orbis - the patch-queue era's path, which on
# 2026-08-23 still held a driver from the previous day. Nothing announced it; the title would simply
# have linked the wrong RADV and every measurement taken from the run would have been about changes
# it did not contain. orbis-env.sh resolves the checkout; this prints what it found.
orbis_announce_driver

echo "== configuring ${BUILD}"
cmake -S "${ROOT}" -B "${BUILD}" \
      -DCMAKE_TOOLCHAIN_FILE="${ORBIS_TOOLCHAIN_FILE}" \
      -DORBIS_KIT_DIR="${ORBIS_KIT}" \
      -DORBIS_COMPAT_DIR="${ORBIS_COMPAT}" \
      -DORBIS_MESA_BUILD="${ORBIS_MESA_BUILD}" \
      -DORBIS_MESA_SRC="${ORBIS_MESA_DIR}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DPS4_BUILD_PKG=ON \
      -DZK_BUILD_TESTS=OFF \
      -DOG_SOUND_NULL="${SOUND_NULL}" \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5

echo "== building"
cmake --build "${BUILD}" --target Gothic2Notr -j "${JOBS}"

echo
echo "ELF:   ${BUILD}/opengothic/Gothic2Notr.elf"
echo "eboot: ${BUILD}/opengothic/eboot.bin"
echo "pkg:   ${BUILD}/opengothic/TMPS10021.pkg (when PkgTool.Core is present)"
