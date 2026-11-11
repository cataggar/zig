from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import package_zigc_bundle


def make_fake_elf64(e_machine: int, *, with_interp: bool = False) -> bytes:
    """Build a minimal ELF64 little-endian header with optional PT_INTERP program header."""
    e_ident = b"\x7fELF\x02\x01\x01" + b"\x00" * 9
    phentsize = 56
    phdrs = [
        # PT_LOAD = 1
        struct.pack("<IIQQQQQQ", 1, 5, 0, 0x400000, 0x400000, 128, 128, 0x1000),
    ]
    if with_interp:
        phdrs.append(struct.pack("<IIQQQQQQ", package_zigc_bundle.PT_INTERP, 4, 0, 0, 0, 16, 16, 1))
    ehdr = package_zigc_bundle.ELF64_EHDR_STRUCT.pack(
        e_ident,
        package_zigc_bundle.ET_EXEC,
        e_machine,
        1,
        0x401000,
        package_zigc_bundle.ELF64_EHDR_STRUCT.size,
        0,
        0,
        package_zigc_bundle.ELF64_EHDR_STRUCT.size,
        phentsize,
        len(phdrs),
        0,
        0,
        0,
    )
    return ehdr + b"".join(phdrs) + b"fake-zigc-code"


class PackageZigcBundleTests(unittest.TestCase):
    def make_fake_flat_prefix(self, root: Path, target: str = "x86_64-linux", *, with_interp: bool = False) -> Path:
        prefix = root / f"stage3-{target}"
        prefix.mkdir(parents=True)
        e_machine = package_zigc_bundle.TARGET_ELF_MACHINE[target]
        exe = prefix / "zig"
        exe.write_bytes(make_fake_elf64(e_machine, with_interp=with_interp))
        exe.chmod(0o755)

        (prefix / "LICENSE").write_text("MIT License\n", encoding="utf-8")
        (prefix / "README.md").write_text("# Zig\n", encoding="utf-8")

        lib_dir = prefix / "lib"
        for rel in package_zigc_bundle.REQUIRED_REL_MEMBERS:
            if not rel.startswith("lib/"):
                continue
            dst = prefix / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(f"// {rel}\n", encoding="utf-8")

        # Native Linux headers should be preserved in the full -Dflat lib/ bundle.
        glibc_hdr = lib_dir / "libc" / "include" / "x86_64-linux-gnu" / "gnu" / "stubs.h"
        glibc_hdr.parent.mkdir(parents=True, exist_ok=True)
        glibc_hdr.write_text("/* glibc stubs */\n", encoding="utf-8")
        return prefix

    def test_packages_x86_64_and_aarch64_bundles(self) -> None:
        version = "0.17.1-zigc.1"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            out_dir = root / "dist"
            for target in ("x86_64-linux", "aarch64-linux"):
                prefix = self.make_fake_flat_prefix(root, target=target)
                archive = package_zigc_bundle.package_bundle(target, version, prefix, out_dir)
                bundle_name = f"zigc-{target}-{version}"
                self.assertEqual(archive, out_dir / f"{bundle_name}.tar.zst")

                members = package_zigc_bundle.verify_bundle(archive, target, version)
                self.assertIn(f"{bundle_name}/zigc", members)
                self.assertNotIn(f"{bundle_name}/zig", members)
                self.assertIn(f"{bundle_name}/LICENSE", members)
                self.assertIn(f"{bundle_name}/README.md", members)
                self.assertIn(f"{bundle_name}/lib/std/std.zig", members)
                self.assertIn(f"{bundle_name}/lib/libc/include/x86_64-linux-gnu/gnu/stubs.h", members)
                self.assertFalse(any(m.startswith(f"{bundle_name}/doc/") for m in members))
                self.assertEqual(list(out_dir.glob("*.minisig")), [])

    def test_rejects_wrong_elf_architecture(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            prefix = self.make_fake_flat_prefix(root, target="x86_64-linux")
            with self.assertRaisesRegex(ValueError, "e_machine mismatch"):
                package_zigc_bundle.package_bundle("aarch64-linux", "0.17.1-zigc.1", prefix, root / "dist")

    def test_rejects_dynamically_linked_elf_with_pt_interp(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            prefix = self.make_fake_flat_prefix(root, target="x86_64-linux", with_interp=True)
            with self.assertRaisesRegex(ValueError, "PT_INTERP"):
                package_zigc_bundle.package_bundle("x86_64-linux", "0.17.1-zigc.1", prefix, root / "dist")

    def test_rejects_unexpected_doc_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            prefix = self.make_fake_flat_prefix(root, target="x86_64-linux")
            (prefix / "doc").mkdir()
            (prefix / "doc" / "langref.html").write_text("<html/>\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Unexpected doc/ directory"):
                package_zigc_bundle.package_bundle("x86_64-linux", "0.17.1-zigc.1", prefix, root / "dist")

    def test_rejects_leading_v_in_version(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            prefix = self.make_fake_flat_prefix(root, target="x86_64-linux")
            with self.assertRaisesRegex(ValueError, "must not start with 'v'"):
                package_zigc_bundle.package_bundle("x86_64-linux", "v0.17.1-zigc.1", prefix, root / "dist")

    def test_rejects_excluded_testdata_extension_in_lib(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            prefix = self.make_fake_flat_prefix(root, target="x86_64-linux")
            (prefix / "lib" / "std" / "bad.tzif").write_bytes(b"tzif")
            with self.assertRaisesRegex(ValueError, "Forbidden file extension"):
                package_zigc_bundle.package_bundle("x86_64-linux", "0.17.1-zigc.1", prefix, root / "dist")

    def test_rejects_stale_minisig_in_out_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            prefix = self.make_fake_flat_prefix(root, target="x86_64-linux")
            out_dir = root / "dist"
            out_dir.mkdir(parents=True)
            (out_dir / "zigc-x86_64-linux-0.17.1-zigc.1.tar.zst.minisig").write_text("sig\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "minisig"):
                package_zigc_bundle.package_bundle("x86_64-linux", "0.17.1-zigc.1", prefix, out_dir)


if __name__ == "__main__":
    unittest.main()
