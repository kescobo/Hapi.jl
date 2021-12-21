struct FileDependency
    path::AbstractPath
    params::NamedTuple
end

FileDependency(p::AbstractPath) = FileDependency(p, NamedTuple())

FileDependency(p::AbstractString, params) = FileDependency(Path(p), params)
FileDependency(p::AbstractString) = FileDependency(Path(p))

path(fdep::FileDependency) = fdep.path
params(fdep::FileDependency) = fdep.params

Base.getindex(fdep::FileDependency, i::Symbol) = getindex(params(fdep), i)

function Base.show(io::IO, fdep::FileDependency)
    print(io, """
        path: $(path(fdep))
            params: $(params(fdep))""")
end

struct FileDepGroup
    deps::Vector{FileDependency}
    sharedparams::NamedTuple
end

deps(fdg::FileDepGroup) = fdg.deps
params(fdg::FileDepGroup) = fdg.sharedparams
path(fdg::FileDepGroup) = path.(deps(fdg))

function Base.show(io::IO, fdg::FileDepGroup)
    print(io, """
        FileDepGroup with $(length(fdg.deps)) dependencies
            shared params: $(params(fdg))""")
end

# This is copied from https://github.com/JuliaLang/julia/pull/37299, not needed in julia 1.7+
function Base.keys(m::RegexMatch)
    idx_to_capture_name = PCRE.capture_names(m.regex.regex)
    return map(eachindex(m.captures)) do i
        # If the capture group is named, return it's name, else return it's index
        get(idx_to_capture_name, i, i)
    end
end

"""
    build_regex(pattern, groups)

A convenience function for generating `Regex` patterns
with named capture groups.
Spots to sub out should be surrounded by curly braces (eg. `{group_name}`)
and then the actual regular expressions as a `NamedTuple`.
For now, pass the regex as a raw string -
I'll figure out how to compose `Regex` objects another time
(or if you know, make a PR!).
eg `(; group_name=raw"\\w+)`.

Examples
≡≡≡≡≡≡≡≡≡≡

```jldoctest
julia> build_regex("{thing1}_{thing2}.txt", (thing1=raw"\\d+", thing2=raw"\\w+"))
r"(?<thing1>\\d+)_(?<thing2>\\w+).txt"
```
"""
function build_regex(pattern, groups)
    for (g, p) in pairs(groups)
        pattern = replace(pattern, string('{',g,'}')=> "(?<$g>$p)")
    end
    return Regex(pattern)
end

"""
    glob_pattern(dir, pattern; recursive=false)

Match files in directory `dir` with the regular expression `pattern`,
returning a vector of [`FileDependency`](@ref)s.
Use `recursive=true` to search for all files in subdirectories.

If `pattern` contins named capture groups
(eg using [`build_regex`](@ref)),
the returned `FileDependency`s will contain the matches for those capture groups
in the `params` field.

Examples
≡≡≡≡≡≡≡≡≡≡

```jldoctest
julia> rgx = build_regex("file{thing1}_{thing2}.txt", (thing1=raw"\\d+", thing2=raw"\\d+"));

julia> readdir("../test/projects/fileglob/")
4-element Vector{String}:
 "file1_1.txt"
 "file1_2.txt"
 "file2_1.txt"
 "file2_2.txt"

julia> glob_pattern("../test/projects/fileglob/", rgx)
4-element Vector{FileDependency}:
 path: ../test/projects/fileglob/file1_1.txt
    params: (thing1 = "1", thing2 = "1")
 path: ../test/projects/fileglob/file1_2.txt
    params: (thing1 = "1", thing2 = "2")
 path: ../test/projects/fileglob/file2_1.txt
    params: (thing1 = "2", thing2 = "1")
 path: ../test/projects/fileglob/file2_2.txt
    params: (thing1 = "2", thing2 = "2")
```
"""
function glob_pattern(dir, pattern; recursive=false)
    dir = Path(dir)
    files = filter(f-> isfile(f) && occursin(pattern, basename(f)), (recursive ? walkpath(dir) : readpath(dir)))
    deps = map(files) do file
        m = match(pattern, string(basename(file)))
        params =  NamedTuple(Symbol(k) => m[k] for k in keys(m))
        FileDependency(file, params)
    end

    return deps
end

"""
    groupdeps(deps, on)

Group a collection of [`FileDependency`](@ref)s based on matching captures groups.


Examples
≡≡≡≡≡≡≡≡≡≡

```jldoctest
julia> rgx = build_regex("file{thing1}_{thing2}.txt", (thing1=raw"\\d+", thing2=raw"\\d+"));

julia> glb = glob_pattern("../test/projects/fileglob/", rgx)
4-element Vector{FileDependency}:
 path: ../test/projects/fileglob/file1_1.txt
    params: (thing1 = "1", thing2 = "1")
 path: ../test/projects/fileglob/file1_2.txt
    params: (thing1 = "1", thing2 = "2")
 path: ../test/projects/fileglob/file2_1.txt
    params: (thing1 = "2", thing2 = "1")
 path: ../test/projects/fileglob/file2_2.txt
    params: (thing1 = "2", thing2 = "2")

julia> groupdeps(glb, [:thing1])
2-element Vector{FileDepGroup}:
 FileDepGroup with 2 dependencies
    shared params: (thing1 = "1",)
 FileDepGroup with 2 dependencies
    shared params: (thing1 = "2",)

```
"""
function groupdeps(deps, on)
    deps = copy(deps)
    depgroups = FileDepGroup[]
    while !isempty(deps)
        curdep = first(deps)
        idx = findall(deps) do d
            for grouper in on
                d[grouper] == curdep[grouper] || return false
            end
            return true
        end
        depgroup = splice!(deps, idx)
        sharedparms = NamedTuple(g=> params(curdep)[g] for g in on)
        push!(depgroups, FileDepGroup(depgroup, sharedparms))
    end
    return depgroups
end

