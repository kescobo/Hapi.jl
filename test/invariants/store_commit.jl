@testitem "atomic commit: partials never enter the store (I8)" tags = [:invariant] begin
    using Hapi

    root = mktempdir()
    d = digest("some-content")

    td = scratchdir(; root)
    write(joinpath(td, "partial.txt"), "oops")
    @test !isdir(path(d; root))   # interrupted: never committed, never visible

    target = commit!(td, d; root)
    @test target == path(d; root)
    @test isdir(target)
    @test isfile(joinpath(target, "partial.txt"))
end
