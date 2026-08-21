@testitem "Phase-0 forward-compat hooks exist (I11)" tags = [:invariant] begin
    using Hapi

    f(x) = x
    si = Step(f, :noop)()
    h = instance_hash(si)

    db = open_ledger(joinpath(mktempdir(), "hapi.sqlite"))
    record_step_instance!(db, h, si)
    record_output!(db, h, :out, :intentionally_absent)   # (a) intentionally-absent state
    row = step_instance_row(db, h)
    @test row.status == "pending"
    @test row.temp_refcount == 0                          # (b) consumer-refcount column

    @test si.retention isa Symbol
    @test si.retention in (:temp, :cached, :published)     # (b) retention class

    p = plan(si)
    @test hasfield(typeof(p), :frontier)
    @test p.frontier === false                             # (c) frontier hook, always false today
end
