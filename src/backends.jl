# Execution backends (plan §7). Stubbed in Phase 0 — real Local execution (Distributed)
# lands in Phase 1, SLURM in Phase 3, AWS later. Nothing above `run` may know which of
# these is in use (I1); `run` itself doesn't exist yet.
abstract type ExecutionBackend end

struct Local <: ExecutionBackend end
