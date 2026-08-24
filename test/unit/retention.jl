@testitem "retention overlay: validation, layering, defaults" tags = [:slow] begin
    using Hapi

    @step function stepA(p::AbstractPath; sample)::AbstractPath
        return p
    end
    @step function stepB(p::AbstractPath; sample)
        return (x = p, y = p)
    end

    dir = mktempdir()
    write(joinpath(dir, "in.txt"), "x")

    cd(dir) do
        fa = FileArtifact(joinpath(dir, "in.txt"); sample = "S")
        a = stepA(fa)
        b = stepB(a)

        @test_throws ErrorException retention((; a, b), :nosuchstep => :published)

        policy = retention((; a, b), :stepA => :published, :stepB => (y = :temp,))
        @test Hapi.retentionfor(policy, :stepA, :stepA) == :published
        @test Hapi.retentionfor(policy, :stepB, :y) == :temp
        @test Hapi.retentionfor(policy, :stepB, :x) == :cached   # not overridden
        @test Hapi.retentionfor(nothing, :stepA, :stepA) == :cached
        @test Hapi.retentionfor(policy, :unrelated, :whatever) == :cached

        run((; a, b); retention = policy)
        db = ledger()
        arow = only(outputrows(db, digest(a)))
        @test arow.retention == :published

        browsB = outputrows(db, digest(b))
        yrow = only(filter(r -> r.name == :y, browsB))
        xrow = only(filter(r -> r.name == :x, browsB))
        @test yrow.retention == :temp
        @test xrow.retention == :cached
    end
end
