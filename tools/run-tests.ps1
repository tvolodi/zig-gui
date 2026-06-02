#Requires -Version 5.1
<#
.SYNOPSIS
    Run zig-gui module 01 tests.

.DESCRIPTION
    This script runs the acceptance (smoke) tests and/or unit tests for module 01
    (Platform spike). The smoke tests require a GPU and display to run the Vulkan
    application. Unit tests mostly run without a GPU.

.PARAMETER TestType
    Which tests to run:
    - 'smoke'     : Run acceptance tests only (zig build test-01)
    - 'unit'      : Run unit tests only (zig build test-01-unit)
    - 'all'       : Run both smoke and unit tests (default)
    - 'build'     : Compile only, do not run tests

.PARAMETER Verbose
    Print detailed build output.

.EXAMPLE
    .\run-tests.ps1
    Runs both smoke and unit tests.

.EXAMPLE
    .\run-tests.ps1 -TestType smoke
    Runs smoke tests (visual verification of the Vulkan window).

.EXAMPLE
    .\run-tests.ps1 -TestType unit -Verbose
    Runs unit tests with detailed output.
#>

param(
    [ValidateSet('smoke', 'unit', 'all', 'build')]
    [string]$TestType = 'all',
    
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
$WarningPreference = if ($Verbose) { 'Continue' } else { 'SilentlyContinue' }

# Navigate to workspace root (parent of tools directory)
$workspaceRoot = Split-Path -Parent $PSScriptRoot
Push-Location $workspaceRoot

# Verify we're in the zig-gui workspace
if (-not (Test-Path 'build.zig')) {
    Write-Error "build.zig not found. Run this script from the zig-gui workspace root or from tools/ directory."
    Pop-Location
    exit 1
}

# Verify Zig is available
if (-not (Get-Command zig -ErrorAction SilentlyContinue)) {
    Write-Error "zig compiler not found in PATH. Install Zig or add it to PATH."
    Pop-Location
    exit 1
}

Write-Host "`n[zig-gui] Module 01 Test Runner`n" -ForegroundColor Cyan

# Build the project first
Write-Host "Building project..." -ForegroundColor Yellow
zig build
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    Pop-Location
    exit 1
}

Write-Host "Build successful.`n" -ForegroundColor Green

# Run requested tests
$testCount = 0
$passCount = 0
$failCount = 0

if ($TestType -eq 'build') {
    Write-Host "Build completed. Skipping tests as requested." -ForegroundColor Green
    Pop-Location
    exit 0
}

if ($TestType -in 'smoke', 'all') {
    Write-Host "─────────────────────────────────────────────────────────" -ForegroundColor Gray
    Write-Host "SMOKE TESTS (acceptance tests — requires GPU)" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────────────────────────────`n" -ForegroundColor Gray
    
    Write-Host "Running: zig build test-01" -ForegroundColor Yellow
    zig build test-01
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✓ Smoke tests PASSED" -ForegroundColor Green
        $passCount++
    } else {
        Write-Host "`n✗ Smoke tests FAILED (exit code $LASTEXITCODE)" -ForegroundColor Red
        $failCount++
    }
    $testCount++
}

if ($TestType -in 'unit', 'all') {
    Write-Host "`n─────────────────────────────────────────────────────────" -ForegroundColor Gray
    Write-Host "UNIT TESTS (compile-time & GPU-optional)" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────────────────────────────`n" -ForegroundColor Gray
    
    Write-Host "Running: zig build test-01-unit" -ForegroundColor Yellow
    zig build test-01-unit
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✓ Unit tests PASSED" -ForegroundColor Green
        $passCount++
    } else {
        Write-Host "`n✗ Unit tests FAILED (exit code $LASTEXITCODE)" -ForegroundColor Red
        $failCount++
    }
    $testCount++
}

# Summary
Write-Host "`n─────────────────────────────────────────────────────────" -ForegroundColor Gray
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "─────────────────────────────────────────────────────────" -ForegroundColor Gray
Write-Host "Tests run: $testCount | Passed: $passCount | Failed: $failCount`n" -ForegroundColor Yellow

if ($failCount -eq 0) {
    Write-Host "All tests passed! ✓" -ForegroundColor Green
    
    if ($TestType -in 'smoke', 'all') {
        Write-Host "`nNOTE: Smoke tests verify the Vulkan window opened and rendered correctly." -ForegroundColor Cyan
        Write-Host "      For full manual verification, ensure you saw:" -ForegroundColor Cyan
        Write-Host "        • A window with the clear color (dark blue-gray)" -ForegroundColor Cyan
        Write-Host "        • A colored triangle in the center" -ForegroundColor Cyan
        Write-Host "        • Window resize without crashes" -ForegroundColor Cyan
        Write-Host "        • Clean exit on window close`n" -ForegroundColor Cyan
    }
    
    Pop-Location
    exit 0
} else {
    Write-Host "Some tests failed. Check the output above for details." -ForegroundColor Red
    Pop-Location
    exit 1
}
