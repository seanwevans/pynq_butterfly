# Two-tower OpenFHE runtime bridge

This checkpoint constructs a real two-tower OpenFHE `DCRTPoly`, derives
the second RNS prime and root through OpenFHE, generates a runtime FPGA
profile for each tower, and exports one DMA polynomial product per tower.

The existing runtime-profile PYNQ-Z2 overlay executes tower 0 and tower 1
sequentially without rebuilding the bitstream. The verifier imports both
FPGA results into a two-tower `DCRTPoly` and requires exact object equality
with OpenFHE's software product.
