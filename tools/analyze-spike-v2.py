#!/usr/bin/env python3
"""
Capture and analyze the Module 01 spike test window specifically.

This script:
1. Launches the spike test (zig build test-01)
2. Detects the "smoke" window
3. Captures video of ONLY that window
4. Extracts frames as images
5. Analyzes frame content for triangle, colors, rendering
"""

import subprocess
import time
import threading
import cv2
import numpy as np
from pathlib import Path
import pygetwindow as gw
from PIL import ImageGrab
import os


# Configuration
OUTPUT_DIR = Path("../test-results/spike-frames")
VIDEO_OUTPUT = Path("../test-results/spike-window.mp4")
ANALYSIS_OUTPUT = Path("../test-results/spike-frame-analysis.txt")


def find_spike_window(timeout: float = 5.0):
    """Wait for the spike window to appear and return its handle."""
    print(f"[Window] Waiting for 'smoke' window to appear (timeout: {timeout}s)...")
    
    start = time.time()
    while time.time() - start < timeout:
        try:
            windows = gw.getWindowsWithTitle("smoke")
            if windows:
                print(f"[Window] Found: {windows[0].title}")
                return windows[0]
        except Exception as e:
            print(f"[Window] Error: {e}")
        
        time.sleep(0.05)
    
    print("[Window] Window not found (may have closed quickly)")
    return None


def capture_window_video(window, duration: float, output_path: Path) -> int:
    """Capture a specific window to video."""
    print(f"[Capture] Recording window to {output_path}...")
    
    # Create video writer
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = None
    frame_count = 0
    start_time = time.time()
    
    try:
        while time.time() - start_time < duration:
            try:
                # Get window bounds
                if not window.isActive:
                    print("[Capture] Window closed")
                    break
                
                x, y, w, h = window.left, window.top, window.width, window.height
                
                if w <= 0 or h <= 0:
                    time.sleep(0.01)
                    continue
                
                # Capture window
                screenshot = ImageGrab.grab(bbox=(x, y, x + w, y + h))
                frame_np = cv2.cvtColor(np.array(screenshot), cv2.COLOR_RGB2BGR)
                
                # Initialize writer with actual dimensions
                if out is None:
                    h_actual, w_actual = frame_np.shape[:2]
                    out = cv2.VideoWriter(
                        str(output_path),
                        fourcc,
                        60,  # 60 FPS
                        (w_actual, h_actual)
                    )
                    print(f"[Capture] Window size: {w_actual}x{h_actual}")
                
                out.write(frame_np)
                frame_count += 1
                
                time.sleep(1.0 / 60.0)  # 60 FPS
            
            except Exception as e:
                print(f"[Capture] Frame error: {e}")
                time.sleep(0.01)
    
    finally:
        if out:
            out.release()
    
    print(f"[Capture] Saved {frame_count} frames")
    return frame_count


def extract_frames(video_path: Path, output_dir: Path):
    """Extract all frames from video as PNG images."""
    output_dir.mkdir(exist_ok=True)
    
    print(f"[Extract] Reading {video_path}...")
    cap = cv2.VideoCapture(str(video_path))
    
    if not cap.isOpened():
        print(f"ERROR: Could not open {video_path}")
        return []
    
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    print(f"[Extract] Total frames: {frame_count}")
    
    frame_paths = []
    for i in range(frame_count):
        ret, frame = cap.read()
        if not ret:
            break
        
        path = output_dir / f"frame_{i:04d}.png"
        cv2.imwrite(str(path), frame)
        frame_paths.append(path)
        
        if (i + 1) % 10 == 0 or i < 3:
            print(f"[Extract] Saved frame {i}")
    
    cap.release()
    print(f"[Extract] Done: {len(frame_paths)} frames extracted to {output_dir}/")
    return frame_paths


def analyze_frame(frame_path: Path) -> dict:
    """Analyze a single frame for content."""
    img = cv2.imread(str(frame_path))
    if img is None:
        return {"error": "Could not read frame"}
    
    h, w = img.shape[:2]
    
    # Convert to HSV for color analysis
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    
    # Detect clear color background (dark blue-gray area)
    # Expected clear color: dark blue-gray RGB ~ (25, 31, 41)
    # In BGR: (41, 31, 25)
    lower_clear = np.array([20, 25, 35])
    upper_clear = np.array([45, 40, 50])
    clear_mask = cv2.inRange(img, lower_clear, upper_clear)
    clear_pixels = cv2.countNonZero(clear_mask)
    
    # Detect non-background (colored pixels)
    non_bg_mask = 255 - clear_mask
    non_bg_pixels = cv2.countNonZero(non_bg_mask)
    
    # Detect bright colors (triangle colors: red, green, blue)
    # Red region in HSV
    lower_red1 = np.array([0, 100, 100])
    upper_red1 = np.array([10, 255, 255])
    lower_red2 = np.array([170, 100, 100])
    upper_red2 = np.array([180, 255, 255])
    red_mask = cv2.inRange(hsv, lower_red1, upper_red1) | cv2.inRange(hsv, lower_red2, upper_red2)
    
    # Green region
    lower_green = np.array([35, 100, 100])
    upper_green = np.array([85, 255, 255])
    green_mask = cv2.inRange(hsv, lower_green, upper_green)
    
    # Blue region
    lower_blue = np.array([100, 100, 100])
    upper_blue = np.array([130, 255, 255])
    blue_mask = cv2.inRange(hsv, lower_blue, upper_blue)
    
    red_px = cv2.countNonZero(red_mask)
    green_px = cv2.countNonZero(green_mask)
    blue_px = cv2.countNonZero(blue_mask)
    
    # Detect edges (for triangle outline)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 50, 150)
    edge_pixels = cv2.countNonZero(edges)
    
    # Detect contours (shapes)
    contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    triangle_candidates = [c for c in contours if len(cv2.approxPolyDP(c, 0.01 * cv2.arcLength(c, True), True)) == 3]
    
    has_triangle = len(triangle_candidates) > 0
    
    return {
        "total_pixels": h * w,
        "clear_bg_pixels": clear_pixels,
        "non_bg_pixels": non_bg_pixels,
        "red_pixels": red_px,
        "green_pixels": green_px,
        "blue_pixels": blue_px,
        "edge_pixels": edge_pixels,
        "has_triangle": has_triangle,
        "triangle_count": len(triangle_candidates),
        "has_colors": (red_px + green_px + blue_px) > 100,
    }


def main():
    """Main: launch test, capture window, extract frames, analyze."""
    print("\n" + "="*80)
    print("ZIG-GUI MODULE 01 SPIKE — WINDOW CAPTURE & ANALYSIS")
    print("="*80 + "\n")
    
    # Clean up old files
    if OUTPUT_DIR.exists():
        import shutil
        shutil.rmtree(OUTPUT_DIR)
    if VIDEO_OUTPUT.exists():
        VIDEO_OUTPUT.unlink()
    
    print("[Setup] Launching test in background...")
    
    # Launch test
    process = subprocess.Popen(
        ["zig", "build", "test-01"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd="."
    )
    
    # Wait for window
    window = find_spike_window(timeout=5.0)
    
    if window:
        # Capture window video
        capture_window_video(window, duration=1.0, output_path=VIDEO_OUTPUT)
    else:
        print("[Warning] Window not found, trying to capture from video anyway")
    
    # Wait for test to complete
    stdout, stderr = process.communicate()
    print(f"[Test] Exit code: {process.returncode}\n")
    
    # Extract frames
    if VIDEO_OUTPUT.exists():
        frame_paths = extract_frames(VIDEO_OUTPUT, OUTPUT_DIR)
        
        # Analyze frames
        print(f"\n[Analysis] Analyzing {len(frame_paths)} frames...\n")
        print("="*80)
        print("FRAME ANALYSIS")
        print("="*80)
        
        results = []
        for i, path in enumerate(frame_paths):
            result = analyze_frame(path)
            results.append(result)
            
            if "error" not in result:
                has_color = result["has_colors"]
                has_tri = result["has_triangle"]
                color_str = "✓ COLORS" if has_color else "  —"
                tri_str = "✓ TRIANGLE" if has_tri else "  —"
                
                print(f"Frame {i:3d} | BG: {result['clear_bg_pixels']:7d} | "
                      f"Non-BG: {result['non_bg_pixels']:6d} | "
                      f"R:{result['red_pixels']:4d} G:{result['green_pixels']:4d} B:{result['blue_pixels']:4d} | "
                      f"{color_str} | {tri_str}")
        
        print("\n" + "="*80)
        print("SUMMARY")
        print("="*80)
        
        frames_with_color = sum(1 for r in results if r.get("has_colors", False))
        frames_with_tri = sum(1 for r in results if r.get("has_triangle", False))
        
        print(f"✓ Total frames:           {len(frame_paths)}")
        print(f"✓ Frames with colors:     {frames_with_color}")
        print(f"✓ Frames with triangle:   {frames_with_tri}")
        
        if frames_with_color > 0:
            print(f"\n🎉 SPIKE TEST SUCCESSFUL!")
            print(f"   Detected rendered output with colors.")
            if frames_with_tri > 0:
                print(f"   Triangle geometry detected in {frames_with_tri} frame(s).")
        else:
            print(f"\n❌ No colored rendering detected")
        
        print("="*80)
        
        # Save analysis
        with open(ANALYSIS_OUTPUT, "w") as f:
            f.write("Module 01 Spike Window Analysis\n")
            f.write("=" * 80 + "\n\n")
            f.write(f"Total frames: {len(frame_paths)}\n")
            f.write(f"Frames with colors: {frames_with_color}\n")
            f.write(f"Frames with triangle: {frames_with_tri}\n\n")
            f.write("Frame details:\n")
            for i, result in enumerate(results):
                f.write(f"Frame {i}: {result}\n")
        
        print(f"\n[Output] Frames saved to {OUTPUT_DIR}/")
        print(f"[Output] Analysis saved to {ANALYSIS_OUTPUT}")
        print(f"[Output] Video saved to {VIDEO_OUTPUT}")
    else:
        print("ERROR: Video file not created")


if __name__ == "__main__":
    main()
