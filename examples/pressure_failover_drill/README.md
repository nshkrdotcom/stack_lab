# Pressure Failover Drill

Transport and duplicate-delivery drill for the assembled lower seam.

Covered cases:

- recovery after transport interruption
- duplicate delivery converging to one durable Spine acceptance

The recovery assertions use a longer CI wait budget than the normal happy-path
runtime because this example runs concurrently with other StackLab examples
during workspace `mix ci`.
