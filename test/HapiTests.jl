module HapiTests

using Hapi
using Hapi.FilePaths
using ReTest

@testset "Hapi.jl" begin
    rgx = build_regex("{thing1}_{thing2}.txt", (thing1=raw"\d+", thing2=raw"\w+"))
    @test rgx isa Regex
    @test occursin(rgx, "file1_a.txt")
    @test !occursin(rgx, "testa_1.txt")

    m1 = match(rgx, "file1_a.txt")
    @test m1[:thing1] == "1"
    @test m1[:thing2] == "a"

    glb = glob_pattern("projects/fileglob/", rgx)
    fd = first(glb)
    @test fd isa FileDependency
    @test path(fd) isa AbstractPath
    @test params(fd) isa NamedTuple
    @test collect(keys(params(fd))) == [:thing1, :thing2]
    @test fd[:thing1] == "1"
    @test fd[:thing2] == "1"

    @test length(glb) == 4
    @test all(f-> f isa FileDependency, glb)
end

end # module