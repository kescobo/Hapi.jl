# SQLite provenance ledger (plan §5). Two of the columns below exist purely as
# forward-compat hooks (I11) — nothing here yet writes anything but their default/
# 'present'/'failed' values, but retrofitting the columns later would mean a schema
# migration once optional outputs and retention/GC land.
const STEP_INSTANCES_SCHEMA = """
CREATE TABLE IF NOT EXISTS step_instances (
    hash          TEXT PRIMARY KEY,
    step_name     TEXT NOT NULL,
    code_hash     TEXT NOT NULL,
    params        TEXT NOT NULL,
    env           TEXT NOT NULL,
    retention     TEXT NOT NULL,             -- 'temp' | 'cached' | 'published'      (I11b)
    temp_refcount INTEGER NOT NULL DEFAULT 0, -- consumer refcount, 'temp' only       (I11b)
    status        TEXT NOT NULL,             -- 'pending' | 'running' | 'done' | 'failed'
    started_at    TEXT,
    finished_at   TEXT,
    user          TEXT,
    git_commit    TEXT
)
"""

const OUTPUTS_SCHEMA = """
CREATE TABLE IF NOT EXISTS outputs (
    step_hash   TEXT NOT NULL REFERENCES step_instances(hash),
    name        TEXT NOT NULL,
    state       TEXT NOT NULL,               -- 'present' | 'intentionally_absent' | 'failed' (I11a)
    output_hash TEXT,
    PRIMARY KEY (step_hash, name)
)
"""

"""
    ledger(file=".hapi/db/hapi.sqlite") -> SQLite.DB

Open (creating if needed) the provenance ledger, ensuring the schema exists.
"""
function ledger(file::AbstractString = joinpath(".hapi", "db", "hapi.sqlite"))
    mkpath(dirname(file))
    db = SQLite.DB(file)
    DBInterface.execute(db, STEP_INSTANCES_SCHEMA)
    DBInterface.execute(db, OUTPUTS_SCHEMA)
    return db
end

"""
    record!(db, hash, si::StepInstance; status="pending", user=nothing, git_commit=nothing)
    record!(db, step_hash, name::Symbol, state::Symbol; output_hash=nothing)

Upsert a ledger row: either a `StepInstance`'s own row, or one of its outputs' state
(`:present` | `:intentionally_absent` | `:failed`, I11a).
"""
function record!(
        db::SQLite.DB, hash::Digest, si::StepInstance;
        status::AbstractString = "pending",
        user::Union{Nothing, AbstractString} = nothing,
        git_commit::Union{Nothing, AbstractString} = nothing
    )
    DBInterface.execute(
        db,
        """
        INSERT INTO step_instances
            (hash, step_name, code_hash, params, env, retention, temp_refcount, status, user, git_commit)
        VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?)
        ON CONFLICT(hash) DO UPDATE SET status=excluded.status
        """,
        (
            string(hash), string(si.step.name), string(si.code_hash), repr(si.params),
            string(si.env), string(si.retention), status, user, git_commit,
        )
    )
    return nothing
end

function record!(
        db::SQLite.DB, step_hash::Digest, name::Symbol, state::Symbol;
        output_hash::Union{Nothing, Digest} = nothing
    )
    state in (:present, :intentionally_absent, :failed) ||
        error("output state must be :present, :intentionally_absent, or :failed, got :$state")
    DBInterface.execute(
        db,
        """
        INSERT INTO outputs (step_hash, name, state, output_hash)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(step_hash, name) DO UPDATE SET state=excluded.state, output_hash=excluded.output_hash
        """,
        (
            string(step_hash), string(name), string(state),
            output_hash === nothing ? nothing : string(output_hash),
        )
    )
    return nothing
end

"""
    row(db, hash) -> Union{Nothing,NamedTuple}

The raw `step_instances` ledger row for `hash`, or `nothing` if no such StepInstance was
recorded. The basis for the `hapi why` command once the CLI exists.
"""
function row(db::SQLite.DB, hash::Digest)
    for r in DBInterface.execute(
            db,
            """
            SELECT hash, step_name, code_hash, params, env, retention, temp_refcount, status
            FROM step_instances WHERE hash = ?
            """,
            (string(hash),)
        )
        return (
            hash = r.hash, step_name = r.step_name, code_hash = r.code_hash, params = r.params,
            env = r.env, retention = r.retention, temp_refcount = r.temp_refcount, status = r.status,
        )
    end
    return nothing
end
