import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import package_wazig_bundle


class PackageWazigBundleTests(unittest.TestCase):
    def make_fake_stage_prefix(self, root: Path) -> Path:
        prefix = root / "stage3-wazig"
        (prefix / "bin").mkdir(parents=True)
        (prefix / "bin" / "zig.wasm").write_bytes(b"\x00asm\x01\x00\x00\x00fake-wasm-binary")

        lib_zig = prefix / "lib" / "zig"
        (lib_zig / "std").mkdir(parents=True)
        (lib_zig / "std" / "std.zig").write_text("pub const std = 1;\n", encoding="utf-8")
        (lib_zig / "std" / "test.zig").write_text("", encoding="utf-8")
        (lib_zig / "compiler_rt").mkdir(parents=True)
        (lib_zig / "compiler_rt" / "atomics.zig").write_text("// rt\n", encoding="utf-8")
        (lib_zig / "c").mkdir(parents=True)
        (lib_zig / "c" / "stdlib.zig").write_text("// c\n", encoding="utf-8")
        (lib_zig / "compiler" / "aro").mkdir(parents=True)
        (lib_zig / "compiler" / "Maker.zig").write_text("// maker\n", encoding="utf-8")
        (lib_zig / "compiler" / "test_runner.zig").write_text("// test_runner\n", encoding="utf-8")
        (lib_zig / "compiler" / "aro" / "aro.zig").write_text("// aro\n", encoding="utf-8")
        (lib_zig / "init").mkdir(parents=True)
        (lib_zig / "init" / "build.zig").write_text("// init\n", encoding="utf-8")
        (lib_zig / "libc" / "include" / "wasm-wasi-musl").mkdir(parents=True)
        (lib_zig / "libc" / "include" / "wasm-wasi-musl" / "stdlib.h").write_text("/* wasi */\n", encoding="utf-8")
        (lib_zig / "libc" / "include" / "generic-musl").mkdir(parents=True)
        (lib_zig / "libc" / "include" / "generic-musl" / "stdio.h").write_text("/* musl */\n", encoding="utf-8")

        # Native libc / C++ headers that should NOT be packaged into the Wasm subset:
        (lib_zig / "libc" / "glibc").mkdir(parents=True)
        (lib_zig / "libc" / "glibc" / "dummy.c").write_text("/* glibc */\n", encoding="utf-8")
        (lib_zig / "libcxx" / "include").mkdir(parents=True)
        (lib_zig / "libcxx" / "include" / "vector").write_text("/* cxx */\n", encoding="utf-8")

        for rel_file in package_wazig_bundle.REQUIRED_LIB_FILES:
            (lib_zig / rel_file).write_text(f"// {rel_file}\n", encoding="utf-8")

        inc = lib_zig / "include"
        inc.mkdir(parents=True)
        (inc / "stddef.h").write_text("/* stddef */\n", encoding="utf-8")
        (inc / "stdint.h").write_text("/* stdint */\n", encoding="utf-8")
        (inc / "wasm_simd128.h").write_text("/* simd */\n", encoding="utf-8")
        (inc / "__stddef_size_t.h").write_text("/* size_t */\n", encoding="utf-8")
        # Non-Wasm architecture header that should NOT be copied:
        (inc / "arm_neon.h").write_text("/* arm_neon */\n", encoding="utf-8")
        (inc / "avx512fintrin.h").write_text("/* avx512 */\n", encoding="utf-8")
        return prefix

    def test_packages_archive_and_external_sidecar(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            prefix = self.make_fake_stage_prefix(root)
            out_dir = root / "dist"

            archive_path, sidecar_path = package_wazig_bundle.package_bundle("wazig", prefix, out_dir)
            self.assertEqual(archive_path, out_dir / "wazig.tar.zst")
            self.assertEqual(sidecar_path, out_dir / "wazig.tar.zst.ghr")

            members = package_wazig_bundle.verify_bundle(archive_path, sidecar_path, "wazig")
            self.assertIn("wazig.wasm", members)
            self.assertIn("lib/std/std.zig", members)
            self.assertIn("lib/include/wasm_simd128.h", members)
            self.assertNotIn("lib/include/arm_neon.h", members)
            self.assertNotIn("lib/include/avx512fintrin.h", members)
            self.assertFalse(any(m.startswith("lib/libc/glibc") for m in members))
            self.assertFalse(any(m.endswith(".ghr") for m in members))
            self.assertEqual(list(out_dir.glob("*.minisig")), [])

    def test_fails_when_required_subset_entry_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            prefix = self.make_fake_stage_prefix(root)
            (prefix / "lib" / "zig" / "ubsan_rt.zig").unlink()
            out_dir = root / "dist"

            with self.assertRaises(FileNotFoundError):
                package_wazig_bundle.package_bundle("wazig", prefix, out_dir)

    def test_rejects_excluded_testdata_extension_in_staged_lib(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            prefix = self.make_fake_stage_prefix(root)
            (prefix / "lib" / "zig" / "std" / "bad.tzif").write_bytes(b"tzif")
            out_dir = root / "dist"

            with self.assertRaises(ValueError):
                package_wazig_bundle.package_bundle("wazig", prefix, out_dir)

    def test_rejects_stale_minisig_in_out_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            prefix = self.make_fake_stage_prefix(root)
            out_dir = root / "dist"
            out_dir.mkdir(parents=True)
            (out_dir / "wazig.wasm.minisig").write_text("untrusted comment\n", encoding="utf-8")

            with self.assertRaises(ValueError):
                package_wazig_bundle.package_bundle("wazig", prefix, out_dir)

    def test_ghr_shim_expands_tool_dir_with_spaces(self) -> None:
        ghr_bin = shutil.which("ghr") or "/home/g/.local/bin/ghr"
        if not Path(ghr_bin).is_file():
            self.skipTest("ghr binary not available")

        ghr_bytes = Path(ghr_bin).read_bytes()
        magic = b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        pos = ghr_bytes.find(magic, 16)
        self.assertGreater(pos, 0, "Expected embedded ELF64 shim inside ghr binary")
        e_shoff, _, _, _, _, e_shentsize, e_shnum, _ = struct.unpack_from("<QIHHHHHH", ghr_bytes, pos + 40)
        shim_bytes = ghr_bytes[pos : pos + e_shoff + e_shentsize * e_shnum]

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bundle_dir = root / "extracted wazig" / "_unit"
            shim_bin_dir = root / "extracted wazig" / "bin"
            fake_rt_dir = root / "fake-rt"
            (bundle_dir / "lib").mkdir(parents=True)
            shim_bin_dir.mkdir(parents=True)
            fake_rt_dir.mkdir(parents=True)

            fake_wasmtime = fake_rt_dir / "wasmtime"
            fake_wasmtime.write_text('#!/bin/sh\nfor a in "$@"; do printf "%s\\n" "$a"; done\n', encoding="utf-8")
            fake_wasmtime.chmod(0o755)

            shim_exe = shim_bin_dir / "wazig"
            shim_exe.write_bytes(shim_bytes)
            shim_exe.chmod(0o755)

            target_wasm = bundle_dir / "wazig.wasm"
            target_wasm.write_bytes(b"\x00asm\x01\x00\x00\x00")

            manifest_text = package_wazig_bundle.GHR_MANIFEST_CONTENT.replace(
                ".version = 1,\n",
                f'.version = 1,\n    .targetWasm = "{target_wasm}",\n',
                1,
            )
            self.assertIn('"--dir=${GHR_TOOL_DIR}/lib::/lib"', manifest_text)
            (shim_bin_dir / "wazig.ghr").write_text(manifest_text, encoding="utf-8")

            env = os.environ.copy()
            env["PATH"] = f"{fake_rt_dir}:" + env.get("PATH", "")
            res = subprocess.run([str(shim_exe), "version"], env=env, capture_output=True, text=True, check=True)
            forwarded_args = res.stdout.splitlines()

            self.assertIn(f"--dir={bundle_dir}/lib::/lib", forwarded_args)
            self.assertIn("--dir=.", forwarded_args)
            self.assertIn(str(target_wasm), forwarded_args)
            self.assertEqual(forwarded_args[-1], "version")


if __name__ == "__main__":
    unittest.main()
