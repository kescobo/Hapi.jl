# A content hash. Wraps the raw SHA-256 digest so callers get hex `show`/`string` for
# free instead of reading raw bytes everywhere (store paths, ledger rows, `hapi why`).
struct Digest
    bytes::NTuple{32, UInt8}
end

digest(data::AbstractVector{UInt8}) = Digest(NTuple{32, UInt8}(sha256(data)))
digest(s::AbstractString) = digest(Vector{UInt8}(codeunits(s)))

# Combine several digests into one, order-sensitive — used to fold a StepInstance's
# code hash, params, env identity, and each input's hash into a single instance hash.
combine(parts::Digest...) = digest(reduce(vcat, (collect(p.bytes) for p in parts); init = UInt8[]))

Base.string(d::Digest) = bytes2hex(collect(d.bytes))
Base.show(io::IO, d::Digest) = print(io, "Digest(", string(d)[1:12], "…)")
Base.:(==)(a::Digest, b::Digest) = a.bytes == b.bytes
Base.hash(d::Digest, h::UInt) = hash(d.bytes, h)

"""
    assert_no_captures(f)

I9's "captured non-const globals are a hard error" — two distinct Julia mechanisms, both
checked: (1) a closure over a *local* variable stores that state as a field on its
synthesized callable type, so any such closure (`nfields(f) != 0`) is rejected outright;
(2) a plain top-level function referencing a *global* doesn't capture anything structurally
— it resolves the global at call time — so each method's lowered code is scanned for
`GlobalRef`s and any pointing at a non-`const` binding is rejected. Referencing other
functions/types (ordinary `const` bindings) is unaffected.
"""
function assert_no_captures(f)
    nfields(f) == 0 || error(
        "$(nameof(typeof(f))) captures local state (has $(nfields(f)) field(s)) — task " *
            "functions must be pure and top-level; use explicit `depends_on` for callee " *
            "dependencies instead."
    )
    for m in methods(f)
        for gr in globalrefs(Base.uncompressed_ast(m))
            isconst(gr.mod, gr.name) || error(
                "$(m.name) references non-const global $(gr.mod).$(gr.name) — task " *
                    "functions must be pure and top-level; make it `const` or pass it as an argument."
            )
        end
    end
    return nothing
end

function globalrefs(ci::Core.CodeInfo)
    refs = GlobalRef[]
    for stmt in ci.code
        collect_globalrefs!(refs, stmt)
    end
    return refs
end

collect_globalrefs!(acc::Vector{GlobalRef}, x::GlobalRef) = push!(acc, x)
function collect_globalrefs!(acc::Vector{GlobalRef}, x::Expr)
    for a in x.args
        collect_globalrefs!(acc, a)
    end
    return acc
end
collect_globalrefs!(acc::Vector{GlobalRef}, x) = acc
