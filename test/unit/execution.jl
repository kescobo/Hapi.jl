@testitem "run executes, commits, and cache-hits on re-run" tags = [:slow] begin
    using Hapi

    dir = mktempdir()
    write(joinpath(dir, "a.txt"), "hello world")

    calls = Ref(0)
    # plain-value in, plain-value out — no Hapi types in the body (run wraps the result)
    @step function wc(p::AbstractPath; sample)::AbstractPath
        calls[] += 1
        out = Path(basename(string(p)) * "_wc")
        write(string(out), string(length(split(read(p, String)))))
        return out
    end

    cd(dir) do
        fa = FileArtifact(joinpath(dir, "a.txt"); sample = "A")
        si = wc(fa)
        result = run(si)
        @test isfile(string(result.path))
        @test read(string(result.path), String) == "2"
        @test calls[] == 1

        result2 = run(si)
        @test calls[] == 1   # cache hit, no re-execution
        @test string(result.path) == string(result2.path)

        db = ledger()
        rec = row(db, digest(si))
        @test rec.status == "done"
    end
end
