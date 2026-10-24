"""
    EnvName

Name of an execution environment resolved before a workflow runs. Only `:native` is
currently supported, and its exact Julia project, manifest, and Julia version enter the
task identity.
"""
const EnvName = Symbol

"""
    Resources(cpus=1, mem=nothing, walltime=nothing, gpus=0, extra=Dict())

Execution resources attached to a task. Resources affect scheduling but never task
identity.
"""
struct Resources
    cpus::Int
    mem::Union{Nothing, Int}
    walltime::Union{Nothing, Period}
    gpus::Int
    extra::Dict{Symbol, Any}
end

Resources() = Resources(1, nothing, nothing, 0, Dict{Symbol, Any}())
