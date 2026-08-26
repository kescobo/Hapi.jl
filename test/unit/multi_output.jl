@testitem "multi-output steps: independent commit, hash, cache-hit, wiring" tags = [:slow] begin
    using Hapi

    calls = Ref(0)
    @step function split3(p::AbstractPath; sample)
        calls[] += 1
        base = basename(string(p))
        a = Path(base * "_a")
        b = Path(base * "_b")
        c = Path(base * "_c")
        write(string(a), "A")
        write(string(b), "B")
        write(string(c), "C")
        return (a = a, b = b, c = c)
    end

    @step function readback(p::AbstractPath; sample)::AbstractPath
        out = Path(basename(string(p)) * "_copy")
        write(string(out), read(p, String))
        return out
    end

    dir = mktempdir()
    write(joinpath(dir, "in.txt"), "x")

    cd(dir) do
        fa = FileArtifact(joinpath(dir, "in.txt"); sample = "S")
        si = split3(fa)

        # two outputs of the same instance hash differently as consumer inputs
        @test digest(si[:a]) != digest(si[:b])

        result = run(readback(si[:b]))
        @test read(string(result.path), String) == "B"
        @test calls[] == 1

        # cache hit: reconstructing si's other outputs doesn't re-run split3
        result2 = run(readback(si[:c]))
        @test calls[] == 1
        @test read(string(result2.path), String) == "C"

        db = ledger()
        orows = outputrows(db, digest(si))
        @test Set(r.name for r in orows) == Set([:a, :b, :c])
        @test all(r -> r.state == :present, orows)
    end
end
