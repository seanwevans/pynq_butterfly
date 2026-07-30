# OpenFHE workflow

Generate evaluation-domain BGV test material with the maintained utilities under
`openfhe/`, install that vector directory with the [board deployment guide](board-deployment.md),
and compare every returned residue against OpenFHE output. The hardware boundary
expects reduced 32-bit residues, paired Q towers, Barrett reciprocals, and
host-supplied BV CRT digits.

Read [`../architecture/relinearization-boundary.md`](../architecture/relinearization-boundary.md)
before changing packing or decomposition. Probe failures and format migrations
are historical records under [`../history/`](../history/), not current formats.
