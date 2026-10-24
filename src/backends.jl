"""
    ExecutionBackend

Execution strategy selected only at [`run`](@ref).
"""
abstract type ExecutionBackend end

"""
    Local()

Execute steps sequentially in the current Julia process.
"""
struct Local <: ExecutionBackend end

abstract type PreparedResult end

struct PreparedFile <: PreparedResult
    source::String
    logical_name::String
    hash::Digest
end

struct PreparedNamed{T <: NamedTuple} <: PreparedResult
    values::T
end

struct PreparedAbsent <: PreparedResult end

prepare(path::AbstractPath, scratch::AbstractString) = begin
    source = outputpath(path, scratch)
    PreparedFile(source, basename(path), digest(Path(source)))
end

prepare(values::NamedTuple, scratch::AbstractString) =
    PreparedNamed(map(value -> prepare(value, scratch), values))
prepare(::Nothing, scratch::AbstractString) = PreparedAbsent()

function commitresult(prepared::PreparedFile)
    stored = commit!(prepared.source, prepared.hash)
    return FileArtifact(Path(stored), prepared.logical_name, prepared.hash, NamedTuple())
end

commitresult(prepared::PreparedNamed) =
    NamedArtifact(map(commitresult, prepared.values), NamedTuple())
commitresult(::PreparedAbsent) = AbsentArtifact()

selectartifact(artifact::AbstractArtifact, selector::Tuple{}) = artifact

function selectartifact(artifact::NamedArtifact, selector::Tuple{Symbol, Vararg{Symbol}})
    selected = artifact[first(selector)]
    return selectartifact(selected, Base.tail(selector))
end

function selectartifact(artifact::AbstractArtifact, selector::Tuple{Symbol, Vararg{Symbol}})
    error("cannot select $(first(selector)) from $(typeof(artifact))")
end

resolveinput(instance::StepInstance, produced) = produced[instance]
resolveinput(output::Output, produced) =
    selectartifact(produced[output.instance], output.selector)
resolveinput(file::FileArtifact, produced) = file
resolveinput(branch::NamedArtifact, produced) = branch
resolveinput(absent::AbsentArtifact, produced) = absent
resolveinput(gathered::Gathered, produced) =
    gather(resolveinput(item, produced) for item in gathered.items)

function stagevalue(file::FileArtifact, scratch::AbstractString, components::Tuple)
    directory = joinpath(scratch, ".hapi-inputs", components...)
    mkpath(directory)
    destination = joinpath(directory, file.logical_name)
    cp(string(file.path), destination)
    return Path(destination)
end

function stagevalue(branch::NamedArtifact, scratch::AbstractString, components::Tuple)
    return NamedTuple(
        name => stagevalue(value, scratch, (components..., string(name))) for
            (name, value) in pairs(branch.values)
    )
end

stagevalue(::AbsentArtifact, scratch::AbstractString, components::Tuple) = nothing

function stagevalue(gathered::Gathered, scratch::AbstractString, components::Tuple)
    return [
        stagevalue(item, scratch, (components..., string(index))) for
            (index, item) in enumerate(gathered.items)
    ]
end

resolvevalue(instance::StepInstance, produced) = payload(produced[instance])
resolvevalue(output::Output, produced) =
    payload(selectartifact(produced[output.instance], output.selector))
resolvevalue(value::Tuple, produced) = map(item -> resolvevalue(item, produced), value)
resolvevalue(value::NamedTuple, produced) = map(item -> resolvevalue(item, produced), value)
resolvevalue(value::AbstractArray, produced) = map(item -> resolvevalue(item, produced), value)
resolvevalue(value, produced) = value

function execute(instance::StepInstance, produced, database)
    task_hash = digest(instance)
    existing = row(database, task_hash)
    if !isnothing(existing) && existing.status == "done"
        cached = loadresult(database, task_hash, instance.params)
        if !isnothing(cached) && resultvalid(cached)
            produced[instance] = cached
            return nothing
        end
    end

    record!(database, task_hash, instance; status = "running")
    scratch = scratchdir()
    try
        inputs = [resolveinput(input, produced) for input in instance.inputs]
        staged = [
            stagevalue(input, scratch, (string(index),)) for
                (index, input) in enumerate(inputs)
        ]
        raw_result = cd(scratch) do
            instance.step.f(staged...; instance.params...)
        end
        prepared = prepare(raw_result, scratch)
        stored = withparams(commitresult(prepared), instance.params)
        DBInterface.transaction(database) do
            recordresult!(database, task_hash, stored)
            record!(database, task_hash, instance; status = "done")
        end
        produced[instance] = something(loadresult(database, task_hash, instance.params))
    catch
        record!(database, task_hash, instance; status = "failed")
        rethrow()
    finally
        isdir(scratch) && rm(scratch; recursive = true, force = true)
    end
    return nothing
end

"""
    run(graph; backend=Local())

Execute every step reachable from `graph` and return ordinary Julia values in the same
outer shape. A task becomes a cache hit only when its result manifest exists and every
referenced content object validates.
"""
Base.run(
    graph::Union{StepInstance, Output, Tuple, NamedTuple, AbstractArray};
    backend::ExecutionBackend = Local(),
) = execute(backend, graph)

function execute(::Local, graph)
    execution_plan = plan(graph)
    isempty(execution_plan.order) && return graph
    database = ledger()
    produced = Dict{StepInstance, AbstractArtifact}()
    try
        for instance in execution_plan.order
            execute(instance, produced, database)
        end
        return resolvevalue(graph, produced)
    finally
        close(database)
    end
end
