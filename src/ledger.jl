const STEP_INSTANCES_SCHEMA = """
CREATE TABLE IF NOT EXISTS step_instances (
    hash          TEXT PRIMARY KEY,
    step_name     TEXT NOT NULL,
    code_hash     TEXT NOT NULL,
    params        TEXT NOT NULL,
    env           TEXT NOT NULL,
    status        TEXT NOT NULL,
    started_at    TEXT,
    finished_at   TEXT,
    user          TEXT,
    git_commit    TEXT
)
"""

const RESULT_NODES_SCHEMA = """
CREATE TABLE IF NOT EXISTS result_nodes (
    step_hash     TEXT NOT NULL REFERENCES step_instances(hash),
    node_id       INTEGER NOT NULL,
    parent_id     INTEGER,
    name          TEXT,
    position      INTEGER NOT NULL,
    kind          TEXT NOT NULL,
    object_hash   TEXT,
    logical_name  TEXT,
    PRIMARY KEY (step_hash, node_id)
)
"""

"""
    ledger(file=abspath(".hapi/db/hapi.sqlite")) -> SQLite.DB

Open the local provenance ledger and ensure its schema exists.
"""
function ledger(file::AbstractString = abspath(joinpath(".hapi", "db", "hapi.sqlite")))
    mkpath(dirname(file))
    database = SQLite.DB(file)
    DBInterface.execute(database, "PRAGMA foreign_keys = ON")
    DBInterface.execute(database, STEP_INSTANCES_SCHEMA)
    DBInterface.execute(database, RESULT_NODES_SCHEMA)
    migrateresultnodes!(database)
    return database
end

function migrateresultnodes!(database::SQLite.DB)
    columns = Set(String(result.name) for result in DBInterface.execute(database, "PRAGMA table_info(result_nodes)"))
    if "logical_name" ∉ columns
        DBInterface.execute(database, "ALTER TABLE result_nodes ADD COLUMN logical_name TEXT")
    end
    return nothing
end

"""
    record!(database, task_hash, instance; status)

Insert or update the execution state for one task identity.
"""
function record!(
        database::SQLite.DB,
        task_hash::Digest,
        instance::StepInstance;
        status::AbstractString,
    )
    timestamp = string(now())
    started_at = status == "running" ? timestamp : nothing
    finished_at = status in ("done", "failed") ? timestamp : nothing
    DBInterface.execute(
        database,
        """
        INSERT INTO step_instances
            (hash, step_name, code_hash, params, env, status, started_at, finished_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(hash) DO UPDATE SET
            status=excluded.status,
            started_at=COALESCE(excluded.started_at, step_instances.started_at),
            finished_at=excluded.finished_at
        """,
        (
            string(task_hash),
            string(instance.step.name),
            string(instance.code_hash),
            repr(instance.params),
            string(instance.env),
            status,
            started_at,
            finished_at,
        ),
    )
    return nothing
end

"""
    row(database, task_hash)

Return the task ledger row for `task_hash`, or `nothing` when it has never run.
"""
function row(database::SQLite.DB, task_hash::Digest)
    query = DBInterface.execute(
        database,
        """
        SELECT hash, step_name, code_hash, params, env, status, started_at, finished_at
        FROM step_instances WHERE hash = ?
        """,
        (string(task_hash),),
    )
    for result in query
        return (
            hash = result.hash,
            step_name = result.step_name,
            code_hash = result.code_hash,
            params = result.params,
            env = result.env,
            status = result.status,
            started_at = result.started_at,
            finished_at = result.finished_at,
        )
    end
    return nothing
end

"""
    resultrows(database, task_hash) -> Vector{NamedTuple}

Return the recursive result-manifest rows recorded for a task.
"""
function resultrows(database::SQLite.DB, task_hash::Digest)
    rows = NamedTuple[]
    query = DBInterface.execute(
        database,
        """
        SELECT node_id, parent_id, name, position, kind, object_hash, logical_name
        FROM result_nodes WHERE step_hash = ? ORDER BY node_id
        """,
        (string(task_hash),),
    )
    for result in query
        push!(
            rows,
            (
                node_id = Int(result.node_id),
                parent_id = ismissing(result.parent_id) ? nothing : Int(result.parent_id),
                name = ismissing(result.name) ? nothing : Symbol(result.name),
                position = Int(result.position),
                kind = Symbol(result.kind),
                object_hash = ismissing(result.object_hash) ? nothing : parsedigest(result.object_hash),
                logical_name = ismissing(result.logical_name) ? nothing : String(result.logical_name),
            ),
        )
    end
    return rows
end

function recordresult!(database::SQLite.DB, task_hash::Digest, result::AbstractArtifact)
    DBInterface.execute(
        database,
        "DELETE FROM result_nodes WHERE step_hash = ?",
        (string(task_hash),),
    )
    next_id = Ref(1)
    recordnode!(database, task_hash, result, next_id, nothing, nothing, 1)
    return nothing
end

function insertnode!(
        database,
        task_hash,
        id,
        parent_id,
        name,
        position,
        kind,
        object_hash,
        logical_name,
    )
    DBInterface.execute(
        database,
        """
        INSERT INTO result_nodes
            (step_hash, node_id, parent_id, name, position, kind, object_hash, logical_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            string(task_hash),
            id,
            parent_id,
            isnothing(name) ? nothing : string(name),
            position,
            string(kind),
            isnothing(object_hash) ? nothing : string(object_hash),
            logical_name,
        ),
    )
    return nothing
end

function recordnode!(database, task_hash, file::FileArtifact, next_id, parent_id, name, position)
    id = next_id[]
    next_id[] += 1
    isnothing(file.hash) && error("cannot record a produced file without a content hash")
    insertnode!(
        database,
        task_hash,
        id,
        parent_id,
        name,
        position,
        :file,
        file.hash,
        file.logical_name,
    )
    return id
end

function recordnode!(database, task_hash, ::AbsentArtifact, next_id, parent_id, name, position)
    id = next_id[]
    next_id[] += 1
    insertnode!(database, task_hash, id, parent_id, name, position, :absent, nothing, nothing)
    return id
end

function recordnode!(database, task_hash, branch::NamedArtifact, next_id, parent_id, name, position)
    id = next_id[]
    next_id[] += 1
    insertnode!(database, task_hash, id, parent_id, name, position, :named, nothing, nothing)
    for (child_position, (child_name, child)) in enumerate(pairs(branch.values))
        recordnode!(database, task_hash, child, next_id, id, child_name, child_position)
    end
    return id
end

function loadresult(database::SQLite.DB, task_hash::Digest, params::NamedTuple)
    rows = resultrows(database, task_hash)
    isempty(rows) && return nothing
    any(row -> row.kind == :file && isnothing(row.logical_name), rows) && return nothing
    by_id = Dict(row.node_id => row for row in rows)
    root = buildnode(task_hash, by_id, rows, 1)
    return withparams(root, params)
end

buildnode(task_hash, by_id, rows, id) =
    buildnode(Val(by_id[id].kind), task_hash, by_id, rows, id)

function buildnode(::Val{:file}, task_hash, by_id, rows, id)
    hash = something(by_id[id].object_hash)
    logical_name = something(by_id[id].logical_name)
    object = path(hash)
    visible = if isfile(object) && digest(Path(object)) == hash
        materializeresult!(task_hash, id, logical_name, hash)
    else
        object
    end
    return FileArtifact(Path(visible), logical_name, hash, NamedTuple())
end

buildnode(::Val{:absent}, task_hash, by_id, rows, id) = AbsentArtifact()

function buildnode(::Val{:named}, task_hash, by_id, rows, id)
    children = filter(row -> row.parent_id == id, rows)
    sort!(children; by = row -> row.position)
    values = NamedTuple(
        row.name => buildnode(task_hash, by_id, rows, row.node_id) for row in children
    )
    return NamedArtifact(values, NamedTuple())
end

resultvalid(file::FileArtifact) = isfile(string(file.path)) && digest(file.path) == file.hash
resultvalid(::AbsentArtifact) = true
resultvalid(branch::NamedArtifact) = all(resultvalid, values(branch.values))
