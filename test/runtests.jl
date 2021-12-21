include("HapiTests.jl")

using Hapi
using .HapiTests

Hapi.runtests()
HapiTests.runtests()

