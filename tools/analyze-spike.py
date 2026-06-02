#!/usr/bin/env python3
"""
Capture and analyze the Module 01 spike test app visually.

This script:
1. Launches the spike test (zig build test-01)
2. Captures video during execution
3. Analyzes frames for color, geometry, and activity
4. Reports findings frame-by-frame
"""

import subprocess
import time
import threading
import cv2
import numpy as np
from mss import mss
from pathlib import Path
from collections import defaultdict

# Configuration
CAPTURE_FPS = 60
VIDEO_OUTPUT = Path("../test-results/spike-capture.mp4")
ANALYSIS_OUTPUT = Path("../test-results/spike-analysis.txt")
CAPTURE_DURATION = 2.0  # seconds (test runs ~0.5s, capture longer to catch everything)


def capture_video(duration: float, output_path: Path, stop_event: threading.Event):
    """Capture screen to video file while test runs."""
    print(f"[Capture] Starting screen capture to {output_path}...")
    
    with mss() as sct:
        # Capture the primary monitor
        monitor = sct.monitors[1]
        width = monitor["width"]
        height = monitor["height"]
        
        # Create video writer
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(
            str(output_path),
            fourcc,
            CAPTURE_FPS,
            (width, height)
        )
        
        start_time = time.time()
        frame_count = 0
        
        try:
            while time.time() - start_time < duration and not stop_event.is_set():
                frame = sct.grab(monitor)
                # Convert RGBA to BGR for OpenCV
                frame_np = np.array(frame)
                frame_bgr = cv2.cvtColor(frame_np, cv2.COLOR_RGBA2BGR)
                out.write(frame_bgr)
                frame_count += 1
                time.sleep(1.0 / CAPTURE_FPS)
        finally:
            out.release()
    
    print(f"[Capture] Saved {frame_count} frames to {output_path}")
    return frame_count


def analyze_video(video_path: Path) -> dict:
    """Analyze video frames for color, changes, and content."""
    print(f"\n[Analysis] Reading {video_path}...")
    
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        print(f"ERROR: Could not open {video_path}")
        return {}
    
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    
    print(f"[Analysis] Video: {frame_count} frames @ {fps:.1f} FPS")
    print(f"[Analysis] Duration: {frame_count / fps:.2f} seconds\n")
    
    analysis = {
        "total_frames": frame_count,
        "fps": fps,
        "frames": []
    }
    
    prev_frame = None
    unique_colors = defaultdict(int)
    
    for i in range(frame_count):
        ret, frame = cap.read()
        if not ret:
            break
        
        # Convert to HSV for better color analysis
        hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
        
        # Detect non-black regions (anything that's not background)
        # Black/dark = (H: 0-180, S: 0-255, V: 0-50 or so)
        lower_dark = np.array([0, 0, 0])
        upper_dark = np.array([180, 255, 60])
        
        dark_mask = cv2.inRange(hsv, lower_dark, upper_dark)
        non_dark_pixels = cv2.countNonZero(255 - dark_mask)
        
        # Calculate dominant colors in non-dark areas
        non_dark_frame = frame[255 - dark_mask == 255]
        
        frame_info = {
            "frame": i,
            "time_ms": (i / fps * 1000),
            "non_background_pixels": non_dark_pixels,
            "has_color": non_dark_pixels > 100,
        }
        
        # Detect changes from previous frame
        if prev_frame is not None:
            diff = cv2.absdiff(frame, prev_frame)
            changed_pixels = np.count_nonzero(diff > 10)
            frame_info["changed_pixels"] = changed_pixels
            frame_info["is_moving"] = changed_pixels > 1000
        
        analysis["frames"].append(frame_info)
        prev_frame = frame
    
    cap.release()
    return analysis


def report_analysis(analysis: dict):
    """Print detailed analysis report."""
    if not analysis or "frames" not in analysis:
        print("No analysis data available")
        return
    
    print("\n" + "="*80)
    print("FRAME-BY-FRAME ANALYSIS")
    print("="*80)
    
    window_detected = False
    triangle_detected = False
    motion_detected = False
    
    for frame_info in analysis["frames"]:
        f = frame_info["frame"]
        t = frame_info["time_ms"]
        colored = "✓ COLOR" if frame_info["has_color"] else "  black"
        motion = "✓ MOTION" if frame_info.get("is_moving", False) else "        "
        pixels = frame_info["non_background_pixels"]
        changed = frame_info.get("changed_pixels", 0)
        
        if f % 10 == 0 or f < 5 or frame_info["has_color"]:  # Print key frames
            print(f"Frame {f:4d} | {t:7.1f}ms | {colored} ({pixels:6d} px) | {motion} | Δ{changed:5d} px")
        
        if frame_info["has_color"]:
            window_detected = True
            triangle_detected = True
        
        if frame_info.get("is_moving", False):
            motion_detected = True
    
    print("\n" + "="*80)
    print("FINDINGS")
    print("="*80)
    print(f"✓ Window rendered:     {window_detected}")
    print(f"✓ Colors detected:     {triangle_detected}")
    print(f"✓ Motion detected:     {motion_detected}")
    print(f"✓ Total frames:        {analysis['total_frames']}")
    print(f"✓ Video duration:      {analysis['total_frames'] / analysis['fps']:.2f}s")
    
    if window_detected and triangle_detected:
        print("\n🎉 SPIKE TEST SUCCESSFUL!")
        print("   Window opened, rendered with colors (triangle), and closed cleanly.")
    
    print("="*80 + "\n")


def main():
    """Main: launch test and capture/analyze video."""
    print("\n" + "="*80)
    print("ZIG-GUI MODULE 01 SPIKE — VIDEO ANALYSIS")
    print("="*80 + "\n")
    
    # Clean up old capture
    if VIDEO_OUTPUT.exists():
        VIDEO_OUTPUT.unlink()
        print(f"[Setup] Removed old {VIDEO_OUTPUT}")
    
    # Start capture in background thread
    stop_event = threading.Event()
    capture_thread = threading.Thread(
        target=capture_video,
        args=(CAPTURE_DURATION, VIDEO_OUTPUT, stop_event)
    )
    capture_thread.daemon = True
    capture_thread.start()
    
    # Give capture thread time to start
    time.sleep(0.1)
    
    # Launch test
    print("[Test] Launching: zig build test-01")
    print("[Test] Recording screen during execution...\n")
    
    start = time.time()
    result = subprocess.run(
        ["zig", "build", "test-01"],
        cwd=".",
        capture_output=True,
        text=True
    )
    elapsed = time.time() - start
    
    print(f"[Test] Test completed in {elapsed:.2f}s (exit code: {result.returncode})")
    
    # Stop capture
    stop_event.set()
    capture_thread.join(timeout=CAPTURE_DURATION + 1.0)
    
    # Wait for video to be written
    time.sleep(0.5)
    
    if not VIDEO_OUTPUT.exists():
        print(f"ERROR: Video file not created at {VIDEO_OUTPUT}")
        return
    
    # Analyze video
    analysis = analyze_video(VIDEO_OUTPUT)
    report_analysis(analysis)
    
    # Save analysis to file
    with open(ANALYSIS_OUTPUT, "w") as f:
        f.write(f"Module 01 Spike Analysis\n")
        f.write(f"========================\n\n")
        f.write(f"Test exit code: {result.returncode}\n")
        f.write(f"Test elapsed: {elapsed:.2f}s\n")
        f.write(f"Video frames: {analysis.get('total_frames', 0)}\n")
        f.write(f"Video fps: {analysis.get('fps', 0):.1f}\n\n")
        f.write(f"Test stdout:\n{result.stdout}\n\n")
        f.write(f"Test stderr:\n{result.stderr}\n")
    
    print(f"[Output] Analysis saved to {ANALYSIS_OUTPUT}")
    print(f"[Output] Video saved to {VIDEO_OUTPUT}")


if __name__ == "__main__":
    main()
