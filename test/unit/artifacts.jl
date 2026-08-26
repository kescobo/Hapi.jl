@testitem "FileArtifact payload and digest" tags = [:fast] begin
    using Hapi

    dir = mktempdir()
    p = joinpath(dir, "a.txt")
    write(p, "hello")

    fa = FileArtifact(p; sample = "A")
    @test payload(fa) == fa.path
    @test fa.hash === nothing

    # not yet produced: digest is the real content hash, changes if the file changes
    d1 = digest(fa)
    write(p, "hello!")
    d2 = digest(fa)
    @test d1 != d2

    # once produced (.hash set), digest just returns it — no re-reading the file
    produced = FileArtifact(p, Hapi.digest("fixed"), fa.params)
    @test digest(produced) == Hapi.digest("fixed")
end

@testitem "FileGroupArtifact payload and digest" tags = [:fast] begin
    using Hapi

    dir = mktempdir()
    p1, p2 = joinpath(dir, "r1.txt"), joinpath(dir, "r2.txt")
    write(p1, "a")
    write(p2, "b")

    fg = FileGroupArtifact((R1 = FileArtifact(p1), R2 = FileArtifact(p2)); sample = "A")
    @test payload(fg) == (R1 = Path(p1), R2 = Path(p2))
    @test digest(fg) == digest(digest(fg.files.R1), digest(fg.files.R2))
end

@testitem "FileGroupArtifact indexing" tags = [:fast] begin
    using Hapi

    dir = mktempdir()
    p1, p2 = joinpath(dir, "r1.txt"), joinpath(dir, "r2.txt")
    write(p1, "a")
    write(p2, "b")

    fg = FileGroupArtifact((R1 = FileArtifact(p1), R2 = FileArtifact(p2)); sample = "A")

    # single key unwraps to the member, with the group's params merged in — members carry
    # none of their own, so this is the only way `sample` survives pulling one out
    r1 = fg[:R1]
    @test r1 isa FileArtifact
    @test r1.path == Path(p1)
    @test r1.params == (; sample = "A")

    # a tuple of keys gives back another FileGroupArtifact over just that subset (mirrors
    # NamedTuple's own indexing), not a bare collection
    sub = fg[(:R1, :R2)]
    @test sub isa FileGroupArtifact
    @test sub.params == fg.params
    @test sub.hash === nothing   # not the parent's — the subset isn't byte-identical to it
    @test digest(sub) == digest(fg)   # same members, so recombines to the same value here

    # a member's own params (if it ever has any) win over the group's on conflict
    fg2 = FileGroupArtifact((R1 = FileArtifact(p1; sample = "override"), R2 = FileArtifact(p2)); sample = "A")
    @test fg2[:R1].params == (; sample = "override")
end

@testitem "artifact lifts a step body's plain return value (the inverse of payload)" tags = [:fast] begin
    using Hapi

    dir = mktempdir()
    p1, p2 = joinpath(dir, "r1.txt"), joinpath(dir, "r2.txt")
    write(p1, "a")
    write(p2, "b")

    # a plain path becomes a FileArtifact
    fa = artifact(Path(p1), (; sample = "A"))
    @test fa isa FileArtifact
    @test fa.path == Path(p1)
    @test fa.params == (; sample = "A")

    # an explicitly-constructed FileGroupArtifact passes through unchanged — it's ONE
    # grouped output, not several (a *bare* NamedTuple return means several separate
    # outputs instead; that's handled in `run`'s execution loop, not by `artifact` — see
    # test/unit/multi_output.jl)
    grouped = FileGroupArtifact((R1 = FileArtifact(p1), R2 = FileArtifact(p2)); sample = "A")
    @test artifact(grouped, (; sample = "ignored")) === grouped

    # a body that already returns an artifact (full control, e.g. an explicit hash) passes
    # through unchanged
    explicit = FileArtifact(p1, Hapi.digest("custom"), (; sample = "B"))
    @test artifact(explicit, (; sample = "ignored")) === explicit
end
