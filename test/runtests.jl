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

    @testset "CorpusConfig" begin
        rc = RoleConfig("outside_counsel", OutsideFirm,
            [r".*@lawfirm\.com"], ["lawfirm.com"], Set(["bob@lawfirm.com"]))

        cfg = CorpusConfig(
            sender         = :sender,
            recipients_to  = :tos,
            recipients_cc  = :ccs,
            timestamp      = :date,
            subject        = :subj,
            hash           = :hash,
            lastword       = :lastword,
            corpus_start   = DateTime(2000, 1, 1),
            corpus_end     = DateTime(2002, 12, 31),
            baseline_start = DateTime(2000, 7, 1),
            baseline_end   = DateTime(2000, 9, 30),
            roles          = [rc],
        )
        @test cfg.sender == :sender
        @test cfg.corpus_start == DateTime(2000, 1, 1)
        @test length(cfg.roles) == 1
        @test cfg.broadcast_discount(0) ≈ 1 / log(2)
    end
end
