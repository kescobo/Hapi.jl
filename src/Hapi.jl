module Hapi

export FileDependency,
       FileDepGroup,
       path,
       params,
       glob_pattern,
       groupdeps,
       build_regex,
       path

using FilePaths
using FilePathsBase: /
using Dagger
using ClusterManagers
using ReTest

@testset "Module Test" begin
    @test true
end

include("filehandling.jl")
include("processhandling.jl")

end # module