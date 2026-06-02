# Tools Directory

This directory contains development and testing scripts for the zig-gui project.

## Scripts

### `run-tests.ps1` (Windows PowerShell)
Test runner for Module 01 spike tests.

**Usage:**
```powershell
.\run-tests.ps1 -TestType smoke   # Run smoke tests only
.\run-tests.ps1 -TestType unit    # Run unit tests only
.\run-tests.ps1 -TestType all     # Run all tests
.\run-tests.ps1 -TestType build   # Build only
```

### `analyze-spike-v2.py` (Python)
Improved spike window capture and frame-by-frame analysis.

**Features:**
- Detects and captures "smoke" window specifically
- Extracts individual frames to PNG images
- Analyzes pixel colors and geometry per frame
- Generates detailed frame analysis report

**Usage:**
```bash
python.exe analyze-spike-v2.py
```

**Output:**
- `spike-window.mp4` — captured video (in test-results/)
- `spike-frames/` — individual frame PNGs (in test-results/)
- `spike-frame-analysis.txt` — per-frame statistics (in test-results/)

### `analyze-spike.py` (Python)
Original whole-screen spike capture and analysis script.

**Usage:**
```bash
python.exe analyze-spike.py
```
