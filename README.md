# NSSM

NSSM (the Non-Sucking Service Manager) runs ordinary applications as Windows
services, restarts them after failures, redirects their I/O, and provides both
command-line and graphical service management.

This repository is an adaptation of NSSM's original build system to CMake. The
program's usage documentation remains available in [README.txt](README.txt).

## Build

CMake 3.20 or newer is required. Native Windows builds need Visual Studio with
the C++ tools and Windows SDK installed.

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A Win32
cmake --build build --config Release
```

Use `-A x64` for a 64-bit build.

Linux cross-builds require MinGW-w64, including `windres` and `windmc`. Toolchain
files for both architectures are included:

```sh
cmake -S . -B build-mingw-x86 \
  -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-mingw-x86.cmake \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build-mingw-x86 -j
```

Replace `x86` with `x64` in the build directory and toolchain filename for a
64-bit cross-build. If the message compiler is installed in a non-standard
location, pass `-DMC_COMPILER=/full/path/to/mc` when configuring.

## Basic usage

```text
nssm install <service-name> <application> [arguments]
nssm edit <service-name>
nssm remove <service-name>
```
