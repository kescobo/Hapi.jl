"""
    Step(f, name; depends_on=[])

The graph-building form of an ordinary Julia function. A `Step` contains no execution
backend, environment delivery mechanism, resources, or output declarations. Applying it to
artifacts creates a [`StepInstance`](@ref); it never calls `f`.
"""
struct Step
    f::Function
    name::Symbol
    depends_on::Vector{Function}
end

Step(f::Function, name::Symbol; depends_on = Function[]) =
    Step(f, name, collect(Function, depends_on))

"""
    StepInstance <: AbstractArtifact

A lazy application of a [`Step`](@ref) to concrete inputs and parameters.
"""
struct StepInstance <: AbstractArtifact
    step::Step
    code_hash::Digest
    inputs::Vector{AbstractArtifact}
    params::NamedTuple
    env::EnvName
    resources::Resources
end

function merge_params(inputs, keywords::NamedTuple)
    params = NamedTuple()
    for input in inputs
        params = merge(params, paramsof(input))
    end
    return merge(params, keywords)
end

function (step::Step)(inputs::AbstractArtifact...; params...)
    return StepInstance(
        step,
        digest(step),
        collect(AbstractArtifact, inputs),
        merge_params(inputs, NamedTuple(params)),
        :native,
        Resources(),
    )
end

paramsof(instance::StepInstance) = instance.params

payload(instance::StepInstance) = error(
    "StepInstance for step :$(instance.step.name) is a graph node; call run on the graph to produce its value."
)

"""
    Output(instance, selector)

A lazy reference to a named branch or leaf in a step's structured result.
"""
struct Output <: AbstractArtifact
    instance::StepInstance
    selector::Tuple{Vararg{Symbol}}
end

Base.getindex(instance::StepInstance, name::Symbol) = Output(instance, (name,))
Base.getindex(output::Output, name::Symbol) = Output(output.instance, (output.selector..., name))
paramsof(output::Output) = output.instance.params

payload(output::Output) = error(
    "Output $(output.selector) of step :$(output.instance.step.name) is a graph reference; call run on the graph to produce its value."
)

function digest(output::Output)
    parts = Digest[digest("output-selector-v1"), digest(output.instance)]
    append!(parts, digest(string(name)) for name in output.selector)
    return digest(parts...)
end

concretemethods(f) = [method for method in methods(f) if !isgraphmethod(method)]
isgraphmethod(method::Method) = any(
    mentions_abstractartifact,
    Base.unwrap_unionall(method.sig).parameters[2:end],
)
mentions_abstractartifact(type::Core.TypeofVararg) =
    isdefined(type, :T) && mentions_abstractartifact(type.T)
mentions_abstractartifact(type::Type) = type <: AbstractArtifact
mentions_abstractartifact(type) = false

const STEP_DEFINITION_SOURCES = IdDict{Method, String}()

function register_step_definition!(f, file::Symbol, line::Integer, source::AbstractString)
    registered = false
    for method in concretemethods(f)
        if method.file == file && method.line == line
            STEP_DEFINITION_SOURCES[method] = String(source)
            registered = true
        end
    end
    registered || error("@step could not identify the concrete method declared at $(file):$(line)")
    return nothing
end

function digest(step::Step)
    concrete_methods = concretemethods(step.f)
    assert_no_captures(step.f, concrete_methods)
    sources = String[sourcetext(method) for method in concrete_methods]
    for dependency in step.depends_on
        assert_no_captures(dependency)
        append!(sources, sourcetext(method) for method in methods(dependency))
    end
    sort!(sources)
    return digest("step-code-v2", join(sources, "\0"))
end

function sourcetext(method::Method)
    captured = get(STEP_DEFINITION_SOURCES, method, nothing)
    if isreplorigin(method.file) && !isnothing(captured)
        return captured
    end
    return sourcetext(CodeTracking.definition(String, method), method)
end

isreplorigin(file::Symbol) = !isnothing(match(r"^REPL\[\d+\]$", String(file)))

sourcetext(source::AbstractString, method::Method) = String(source)
sourcetext(source::Tuple{<:AbstractString, <:Integer}, method::Method) = String(first(source))
function sourcetext(::Nothing, method::Method)
    source = get(STEP_DEFINITION_SOURCES, method, nothing)
    isnothing(source) && error("source text is unavailable for method $(method)")
    return source
end

"""
    @step function f(values...; parameters...)
        ...
    end

Leave an ordinary function body untouched and add artifact-dispatching graph behavior under
the same name. Direct calls on ordinary Julia values execute immediately. Calls on Hapi
artifacts return a lazy [`StepInstance`](@ref). The macro also retains a normalized copy of
the definition so REPL-authored steps remain hashable when the REPL does not expose standard
Julia history.
"""
macro step(expression)
    definition = splitdef(expression)
    name = stepname(definition[:name])
    step_variable = gensym(name)
    source_expression = Base.remove_linenums!(deepcopy(expression))
    source = sprint(show, source_expression)
    lines = Int[]
    prewalk(expression) do node
        if node isa LineNumberNode && node.file == __source__.file
            push!(lines, node.line)
        end
        return node
    end
    definition_line = isempty(lines) ? __source__.line : minimum(lines)
    return quote
        $(esc(combinedef(definition)))
        register_step_definition!(
            $(esc(name)),
            $(QuoteNode(__source__.file)),
            $definition_line,
            $(QuoteNode(source)),
        )
        const $(esc(step_variable)) = Step($(esc(name)), $(QuoteNode(name)))
        $(esc(name))(inputs::AbstractArtifact...; params...) =
            $(esc(step_variable))(inputs...; params...)
    end
end

stepname(name::Symbol) = name
stepname(name) = error("@step requires a plain function name, got $(name)")

envdigest(env::EnvName) = envdigest(Val(env))

function envdigest(::Val{:native})
    project = Base.active_project()
    project_hash = isnothing(project) || !isfile(project) ? digest("no-project") : digest(read(project))
    manifest = isnothing(project) ? nothing : joinpath(dirname(project), "Manifest.toml")
    manifest_hash = isnothing(manifest) || !isfile(manifest) ? digest("no-manifest") : digest(read(manifest))
    return digest(
        digest("native-environment-v1"),
        digest(string(VERSION)),
        project_hash,
        manifest_hash,
    )
end

envdigest(::Val{E}) where {E} =
    error("environment :$E has not been resolved; only the exact native environment is supported")

function digest(instance::StepInstance)
    parts = Digest[
        digest("task-v3"),
        instance.code_hash,
        paramdigest(instance.params),
        envdigest(instance.env),
    ]
    append!(parts, digest(input) for input in instance.inputs)
    return digest(parts...)
end
