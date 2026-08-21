@testitem "atomic commit: partials never enter the store (I8)" tags = [:invariant] begin
    using Hapi

    root = mktempdir()
    d = digest("some-content")

    td = tmp_dir(; root)
    write(joinpath(td, "partial.txt"), "oops")
    @test !isdir(store_path(d; root))   # interrupted: never committed, never visible

    target = commit!(td, d; root)
    @test target == store_path(d; root)
    @test isdir(target)
    @test isfile(joinpath(target, "partial.txt"))
end
