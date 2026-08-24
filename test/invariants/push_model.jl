@testitem "push model: run executes the wired graph, no backward target resolution (I7)" tags = [:invariant] begin
    using Hapi

    @test hasmethod(run, Tuple{StepInstance})
    @test !hasmethod(run, Tuple{AbstractString})   # no target-name/pull-style API
    @test !isdefined(Hapi, :resolve)
    @test !isdefined(Hapi, :target)

    @step function idstep(p::AbstractPath; sample)::FileArtifact
        return FileArtifact(p; sample)
    end
    p = Path(tempname())
    write(string(p), "x")
    si = idstep(FileArtifact(p; sample = "z"))

    # the FileArtifact input is a leaf — plan() never goes hunting for "what produces it"
    @test plan(si).order == [si]
end
