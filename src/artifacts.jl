# The trait every input type implements (plan.md §3, I10). Concrete subtypes
# (FileArtifact, ObjectArtifact, FileGroupArtifact, StoredRef, Reference) are Phase 1.
abstract type AbstractArtifact end

"""
    payload(artifact::AbstractArtifact)

Unwrap `artifact` to the concrete value(s) a step body operates on — a scalar or a
`NamedTuple`, whatever shape the consuming step body wants. This is the entire
extension contract: a type flows through steps by implementing this one method.
"""
function payload end
