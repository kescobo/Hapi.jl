"""
    source(f, tbl) -> Vector

The one real input boundary (plan §6.1). `tbl` is any Tables.jl row source (a `DataFrame`,
`glob_table`'s output, a hand-built `Vector{NamedTuple}` — Hapi owns no sample-sheet type);
`f(row)` lifts each row into a typed artifact. Reading, filtering, and joining tables is
ordinary user code, not Hapi's. Meant to be used with `do`-block syntax:
```julia
reads = source(tbl) do row
    FileArtifact(row.path; sample = row.sample)
end
```
"""
source(f, tbl) = [f(row) for row in Tables.rows(tbl)]

"""
    glob_table(pattern::AbstractString) -> Vector{NamedTuple}

Hapi's one tabular job: parse the `{wildcard}` convention out of filenames matching
`pattern` (e.g. `"data/{sample}.fastq.gz"`) into a table — one row per matched file, one
column per named wildcard, plus `path` holding the matched file. Anything fancier
(grouping, joining, pivoting) is ordinary Tables.jl/DataFrames code, not Hapi's (§6.1) —
bypass this entirely and use any other Tables.jl source when there's no glob to parse.
"""
function glob_table(pattern::AbstractString)
    dir, filepattern = splitdir(pattern)
    isempty(dir) && (dir = ".")
    names = Symbol[]
    rxstr = replace(
        filepattern, r"\{(\w+)\}" => function (m)
            push!(names, Symbol(m[2:(end - 1)]))
            return "(?<$(m[2:(end - 1)])>[^/]+)"
        end
    )
    rx = Regex("^" * rxstr * "\$")
    rows = NamedTuple[]
    for fname in readdir(dir)
        m = match(rx, fname)
        m === nothing && continue
        wildcards = NamedTuple(n => m[string(n)] for n in names)
        push!(rows, merge(wildcards, (path = Path(joinpath(dir, fname)),)))
    end
    return rows
end
