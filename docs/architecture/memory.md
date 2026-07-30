# Memory architecture

Two coefficient banks decouple ingestion from result draining. Evaluation-key
data is reused in coefficient-major order, reducing the batch-64 external input
from 2,560 to 1,048 words per coefficient and pair. The six-pair wrapper stores
the modulus and Barrett-reciprocal profile table once per session.

On the host, all pair frames may reside in one CMA arena and one persistent
output allocation. The supported allocation and installation path is described
in [`../guides/board-deployment.md`](../guides/board-deployment.md); superseded
buffer and handoff investigations are catalogued under
[`../history/`](../history/).
