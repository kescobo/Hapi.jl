module Hapi

export FileDependency,
       FileDepGroup,
       path,
       params,
       glob_pattern,
       groupdeps,
       build_regex

using FilePaths
using FilePathsBase: /
using Dagger
using ClusterManagers
using Base.PCRE # remove for 1.7 - https://github.com/JuliaLang/julia/pull/37299

include("filehandling.jl")
include("processhandling.jl")

end # module