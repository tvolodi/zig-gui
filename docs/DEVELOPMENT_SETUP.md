# Development Setup Guide — zig-gui

## System Requirements

This guide assumes Windows development environment for zig-gui.

### Verified Installation (as of 2026-06-02)

| Tool | Version | Location | Status |
|---|---|---|---|
| **Zig** | 0.16.0 | `PATH` | ✅ Installed |
| **Git** | 2.50.1 | `PATH` | ✅ Installed |
| **Vulkan SDK** | 1.4.350.0 | `F:\VulkanSDK\` | ✅ Installed |

### Environment Variables

Verify these are set:

```powershell
$env:VULKAN_SDK        # Should be: F:\VulkanSDK\1.4.350.0
$env:VULKAN_SDK_PATH   # May be same as above
```

If `VULKAN_SDK` is not set, add it manually:

```powershell
# Persistent (Admin terminal required)
[Environment]::SetEnvironmentVariable('VULKAN_SDK', 'F:\VulkanSDK\1.4.350.0', 'User')

# Temporary (current session only)
$env:VULKAN_SDK = 'F:\VulkanSDK\1.4.350.0'
```

## First-Time Setup

1. **Verify Zig installation:**
   ```powershell
   zig version
   ```
   Should output: `0.16.0` (or later)

2. **Verify Vulkan SDK:**
   ```powershell
   Test-Path "F:\VulkanSDK\Lib"
   Test-Path "F:\VulkanSDK\Include"
   ```
   Both should return `True`

3. **Verify Git:**
   ```powershell
   git --version
   ```

4. **Clone/pull the repository:**
   ```powershell
   cd c:\Users\tvolo\dev\ai-dala\zig-gui
   git status
   ```

## Build Instructions

Once `build.zig` is created by the implementer agent:

```powershell
# Build the project
zig build

# Run tests
zig test docs/specs/02.acceptance_test.zig
zig test docs/specs/03.acceptance_test.zig
# ... etc for each module

# Build with release optimization
zig build -Doptimize=ReleaseFast
```

## Troubleshooting

### "Vulkan SDK not found"

If compilation fails with Vulkan errors:

1. Verify `VULKAN_SDK` environment variable:
   ```powershell
   echo $env:VULKAN_SDK
   ```

2. Check directory exists:
   ```powershell
   Get-ChildItem "F:\VulkanSDK\Lib" | Where-Object { $_.Name -like "*.lib" } | Select-Object -First 5
   ```

3. Restart VS Code or terminal after setting environment variables.

### "Zig not found"

Zig must be in `PATH`:

```powershell
where zig
```

If not found, install from [zigdownloads](https://ziglang.org/download/) and add to PATH.

## Development Workflow

See `docs/AGENT_GUIDE.md` for the full development workflow and `docs/agents/AGENT_WORKFLOWS.md` for agent coordination patterns.

### Key files for agents

- **Module specs:** `docs/specs/NN.spec.md`
- **Module types:** `docs/specs/NN.types.zig`
- **Acceptance tests:** `docs/specs/NN.acceptance_test.zig`
- **Build config:** `build.zig` (created when module 01 implementation begins)
- **Agent guides:** `docs/AGENT_GUIDE.md` and `docs/agents/AGENT_WORKFLOWS.md`

## IDE Setup (VS Code)

Recommended extensions:

```powershell
# Install recommended extensions
code --install-extension ziglang.vscode-zig
code --install-extension GitHub.copilot
```

VS Code should auto-detect the Zig toolchain. Verify in the status bar at the bottom.
