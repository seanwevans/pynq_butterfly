# PYNQ-Z2 dual-butterfly two-tower DMA overlay

This bundle packages the verified two-tower 64-bit AXI4-Stream core,
creates a PYNQ-Z2 AXI DMA overlay, and supplies the physical OpenFHE
regression.

Core facts:

- q0 and q1 run concurrently;
- 24 real radix-4 modular multipliers;
- 48 RAMB36 in the accelerator core;
- 607234 clocks per two-tower product;
- 6072.34 us arithmetic latency at 100 MHz;
- 2.2057x fewer clocks than the previous parallel core.

The stream protocol is unchanged:

- profile input: 16384 x 64-bit words, 131072 bytes;
- product input: 8193 x 64-bit words, 65544 bytes;
- product output: 4096 x 64-bit words, 32768 bytes.

## Build

Run from PowerShell:

    $ErrorActionPreference = "Stop"

    $root = "F:\repos\pynq_butterfly"
    $vivado = "F:\Xilinx\Vivado\2024.1\bin\vivado.bat"

    & $vivado `
        -mode batch `
        -source "$root\package_poly_mul4096_dual_butterfly_two_tower_axis_ip.tcl"

    if ($LASTEXITCODE -ne 0) {
        throw "IP packaging failed with exit code $LASTEXITCODE"
    }

    & $vivado `
        -mode batch `
        -source "$root\integrate_poly_mul4096_dual_butterfly_two_tower_dma.tcl"

    if ($LASTEXITCODE -ne 0) {
        throw "DMA overlay build failed with exit code $LASTEXITCODE"
    }

    Get-Content `
        "$root\deploy\poly_mul4096_dual_butterfly_two_tower_dma\manifest.txt"
