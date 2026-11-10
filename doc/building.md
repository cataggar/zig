# Building Zig from Source

## Building `wazig` and `wazigl` (`wasm64-wasip3`)

To build the self-hosted WebAssembly compiler (`wazig.wasm`) using a host Zig 0.17.1 binary (`$HOST_ZIG`):

```sh
# 1. Build stage3-host compiler
ZIG_LIB_DIR="$PWD/lib" "$HOST_ZIG" build \
  --prefix stage3-host \
  -Denable-llvm=false \
  -Duse-llvm=true \
  -Doptimize=ReleaseFast \
  -Dno-langref

# 2. Cross-compile stage3-wazig for wasm64-wasip3
./stage3-host/bin/zig build \
  --prefix stage3-wazig \
  -Dtarget=wasm64-wasip3 \
  -Denable-llvm=false \
  -Duse-llvm=false \
  -Doptimize=ReleaseSafe \
  -Dstrip \
  -Dno-langref
```

To build `wazigl.wasm` with static LLVM, Clang, and LLD linked in (requiring `$HOST_LLVM_PREFIX` for the host and `$WASM_LLVM_PREFIX` built for `wasm64-wasi`):

```sh
# 1. Build stage3-host compiler with LLVM
ZIG_LIB_DIR="$PWD/lib" "$HOST_ZIG" build \
  --prefix stage3-host \
  --search-prefix "$HOST_LLVM_PREFIX" \
  -Denable-llvm=true \
  -Dstatic-llvm \
  -Duse-zig-libcxx \
  -Doptimize=ReleaseFast \
  -Dstrip \
  -Dno-langref

# 2. Cross-compile stage3-wazigl for wasm64-wasip3 with static Wasm LLVM
./stage3-host/bin/zig build \
  --prefix stage3-wazigl \
  --search-prefix "$WASM_LLVM_PREFIX" \
  -Dtarget=wasm64-wasip3 \
  -Denable-llvm=true \
  -Dstatic-llvm \
  -Duse-llvm=false \
  -Duse-zig-libcxx \
  -Doptimize=ReleaseSafe \
  -Dstrip \
  -Dno-langref
```

Package either build into `<flavor>.tar.zst` and `<flavor>.tar.zst.ghr`:

```sh
python3 scripts/package_wazig_bundle.py \
  --flavor wazig \
  --stage-prefix stage3-wazig \
  --out-dir dist
```

## Building from Source (CMake)

Ensure you have the required dependencies:

 * CMake >= 3.15
 * System C/C++ Toolchain
 * LLVM, Clang, LLD development libraries, version 22.x, compiled with the
   same system C/C++ toolchain.
   - If the system package manager lacks these libraries, or has them misconfigured,
     see below for how to build them from source.

Then it is the standard CMake build process:

```sh
mkdir build
cd build
cmake ..
make install
```

Use `CMAKE_PREFIX_PATH` if needed to help CMake find LLVM.

This produces `stage3/bin/zig` which is the Zig compiler built by itself.

## Building from Source without LLVM

In this case, the only system dependency is a C compiler.

```sh
cc -o bootstrap bootstrap.c
./bootstrap
```

This produces a `zig2` executable in the current working directory. This is a
"stage2" build of the compiler,
[without LLVM extensions](https://github.com/ziglang/zig/issues/16270), and is
therefore lacking these features:
- Release mode optimizations
- [Some ELF linking features](https://github.com/ziglang/zig/issues/17749)
- [Some COFF/PE linking features](https://github.com/ziglang/zig/issues/17751)
- [Some WebAssembly linking features](https://github.com/ziglang/zig/issues/17750)
- [Ability to create static archives from object files](https://github.com/ziglang/zig/issues/9828)
- [Ability to compile assembly files](https://github.com/ziglang/zig/issues/21169)
- Ability to compile C, C++, Objective-C, and Objective-C++ files

Even when built this way, Zig provides an LLVM backend that produces bitcode
files, which may be optimized and compiled into object files via separately
installed Clang. Similarly, Zig provides a C backend that produces C source
code, which may be optimized and compiled into object files via a separately
installed C compiler toolchain.

From here you can tinker with `zig2` or you can proceed to installation using
the build system as usual:

```sh
./zig2 build
```

However, due to the above listed caveats, it is recommended to not proceed to
this step until this issue is resolved:

[completely eliminate dependency on LLVM library API calls](https://github.com/ziglang/zig/issues/25492)

## Building from Source Using Prebuilt Zig

Dependencies:

 * A recent prior build of Zig. The exact version required depends on how
   recently breaking changes occurred. If the language or std lib changed too
   much since this version, then this method of building from source will fail.
 * LLVM, Clang, and LLD libraries built using Zig.

The easiest way to obtain both of these artifacts is to use
[zig-bootstrap](https://codeberg.org/ziglang/zig-bootstrap), which creates the
directory `out/zig-$target-$cpu` and `out/$target-$cpu`, to be used as
`$ZIG_PREFIX` and `$LLVM_PREFIX`, respectively, in the following command:

```sh
"$ZIG_PREFIX/zig" build \
  -p stage3 \
  --search-prefix "$LLVM_PREFIX" \
  --zig-lib lib \
  -Dstatic-llvm
```

Where `$LLVM_PREFIX` is the path that contains, for example,
`include/llvm/Pass.h` and `lib/libLLVMCore.a`.

This produces `stage3/bin/zig`. See `zig build -h` to learn about the options
that can be passed such as `-Drelease`.

## Building from Source on Windows

### Option 1: Use the Windows Zig Compiler Dev Kit

This one has the benefit that LLVM, LLD, and Clang are built in Release mode,
while your Zig build has the option to be a Debug build. It also works
completely independently from MSVC so you don't need it to be installed.

Determine the URL by
[looking at the CI script](https://codeberg.org/ziglang/zig/src/branch/master/ci/x86_64-windows-debug.ps1#L1-L4).
It will look something like this (replace `$VERSION` with the one you see by
following the above link):

```
https://ziglang.org/deps/zig+llvm+lld+clang-x86_64-windows-gnu-$VERSION.zip
```

This zip file contains:

 * An older Zig installation.
 * LLVM, LLD, and Clang libraries (.lib and .h files), version 16.0.1, built in Release mode.
 * zlib (.lib and .h files), v1.2.13, built in Release mode
 * zstd (.lib and .h files), v1.5.2, built in Release mode

#### Option 1a: CMake + [Ninja](https://ninja-build.org/)

Unzip the dev kit and then in cmd.exe in your Zig source checkout:

```bat
mkdir build
cd build
set DEVKIT=$DEVKIT
```

Replace `$DEVKIT` with the path to the folder that you unzipped after
downloading it from the link above. Make sure to use forward slashes (`/`) for
all path separators (otherwise CMake will try to interpret backslashes as
escapes and fail).

Then run:

```bat
cmake .. -GNinja -DCMAKE_PREFIX_PATH="%DEVKIT%" -DCMAKE_C_COMPILER="%DEVKIT%/bin/zig.exe;cc" -DCMAKE_CXX_COMPILER="%DEVKIT%/bin/zig.exe;c++" -DCMAKE_AR="%DEVKIT%/bin/zig.exe" -DZIG_AR_WORKAROUND=ON -DZIG_STATIC=ON -DZIG_USE_LLVM_CONFIG=OFF
```

 * Append `-DCMAKE_BUILD_TYPE=Release` for a Release build.
 * Append `-DZIG_NO_LIB=ON` to avoid having multiple copies of the lib/ folder.

Finally, run:

```bat
ninja install
```

You now have the `zig.exe` binary at `stage3\bin\zig.exe`.

#### Option 1b: zig build

Unzip the dev kit and then in cmd.exe in your Zig source checkout:

```bat
$DEVKIT\bin\zig.exe build -p stage3 --search-prefix $DEVKIT --zig-lib lib -Dstatic-llvm -Duse-zig-libcxx -Dtarget=x86_64-windows-gnu
```

Replace `$DEVKIT` with the path to the folder that you unzipped after
downloading it from the link above.

Append `-Doptimize=ReleaseSafe` for a Release build.

**If you get an error building at this step**, it is most likely that the Zig
installation inside the dev kit is too old, and the dev kit needs to be
updated. In this case one more step is required:

 1. [Download the latest master branch zip file](https://ziglang.org/download/#release-master).
 2. Unzip, and try the above command again, replacing the path to zig.exe with
    the path to the zig.exe you just extracted, and also replace the lib\zig
    folder with the new contents.

You now have the `zig.exe` binary at `stage3\bin\zig.exe`.

### Option 2: Using CMake and Microsoft Visual Studio

This one has the benefit that changes to the language or build system won't
break your dev kit. This option can be used to upgrade a dev kit.

First, build LLVM, LLD, and Clang from source using CMake and Microsoft Visual
Studio (see below for detailed instructions).

Install [Build Tools for Visual Studio
2019](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2019).
Be sure to select "Desktop development with C++" when prompted.
 * You must additionally check the optional component labeled **C++ ATL for
   v142 build tools**.

Install [CMake](http://cmake.org).

Use [git](https://git-scm.com/) to clone the zig repository to a path with no spaces, e.g. `C:\Users\Andy\zig`.

Using the start menu, run **x64 Native Tools Command Prompt for VS 2019** and execute these commands, replacing `C:\Users\Andy` with the correct value.

```bat
mkdir C:\Users\Andy\zig\build-release
cd C:\Users\Andy\zig\build-release
"c:\Program Files\CMake\bin\cmake.exe" .. -Thost=x64 -G "Visual Studio 16 2019" -A x64 -DCMAKE_PREFIX_PATH=C:\Users\Andy\llvm+clang+lld-20.0.0-x86_64-windows-msvc-release-mt -DCMAKE_BUILD_TYPE=Release
msbuild -p:Configuration=Release INSTALL.vcxproj
```

You now have the `zig.exe` binary at `bin\zig.exe` and you can run the tests:

```bat
bin\zig.exe build test
```

This can take a long time.

Note: In case you get the error "llvm-config not found" (or similar), make sure
that you have **no** trailing slash (`/` or `\`) at the end of the
`-DCMAKE_PREFIX_PATH` value.

## Building LLVM, LLD, and Clang from Source

### Windows

Install [CMake](https://cmake.org/), version 3.20.0 or newer.

[Download LLVM, Clang, and LLD sources](https://releases.llvm.org/download.html#22.0.0)
The downloads from llvm lead to the github release pages, where the source's
will be listed as : `llvm-22.X.X.src.tar.xz`, `clang-22.X.X.src.tar.xz`,
`lld-22.X.X.src.tar.xz`. Unzip each to their own directory. Ensure no
directories have spaces in them. For example:

 * `C:\Users\Andy\llvm-22.0.0.src`
 * `C:\Users\Andy\clang-22.0.0.src`
 * `C:\Users\Andy\lld-22.0.0.src`

Install [Build Tools for Visual Studio
2019](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2019).
Be sure to select "C++ build tools" when prompted.
 * You **must** additionally check the optional component labeled **C++ ATL for
   v142 build tools**. As this won't be supplied by a default installation of
   Visual Studio.
 * Full list of supported MSVC versions:
   - 2017 (version 15.8) (unverified)
   - 2019 (version 16.7)

Install [Python 3.9.4](https://www.python.org). Tick the box to add python to
your PATH environment variable.

#### LLVM

Using the start menu, run **x64 Native Tools Command Prompt for VS 2019** and execute these commands, replacing `C:\Users\Andy` with the correct value. Here is listed a brief explanation of each of the CMake parameters we pass when configuring the build

- `-Thost=x64` : Sets the windows toolset to use 64 bit mode.
- `-A x64` : Make the build target 64 bit .
- `-G "Visual Studio 16 2019"` : Specifies to generate a 2019 Visual Studio project, the best supported version.
- `-DCMAKE_INSTALL_PREFIX=""` : Path that llvm components will being installed into by the install project.
- `-DCMAKE_PREFIX_PATH=""` : Path that CMake will look into first when trying to locate dependencies, should be the same place as the install prefix. This will ensure that clang and lld will use your newly built llvm libraries.
- `-DLLVM_ENABLE_ZLIB=OFF` : Don't build llvm with ZLib support as it's not required and will disrupt the target dependencies for components linking against llvm. This only has to be passed when building llvm, as this option will be saved into the config headers.
- `-DCMAKE_BUILD_TYPE=Release` : Build llvm and components in release mode.
- `-DCMAKE_BUILD_TYPE=Debug` : Build llvm and components in debug mode.
- `-DLLVM_USE_CRT_RELEASE=MT` : Which C runtime should llvm use during release builds.
- `-DLLVM_USE_CRT_DEBUG=MTd` : Make llvm use the debug version of the runtime in debug builds.

##### Release Mode

```bat
mkdir C:\Users\Andy\llvm-22.0.0.src\build-release
cd C:\Users\Andy\llvm-22.0.0.src\build-release
"c:\Program Files\CMake\bin\cmake.exe" .. -Thost=x64 -G "Visual Studio 16 2019" -A x64 -DCMAKE_INSTALL_PREFIX=C:\Users\Andy\llvm+clang+lld-22.0.0-x86_64-windows-msvc-release-mt -DCMAKE_PREFIX_PATH=C:\Users\Andy\llvm+clang+lld-22.0.0-x86_64-windows-msvc-release-mt -
DLLVM_ENABLE_ZLIB=OFF -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_USE_CRT_RELEASE=MT
msbuild /m -p:Configuration=Release INSTALL.vcxproj
```

##### Debug Mode

```bat
mkdir C:\Users\Andy\llvm-22.0.0.src\build-debug
cd C:\Users\Andy\llvm-22.0.0.src\build-debug
"c:\Program Files\CMake\bin\cmake.exe" .. -Thost=x64 -G "Visual Studio 16 2019" -A x64 -DCMAKE_INSTALL_PREFIX=C:\Users\andy\llvm+clang+lld-22.0.0-x86_64-windows-msvc-debug -
DLLVM_ENABLE_ZLIB=OFF -DCMAKE_PREFIX_PATH=C:\Users\andy\llvm+clang+lld-22.0.0-x86_64-windows-msvc-debug -DCMAKE_BUILD_TYPE=Debug -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="AVR" -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_USE_CRT_DEBUG=MTd
msbuild /m INSTALL.vcxproj
```

#### LLD

Using the start menu, run **x64 Native Tools Command Prompt for VS 2019** and execute these commands, replacing `C:\Users\Andy` with the correct value.

##### Release Mode

```bat
mkdir C:\Users\Andy\lld-22.0.0.src\build-release
cd C:\Users\Andy\lld-22.0.0.src\build-release
"c:\Program Files\CMake\bin\cmake.exe" .. -Thost=x64 -G "Visual Studio 16 2019" -A x64 -DCMAKE_INSTALL_PREFIX=C:\Users\Andy\llvm+clang+lld-14.0.6-x86_64-windows-msvc-release-mt -DCMAKE_PREFIX_PATH=C:\Users\Andy\llvm+clang+lld-22.0.0-x86_64-windows-msvc-release-mt -DCMAKE_BUILD_TYPE=Release -DLLVM_USE_CRT_RELEASE=MT
msbuild /m -p:Configuration=Release INSTALL.vcxproj
```

##### Debug Mode

```bat
mkdir C:\Users\Andy\lld-22.0.0.src\build-debug
cd C:\Users\Andy\lld-22.0.0.src\build-debug
"c:\Program Files\CMake\bin\cmake.exe" .. -Thost=x64 -G "Visual Studio 16 2019" -A x64 -DCMAKE_INSTALL_PREFIX=C:\Users\andy\llvm+clang+lld-22.0.0-x86_64-windows-msvc-debug -DCMAKE_PREFIX_PATH=C:\Users\andy\llvm+clang+lld-22.0.0-x86_64-windows-msvc-debug -DCMAKE_BUILD_TYPE=Debug -DLLVM_USE_CRT_DEBUG=MTd
msbuild /m INSTALL.vcxproj
```

#### Clang

Using the start menu, run **x64 Native Tools Command Prompt for VS 2019** and execute these commands, replacing `C:\Users\Andy` with the correct value.

##### Release Mode

```bat
mkdir C:\Users\Andy\clang-22.0.0.src\build-release
cd C:\Users\Andy\clang-22.0.0.src\build-release
"c:\Program Files\CMake\bin\cmake.exe" .. -Thost=x64 -G "Visual Studio 16 2019" -A x64 -DCMAKE_INSTALL_PREFIX=C:\Users\Andy\llvm+clang+lld-22.0.0-x86_64-windows-msvc-release-mt -DCMAKE_PREFIX_PATH=C:\Users\Andy\llvm+clang+lld-22.0.0-x86_64-windows-msvc-release-mt -DCMAKE_BUILD_TYPE=Release -DLLVM_USE_CRT_RELEASE=MT
msbuild /m -p:Configuration=Release INSTALL.vcxproj
```

##### Debug Mode

```bat
mkdir C:\Users\Andy\clang-22.0.0.src\build-debug
cd C:\Users\Andy\clang-22.0.0.src\build-debug
"c:\Program Files\CMake\bin\cmake.exe" .. -Thost=x64 -G "Visual Studio 16 2019" -A x64 -DCMAKE_INSTALL_PREFIX=C:\Users\andy\llvm+clang+lld-22.0.0-x86_64-windows-msvc-debug -DCMAKE_PREFIX_PATH=C:\Users\andy\llvm+clang+lld-22.0.0-x86_64-windows-msvc-debug -DCMAKE_BUILD_TYPE=Debug -DLLVM_USE_CRT_DEBUG=MTd
msbuild /m INSTALL.vcxproj
```

### POSIX Systems

This guide will get you both a Debug build of LLVM, and/or a Release build of LLVM.
It intentionally does not require privileged access, using a prefix inside your home
directory instead of a global installation.

#### Release

This is the generally recommended approach.

```sh
cd ~/Downloads
git clone --depth 1 --branch release/22.x https://github.com/llvm/llvm-project llvm-project-22
cd llvm-project-22
git checkout release/22.x

mkdir build-release
cd build-release
cmake ../llvm \
  -DCMAKE_INSTALL_PREFIX=$HOME/local/llvm22-assert \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS="lld;clang" \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_ASSERTIONS=ON \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_PARALLEL_LINK_JOBS=1 \
  -G Ninja
ninja install
```

#### Debug

This is occasionally needed when debugging Zig's LLVM backend. Here we build
the three projects separately so that LLVM can be in Debug mode while the
others are in Release mode.

```sh
cd ~/Downloads
git clone --depth 1 --branch release/22.x https://github.com/llvm/llvm-project llvm-project-22
cd llvm-project-22
git checkout release/22.x

# LLVM
mkdir llvm/build-debug
cd llvm/build-debug
cmake .. \
  -DCMAKE_INSTALL_PREFIX=$HOME/local/llvm22-debug \
  -DCMAKE_PREFIX_PATH=$HOME/local/llvm22-debug \
  -DCMAKE_BUILD_TYPE=Debug \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_PARALLEL_LINK_JOBS=1 \
  -G Ninja
ninja install
cd ../..

# LLD
mkdir lld/build-debug
cd lld/build-debug
cmake .. \
  -DCMAKE_INSTALL_PREFIX=$HOME/local/llvm22-debug \
  -DCMAKE_PREFIX_PATH=$HOME/local/llvm22-debug \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_PARALLEL_LINK_JOBS=1 \
  -DCMAKE_CXX_STANDARD=17 \
  -G Ninja
ninja install
cd ../..

# Clang
mkdir clang/build-debug
cd clang/build-debug
cmake .. \
  -DCMAKE_INSTALL_PREFIX=$HOME/local/llvm22-debug \
  -DCMAKE_PREFIX_PATH=$HOME/local/llvm22-debug \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_PARALLEL_LINK_JOBS=1 \
  -DLLVM_INCLUDE_TESTS=OFF \
  -G Ninja
ninja install
cd ../..
```

Then add to your Zig CMake line:
`-DCMAKE_PREFIX_PATH=$HOME/local/llvm22-debug` or
`-DCMAKE_PREFIX_PATH=$HOME/local/llvm22-assert` depending on whether you want
Debug or Release LLVM.
