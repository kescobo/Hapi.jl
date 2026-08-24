@testitem "glob_table parses wildcards" tags = [:fast] begin
    using Hapi

    dir = mktempdir()
    write(joinpath(dir, "sample_A.txt"), "x")
    write(joinpath(dir, "sample_B.txt"), "y")
    write(joinpath(dir, "other.txt"), "z")   # shouldn't match

    tbl = glob_table(joinpath(dir, "sample_{sample}.txt"))
    @test length(tbl) == 2
    @test Set(r.sample for r in tbl) == Set(["A", "B"])
    @test all(r -> isfile(string(r.path)), tbl)
end

@testitem "source lifts rows into artifacts" tags = [:fast] begin
    using Hapi

    dir = mktempdir()
    write(joinpath(dir, "sample_A.txt"), "x")
    tbl = glob_table(joinpath(dir, "sample_{sample}.txt"))

    artifacts = source(tbl) do row
        FileArtifact(row.path; sample = row.sample)
    end
    @test length(artifacts) == 1
    @test only(artifacts).params.sample == "A"
end
