@testitem "forward-compat hooks: output state, retention refcount, plan frontier (I11)" tags = [:invariant] begin
    using Hapi

    f(x) = x
    si = Step(f, :noop)()
    h = digest(si)

    db = ledger(joinpath(mktempdir(), "hapi.sqlite"))
    record!(db, h, si)
    record!(db, h, :out, :intentionally_absent)   # (a) intentionally-absent state
    rec = row(db, h)
    @test rec.status == "pending"

    orow = only(outputrows(db, h))
    @test orow.state == :intentionally_absent               # (a) intentionally-absent state
    @test orow.temp_refcount == 0                            # (b) consumer-refcount column
    @test orow.retention isa Symbol
    @test orow.retention in (:temp, :cached, :published)     # (b) retention class, per-output

    @test si.retention isa Symbol
    @test si.retention in (:temp, :cached, :published)       # (b) retention class, per-instance hook

    p = plan(si)
    @test hasfield(typeof(p), :frontier)
    @test p.frontier === false                             # (c) frontier hook, always false today
end
