# WSL launcher correction

Environment split:

- Run this shell script from WSL.
- The script invokes the Windows Vivado batch file at:
  `/mnt/f/Xilinx/Vivado/2024.1/bin/vivado.bat`
- The Tcl file remains in the repository and derives its own root with
  `[info script]`.

Install from WSL:

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o ./ntt4096_pipeline_wsl_vivado_launcher_fix.zip
./implement_ntt4096_four_butterfly_pipeline.sh
```
