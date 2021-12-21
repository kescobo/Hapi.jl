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
using ReTest
using Base.PCRE # remove for 1.7 - https://github.com/JuliaLang/julia/pull/37299

@testset "Module Test" begin
    @test true
end

include("filehandling.jl")
include("processhandling.jl")

end # module