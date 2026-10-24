"""
    source(f, table; params=row -> NamedTuple()) -> Vector{AbstractArtifact}

Apply ordinary Julia code to each row of any Tables.jl source, then lift the returned value
into the workflow graph. A path becomes a file source and a `NamedTuple` becomes a structured
source whose shape is preserved.
"""
function source(f, table; params = row -> NamedTuple())
    artifacts = AbstractArtifact[]
    for row in Tables.rows(table)
        push!(artifacts, sourceartifact(f(row), params(row)))
    end
    return artifacts
end

sourceartifact(value, metadata::NamedTuple) = artifact(value, metadata)
sourceartifact(value, metadata) = error("source params must return a NamedTuple")

"""
    glob_table(pattern) -> Vector{NamedTuple}

Parse `{name}` wildcard fields from matching filenames into a plain Tables.jl-compatible
row collection.
"""
function glob_table(pattern::AbstractString)
    directory, file_pattern = splitdir(pattern)
    isempty(directory) && (directory = ".")
    names = Symbol[]
    regex_pattern = replace(
        file_pattern,
        r"\{(\w+)\}" => function (match)
            name = match[2:(end - 1)]
            push!(names, Symbol(name))
            return "(?<$name>[^/]+)"
        end,
    )
    regex = Regex("^" * regex_pattern * "\$")
    rows = NamedTuple[]
    for filename in readdir(directory)
        match_result = match(regex, filename)
        isnothing(match_result) && continue
        wildcards = NamedTuple(name => match_result[string(name)] for name in names)
        push!(rows, merge(wildcards, (; path = Path(joinpath(directory, filename)))))
    end
    return rows
end
