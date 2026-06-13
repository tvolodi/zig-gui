# RI5 — M19-05: App installer / packaging

> Roadmap item: M19-05  
> Depends on: M19-03 (Staged update — version manifest)  
> Read `00_constitution.md` before this file.

## Purpose

Create a distributable package bundle that contains the compiled application binary, font
assets, and the version manifest (for update checking). The output is a `.zip` on Windows
and `.tar.gz` on Linux, suitable for distribution to end users or deployment to a web server.

Unlike RI1–RI4 (which handle automatic updates), RI5 is a **build-time** step that runs
when packaging a release:

```bash
zig build package -- --version 1.0.1 --output dist/
```

Output:
- Windows: `dist/app-1.0.1.zip` (binary, manifest, fonts)
- Linux: `dist/app-1.0.1.tar.gz` (same)

After this item ships, the release process is:
1. Build the binary: `zig build -Drelease-fast`.
2. Package it: `zig build package -- --version 1.0.1 --output dist/`.
3. Upload `app-1.0.1.zip` to a server (e.g., GitHub Releases, S3, a CDN).
4. Optionally run `zig build generate-manifest -- --version 1.0.1 --binary dist/app-1.0.1.zip`
   to create the update manifest (RI1 will fetch it).

---

## What to build

### 1. Manifest generation

Create a helper tool `src/tools/generate_manifest.zig` that:
- Takes a binary file path and version string as arguments.
- Computes the SHA256 hash of the binary.
- Outputs a JSON manifest:

```json
{
  "version": "1.0.1",
  "download_url": "https://example.com/app-1.0.1.zip",
  "checksum_sha256": "abcd1234...",
  "release_notes": "Bug fixes and performance improvements"
}
```

Usage:
```bash
zig build run-generate-manifest -- path/to/app-1.0.1.zip https://example.com/app-1.0.1.zip
```

Output: writes `manifest.json` to stdout (or to a file with `--output manifest.json`).

### 2. Package build step — `build.zig`

Add a new build step:

```zig
const package_step = b.addSystemCommand(&.{
    "zig", "build", "run-package",
});
```

And a `run-package` target that invokes `src/tools/package.zig`:

```bash
zig build run-package -- --version 1.0.1 --output dist/ --binary-path zig-cache/bin/app
```

### 3. `package.zig` tool

`src/tools/package.zig` is a standalone Zig program that:

**Input arguments:**
- `--version VERSION` (e.g., `1.0.1`)
- `--output OUTPUT_DIR` (e.g., `dist/`)
- `--binary-path BINARY` (path to the compiled binary)
- Optional: `--fonts-dir FONTS_DIR` (default: `assets/fonts/`)
- Optional: `--include-manifest` (also create a `manifest.json` in the package)

**Process:**
1. Read the binary file.
2. Read font files from `fonts_dir/`.
3. Create a temporary staging directory.
4. Copy the binary and fonts into the staging directory.
5. If `--include-manifest`, compute SHA256 and create a manifest JSON.
6. If on Windows: create a `.zip` file in `OUTPUT_DIR/app-{VERSION}.zip`.
7. If on Linux: create a `.tar.gz` file in `OUTPUT_DIR/app-{VERSION}.tar.gz`.
8. Log: `"Packaged: app-{VERSION}.zip (sizes: binary=10 MB, fonts=2 MB, total=12 MB)"`.

### 4. Package contents

Inside `app-1.0.1.zip` (or `.tar.gz`):

```
app-1.0.1.zip
  ├── app                (or app.exe on Windows)
  ├── manifest.json      (optional; RI1 uses this to check for updates)
  └── fonts/
      ├── regular.ttf
      ├── bold.ttf
      ├── italic.ttf
      └── ...
```

The structure is **flat** (no extra directories). When extracted:
```
/some/path/
  ├── app
  ├── manifest.json
  └── fonts/
```

Users extract to a location like `C:\Program Files\MyApp\` (Windows) or `/opt/myapp/`
(Linux), and the binary runs from there.

### 5. Manifest file generation

If `--include-manifest` is passed:
1. Compute SHA256 of the **original binary** (not the zip).
2. Generate a manifest JSON:
```json
{
  "version": "1.0.1",
  "download_url": "https://example.com/app-1.0.1.zip",
  "checksum_sha256": "deadbeef...",
  "release_notes": ""
}
```
3. Write it to `staging_dir/manifest.json`.
4. Include it in the zip/tar.gz.

When RI1 fetches a manifest from a URL, it expects the **same format**. The
`download_url` field should point to where the `.zip` or `.tar.gz` is hosted. RI1 will
download the entire zip and extract it, then restart the app.

### 6. File compression

**Zip creation (Windows):**
- Use `std.compress.zlib` or a minimal zip writer from the Zig std (if available).
- If std does NOT have zip support, implement a simple uncompressed zip writer (Store
  method, no deflate compression).
- Reason: Keep the binary footprint low; avoid external compression libraries.

**Tar.gz creation (Linux):**
- Create an uncompressed tar file first (using `std` tar support, if available).
- Pipe through gzip compression (system `gzip` command or vendored pure-Zig implementation).

**Alternative (recommended):** Use uncompressed zip/tar.
- Rationale: Binaries and fonts are already compressed (TTF). Adding another compression
  layer saves < 5%. Simpler to implement in pure Zig.

### 7. Build.zig integration

In `build.zig`:

```zig
const package_cmd = b.addSystemCommand(&.{
    "zig", "build", "run-package",
});
package_cmd.addArg("--version");
package_cmd.addArg(version); // from cmd-line or hardcoded
package_cmd.addArg("--output");
package_cmd.addArg("dist");
package_cmd.addArg("--binary-path");
package_cmd.addArg(app_exe.getEmittedBin().?.getPath(b));

const package_step = b.step("package", "Package the app for distribution");
package_step.dependOn(&package_cmd.step);
```

Usage:
```bash
zig build package
```

Or with version override:
```bash
VERSION=1.0.1 zig build package
```

---

## Acceptance criteria

1. `package.zig` is a standalone tool that accepts `--version`, `--output`, and `--binary-path`.
2. `package.zig` reads the binary and font files without errors.
3. On Windows: creates a `.zip` file with the binary and fonts.
4. On Linux: creates a `.tar.gz` file with the binary and fonts.
5. Package contents include the binary with its original file permissions (executable bit preserved).
6. Fonts are included in `fonts/` subdirectory inside the package.
7. Optional manifest JSON is generated with correct SHA256 and version.
8. `zig build package` succeeds and outputs a distributable file.
9. Extracted package can be run: `./app` or `app.exe` (after extraction).
10. Manifest JSON (if included) matches the format expected by RI1.
11. Package filename includes the version: `app-{VERSION}.zip` or `app-{VERSION}.tar.gz`.
12. File sizes are logged for diagnostics.
13. No external compression dependencies (pure Zig or system `gzip` only).

---

## Non-goals

- No signed/verified packages (signature verification is post-v1; users trust HTTPS download).
- No installer GUI (`.exe`/`.msi` for Windows, `.dmg` for macOS). Users extract the zip manually.
- No auto-install into `Program Files` (users manage installation location).
- No uninstaller script.
- No service integration (e.g., Windows Service, systemd unit).

---

## Non-visual

This is a build-time tool. No runtime rendering.

---

## Dependencies

**Existing dependencies used:**
- Zig std (file I/O, SHA256, tar if available)
- System `gzip` (for `.tar.gz` on Linux; optional if vendored Zig implementation exists)

**New dependencies introduced:**
- **None.** Pure Zig + system tools only.

If zip compression is needed and std does not provide it, implement a minimal Store-method
(uncompressed) zip writer in pure Zig.

---

## Implementation notes

### File I/O

Use `std.fs` for all file operations:
- `std.fs.cwd().openFile(path, .{})` to read binary and fonts.
- `std.fs.cwd().createFile(output_path, .{})` to write the package.

### SHA256 computation

Use `std.crypto.hash.sha2.Sha256.hash()` on the binary file:
```zig
var file = try std.fs.cwd().openFile(binary_path, .{});
defer file.close();
var hasher = std.crypto.hash.sha2.Sha256.init(.{});
// read file in chunks and update hasher
var digest: [32]u8 = undefined;
hasher.final(&digest);
```

### Hex encoding

Convert the 32-byte SHA256 to hex:
```zig
var hex_buf: [64]u8 = undefined;
const hex_str = std.fmt.bytesToHex(digest, .lower);
```

### Zip writing (if needed)

If `std` does not provide a zip writer, implement a minimal one:
- Uncompressed Store method (no deflate).
- Local file headers + central directory.
- Reference: `appnote.txt` (PKWARE ZIP specification).

Alternatively, use the system `zip` command:
```zig
var child = try std.process.child_process.init(alloc, &.{ "zip", "-r", output_path, "." });
```

But this is less portable and requires `zip` to be installed.

### Tar writing

Zig std has `std.tar` in recent versions. If available, use it:
```zig
var tar = try std.tar.file.create(...);
defer tar.deinit();
tar.addFile(path, ...);
```

Then pipe the tar output through `gzip`:
```zig
gzip < app.tar > app.tar.gz
```

Or use a system command.

### Directory structure in package

Inside the zip/tar:
```
./app                (or ./app.exe)
./manifest.json      (optional)
./fonts/
  regular.ttf
  bold.ttf
  ...
```

The leading `./` is optional but recommended for portability.

### Logging

Log the packaging process:
```
std.debug.print("Packaging app version {s}...\n", .{version});
std.debug.print("  Binary: {} bytes\n", .{binary_size});
std.debug.print("  Fonts: {} bytes\n", .{fonts_total_size});
std.debug.print("  Package: {s}\n", .{output_path});
std.debug.print("  SHA256: {s}\n", .{hex_checksum});
```

### Manifest `download_url`

The `download_url` field in the manifest should be set by the packager or via a flag:
```bash
zig build run-package -- --version 1.0.1 --download-url https://example.com/app-1.0.1.zip
```

If not provided, it defaults to a placeholder (user must edit the manifest).

### Release notes

The `release_notes` field in the manifest is optional. For now, leave it empty (`""`).
A future feature (M19+) could read it from a `RELEASE_NOTES.md` file.

---

## Why RI5 does NOT depend on HTTP/bsdiff

Unlike RI1–RI4, which handle **automatic updates**, RI5 is a **packaging and distribution**
tool. It runs once per release, at build time, on the developer's machine. It does not
require:
- HTTP client (download is manual or via a separate tool like `curl`)
- bsdiff (delta generation is a separate step; users download the full package)
- async networking (it's a synchronous CLI tool)

This makes RI5 **independent** of the HTTP/bsdiff decisions. It can ship immediately
without waiting for those dependency approvals.
