using Test
using DataFrames, Dates

include("fixtures.jl")

@testset "DiscoveryGraph" begin
    # Sub-testsets added per task
    @test nrow(FIXTURE_CORPUS) == 30
end
