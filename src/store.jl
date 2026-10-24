"""
    path(digest; root=abspath(".hapi"))

Path of an immutable content object in the local store.
"""
path(hash::Digest; root::AbstractString = abspath(".hapi")) =
    joinpath(root, "store", "objects", string(hash)[1:2], string(hash))

"""
    scratchdir(; root=abspath(".hapi"))

Create an execution directory on the store filesystem so committing an output object uses
an atomic rename.
"""
function scratchdir(; root::AbstractString = abspath(".hapi"))
    parent = joinpath(root, "tmp")
    mkpath(parent)
    return mktempdir(parent)
end

"""
    commit!(source, digest; root=abspath(".hapi"))

Move a validated file into the immutable object store. An existing object with the same
content hash is reused.
"""
function commit!(source::AbstractString, hash::Digest; root::AbstractString = abspath(".hapi"))
    target = path(hash; root)
    mkpath(dirname(target))
    if isfile(target)
        digest(Path(target)) == hash && return target
        mv(source, target; force = true)
        return target
    end
    mv(source, target)
    return target
end

"""
    resultpath(task_hash, node_id, logical_name; root=abspath(".hapi"))

Stable execution-visible path for a result-manifest file node. The file is a hard link to
the byte-addressed object, keeping its logical basename without duplicating its contents.
"""
function resultpath(
        task_hash::Digest,
        node_id::Integer,
        logical_name::AbstractString;
        root::AbstractString = abspath(".hapi"),
    )
    validate_logical_name(logical_name)
    return joinpath(root, "results", string(task_hash), string(node_id), logical_name)
end

function materializeresult!(
        task_hash::Digest,
        node_id::Integer,
        logical_name::AbstractString,
        object_hash::Digest;
        root::AbstractString = abspath(".hapi"),
    )
    source = path(object_hash; root)
    destination = resultpath(task_hash, node_id, logical_name; root)
    mkpath(dirname(destination))
    if isfile(destination)
        digest(Path(destination)) == object_hash && return destination
        rm(destination; force = true)
    end
    Base.Filesystem.hardlink(source, destination)
    return destination
end

function outputpath(path::AbstractPath, scratch::AbstractString)
    candidate = string(path)
    absolute = isabspath(candidate) ? normpath(candidate) : normpath(joinpath(scratch, candidate))
    isfile(absolute) || error("step returned an output that does not exist: $absolute")
    islink(absolute) && error("symbolic-link outputs are not supported: $absolute")
    canonical = realpath(absolute)
    relative = relpath(canonical, realpath(scratch))
    first(splitpath(relative)) == ".." &&
        error("step output is outside its scratch directory: $canonical")
    return canonical
end
