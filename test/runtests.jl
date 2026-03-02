using Test
using DataFrames, Dates

include("fixtures.jl")

@testset "DiscoveryGraph" begin
    # Sub-testsets added per task
    @test nrow(FIXTURE_CORPUS) == 30

    include("../src/schema/config.jl")

    @testset "RoleConfig" begin
        rc = RoleConfig(
            "outside_counsel",
            OutsideFirm,
            [r".*@lawfirm\.com"],
            ["lawfirm.com"],
            Set(["bob@lawfirm.com"]),
        )
        @test rc.label == "outside_counsel"
        @test rc.counsel_type == OutsideFirm
        @test length(rc.address_patterns) == 1
        @test "lawfirm.com" ∈ rc.domain_list
        @test "bob@lawfirm.com" ∈ rc.explicit_addresses
    end
end
