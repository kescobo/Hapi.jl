@testitem "push model: run executes the wired graph, no backward target resolution (I7)" tags = [:invariant] begin
    using Hapi

    @test hasmethod(run, Tuple{StepInstance})
    # `run` takes whatever `targets` can walk (a StepInstance, or nested collections of
    # them) — genuinely no target-*name* API exists: a String isn't a graph, so it finds
    # nothing to execute and comes back unchanged, rather than resolving to anything.
    cd(mktempdir()) do
        @test run("not-a-graph") == "not-a-graph"
    end

    @step function idstep(p::AbstractPath; sample)::FileArtifact
        return FileArtifact(p; sample)
    end
    p = Path(tempname())
    write(string(p), "x")
    si = idstep(FileArtifact(p; sample = "z"))

    # the FileArtifact input is a leaf — plan() never goes hunting for "what produces it"
    @test plan(si).order == [si]
end
