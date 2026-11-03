# Debugging, Testing, and Development Guide

## Editing Source Code

For a smooth workflow, when building from source, it is recommended to use
CMake with the following settings:

 * `-DCMAKE_BUILD_TYPE=Release` - to recompile zig faster.
 * `-GNinja` - Ninja is faster and simpler to use than Make.
 * `-DZIG_NO_LIB=ON` - Prevents the build system from copying the lib/
   directory to the installation prefix, causing zig use lib/ directly from the
   source tree instead. Effectively, this makes it so that changes to lib/ do
   not require re-running the install command to become active.

After configuration, there are two scenarios:

 1. Pulling upstream changes and rebuilding.
    - In this case use `git pull` and then `ninja install`. Expected wait:
      about 10 minutes.
 2. Building from source after making local changes.
    - In this case use `stage3/bin/zig build -p stage4 -Denable-llvm -Dno-lib`.
      Expected wait: about 20 seconds.

This leaves you with two builds of Zig:

 * `stage3/bin/zig` - an optimized master branch build. Useful for
   miscellaneous activities such as `zig fmt`, as well as for building the
   compiler itself after changing the source code.
 * `stage4/bin/zig` - a debug build that includes your local changes; useful
   for testing and eliminating bugs before submitting a patch.

To reduce time spent waiting for the compiler to build, try these techniques:

 * Omit `-Denable-llvm` if you don't need the LLVM backend.
 * Use `-Ddev=foo` to build with a reduced feature set for development of
   specific features (for example `-Ddev=wasm`). See `zig build -h` for a list of options.
 * Use `--watch -fincremental` to enable incremental compilation. This offers
   **near instant rebuilds**.

## Testing

```sh
stage4/bin/zig build test
```

This command runs the whole test suite, which does a lot of extra testing that
you likely won't always need, and can take upwards of 1 hour. This is what the
CI server runs when you make a pull request.

To save time, you can add the `--help` option to the `zig build` command and
see what options are available. One of the most helpful ones is
`-Dskip-release`. Adding this option to the command above, along with
`-Dskip-non-native`, will take the time down from around 2 hours to about 30
minutes, and this is a good enough amount of testing before making a pull
request.

Another example is choosing a different set of things to test. For example,
`test-std` instead of `test` will only run the standard library tests, and
not the other ones. Combining this suggestion with the previous one, you could
do this:

```sh
stage4/bin/zig build test-std -Dskip-release
```

This will run only the standard library tests in debug mode for all targets.
It will cross-compile the tests for non-native targets but not run them.

When making changes to the compiler source code, the most helpful test step to
run is `test-behavior`. When editing documentation it is `docs`. You can find
this information and more in the `zig build --help` menu.

### Directly Testing the Standard Library with `zig test`

This command will run the standard library tests with only the native target
configuration and is estimated to complete in 3 minutes:

```sh
zig build test-std -Dno-matrix
```

However, one may also use `zig test` directly. From inside the repo root:

```sh
zig test lib/std/std.zig --zig-lib-dir lib
```

You can add `--test-filter "some test name"` to run a specific test or a subset of tests.
(Running exactly 1 test is not reliably possible, because the test filter does not
exclude anonymous test blocks, but that shouldn't interfere with whatever
you're trying to test in practice.)

Note that `--test-filter` filters on fully qualified names, so e.g. it's possible to run only the `std.json` tests with:

```sh
zig test lib/std/std.zig --zig-lib-dir lib --test-filter "json."
```

If you used `-Dno-lib` and you are in a `build/` subdirectory, you can omit the
`--zig-lib-dir` argument:

```sh
stage3/bin/zig test ../lib/std/std.zig
```

### Testing Non-Native Architectures with QEMU

The Linux CI server additionally has qemu installed and sets `-fqemu`.
This provides test coverage for, e.g. aarch64 even on x86_64 machines. It's
recommended for Linux users to install qemu and enable this testing option
when editing the standard library or anything related to a non-native
architecture.

QEMU packages provided by some system package managers (such as Debian) may be
a few releases old, or may be missing newer targets such as aarch64 and RISC-V.
[ziglang/qemu-static](https://codeberg.org/ziglang/qemu-static) offers static
binaries of the latest QEMU version.

#### Testing Non-Native libc Targets

Testing foreign architectures with dynamically linked libc is one step trickier.
This requires enabling `--libc-runtimes /path/to/libcs`. This path is obtained
by building glibc and musl for multiple architectures. This process for me took
an entire day to complete and takes up 65 GiB on my hard drive.

[Instructions for producing this path.](https://codeberg.org/ziglang/infra/src/branch/master/building-libcs.md)

It is understood that most contributors will not have these tests enabled. The
CI machines provide coverage for these.

### Testing Windows from a Linux Machine with Wine

When developing on Linux, another option is available to you: `-fwine`.
This will enable running behavior tests and std lib tests with Wine. It's
recommended for Linux users to install Wine and enable this testing option
when editing the standard library or anything Windows-related.

### Testing WebAssembly using Wasmtime

If you have [wasmtime](https://wasmtime.dev/) installed, take advantage of the
`-fwasmtime` flag which will enable running WASI behavior tests and std
lib tests. It's recommended for all users to install wasmtime and enable this
testing option when editing the standard library and especially anything
WebAssembly-related.

For WASI Preview 2 (`wasm32-wasip2`) and Preview 3 (`wasm32-wasip3` / `wasm64-wasip3`) Component Model tests:

```sh
# Component linker unit tests
zig test --zig-lib-dir lib -fno-llvm -fno-lld -target wasm32-wasi \
  --test-cmd wasmtime --test-cmd-bin src/link/Wasm/component/root.zig

# WASI Preview 2 E2E test suite
zig test --zig-lib-dir lib -fno-llvm -fno-lld -target wasm32-wasip2 \
  --test-cmd wasmtime --test-cmd=--dir=. --test-cmd-bin test/wasip2_e2e.zig

# WASI Preview 3 (64-bit cm64) E2E test suite
zig test --zig-lib-dir lib -fno-llvm -fno-lld -target wasm64-wasip3 \
  --test-cmd wasmtime \
  --test-cmd=-W --test-cmd=component-model-memory64=y,component-model-async=y,component-model-async-stackful=y,component-model-more-async-builtins=y \
  --test-cmd=-S --test-cmd=p3=y \
  --test-cmd=--dir=. --test-cmd-bin test/wasip3_e2e.zig
```

## Testing Zig Code With LLDB

[@jacobly0](https://github.com/jacobly0) maintains a fork of LLDB with Zig support:

https://github.com/jacobly0/llvm-project/tree/lldb-zig

This fork only contains changes for debugging programs compiled by Zig's
self-hosted backends, i.e. `zig build-exe -fno-llvm ...`.

### Building

To build the LLDB fork, make sure you have
[prerequisites](https://lldb.llvm.org/resources/build.html#preliminaries)
installed, and then do something like:

```sh
$ cmake llvm -G Ninja -B build -DLLVM_ENABLE_PROJECTS="clang;lldb" -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=ON -DLLDB_ENABLE_LIBEDIT=ON -DLLDB_ENABLE_PYTHON=ON
$ cmake --build build --target lldb --target lldb-server
```

(You may need to manually [configure
dependencies](https://lldb.llvm.org/resources/build.html#optional-dependencies)
if CMake can't find them.)

Once built, you can run `./build/bin/lldb` and so on.

### Pretty Printers

If you will be debugging the Zig compiler itself, or if you will be debugging
any project compiled with Zig's LLVM backend (not recommended with the LLDB
fork, prefer vanilla LLDB with a version that matches the version of LLVM that
Zig is using), you can get a better debugging experience by using
[`lldb/pretty_printers.py`](https://codeberg.org/ziglang/zig/src/branch/master/lib/lldb/pretty_printers.py)
which is included in Zig's installed lib dir.

Put this line in `~/.lldbinit`:

```
command script import /path/to/zig/lib/lldb/pretty_printers.py
```

If you will be debugging a Zig compiler built using Zig's self-hosted backends,
you will also want this line:

```
type category enable zig.compiler
```

If you will be using Zig's LLVM backend (again, not recommended with the LLDB
fork), you will also want these lines:

```
type category enable zig.lang
type category enable zig.std
```

If you will be debugging a Zig compiler built using Zig's LLVM backend without
using the LLDB fork, you will also want this line:

```
type category enable zig
```

## Autodoc

Autodoc is an interactive, searchable, single-page web application for browsing
Zig codebases.

An autodoc deployment looks like this:

```
index.html
main.js
main.wasm
sources.tar
```

* `main.js` and `index.html` are static files which live in a Zig installation
  at `lib/docs/`.
* `main.wasm` is compiled from the Zig files inside `lib/docs/wasm/`.
* `sources.tar` is all the zig source files of the project.

These artifacts are produced by the compiler when `-femit-docs` is passed.

### Making Changes

The command `zig std` spawns an HTTP server that provides all the assets
mentioned above specifically for the standard library.

The server creates the requested files on the fly, including rebuilding
`main.wasm` if any of its source files changed, and constructing `sources.tar`,
meaning that any source changes to the documented files, or to the autodoc
system itself are immediately reflected when viewing docs.

This means you can test changes to Zig standard library documentation, as well
as autodocs functionality, by pressing refresh in the browser.

Prefixing the URL with `/debug` results in a debug build of `main.wasm`.

### Debugging the Zig Code

While Firefox and Safari support are obviously required, Chromium is recommended
for development for one reason in particular:

[C/C++ DevTools Support (DWARF)](https://chromewebstore.google.com/detail/cc++-devtools-support-dwa/pdcpmagijalfljmkmjngeonclgbbannb)

This makes debugging Zig WebAssembly code a breeze.

### The Sources Tarball

The system expects the top level of `sources.tar` to be the set of modules
documented. So for the Zig standard library you would do this:
`tar cf std.tar std/`. Don't compress it; the idea is to rely on HTTP
compression.

Any files that are not `.zig` source files will be ignored by `main.wasm`,
however, those files will take up wasted space in the tar file. For the
standard library, use the set of files that zig installs to when running `zig
build`, which is the same as the set of files that are provided on
ziglang.org/download.

If the system doesn't find a file named "foo/root.zig" or "foo/foo.zig", it
will use the first file in the tar as the module root.

You don't typically need to create `sources.tar` yourself, since it is lazily
provided by the `zig std` HTTP server as well as produced by `-femit-docs`.

## Improving Translate-C

`translate-c` is a feature provided by Zig that converts C source code into Zig
source code. It powers the `zig translate-c` command, allowing Zig code to not
only take advantage of function prototypes defined in C header files, but also
`static inline` functions written in C, and even some macros.

It is based on [arocc](https://github.com/Vexu/arocc/), a third-party C
compiler written in Zig. Test coverage, bug reports, and official implementation
live in: [ziglang/translate-c](https://codeberg.org/ziglang/translate-c/).

## Upstream Contributing Guidelines

[Donate monthly](https://ziglang.org/zsf/) · [Join a community](https://ziglang.org/community/)

Zig governance is BDFN (Benevolent Dictator For Now) which means that Andrew
Kelley has final say on the design and implementation of everything.

### Strict No LLM / No AI Policy (Upstream `ziglang/zig`)

No LLMs for issues, patches / pull requests, or comments on the upstream
[codeberg.org/ziglang/zig](https://codeberg.org/ziglang/zig) bug tracker,
including translation.
