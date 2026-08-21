# Execution backends (plan §7). Stubbed for now — no backend actually executes anything
# yet (Local via Distributed, SLURM, AWS all still to come). Nothing above `run` may know
# which of these is in use (I1); `run` itself doesn't exist yet.
abstract type ExecutionBackend end

struct Local <: ExecutionBackend end
