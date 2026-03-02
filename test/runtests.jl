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

    include("../src/schema/validate.jl")

    @testset "load_corpus" begin
        cfg = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = RoleConfig[])

        df = load_corpus(FIXTURE_CORPUS, cfg)
        @test nrow(df) == 30

        # Missing required column
        bad = select(FIXTURE_CORPUS, Not(:sender))
        @test_throws ArgumentError load_corpus(bad, cfg)

        # Missing values in sender
        bad2 = copy(FIXTURE_CORPUS)
        bad2.sender = Vector{Union{String,Missing}}(bad2.sender)
        bad2.sender[1] = missing
        @test_throws ArgumentError load_corpus(bad2, cfg)

        # Inverted date bounds
        cfg_bad = CorpusConfig(;
            FIXTURE_CONFIG_ARGS...,
            roles = RoleConfig[],
            corpus_start = DateTime(2002, 1, 1),
            corpus_end   = DateTime(2000, 1, 1),
        )
        @test_throws ArgumentError load_corpus(FIXTURE_CORPUS, cfg_bad)
    end

    include("../src/schema/loaders/enron.jl")

    @testset "enron_config" begin
        cfg = enron_config()
        @test cfg.sender == :sender
        @test cfg.hash == :hash
        @test cfg.internal_domain == "enron.com"
        @test !isempty(cfg.bot_patterns)
        @test !isempty(cfg.roles)
        counsel_types = [r.counsel_type for r in cfg.roles]
        @test InHouse ∈ counsel_types
        @test OutsideFirm ∈ counsel_types
        @test_nowarn load_corpus(FIXTURE_CORPUS, cfg)
    end

    include("../src/network/parse_addrs.jl")

    @testset "extract_addrs" begin
        @test extract_addrs("['a@corp.com', 'b@corp.com']") == ["a@corp.com", "b@corp.com"]
        @test extract_addrs("['a@corp.com']") == ["a@corp.com"]
        @test extract_addrs("[]") == String[]
        @test extract_addrs(missing) == String[]
        @test extract_addrs("") == String[]
        result = extract_addrs("a@corp.com,b@corp.com")
        @test "a@corp.com" ∈ result
    end

    include("../src/network/bots.jl")

    @testset "bot detection" begin
        cfg = enron_config()
        @test is_bot("mailer-daemon@corp.com", cfg)
        @test is_bot("postmaster@corp.com", cfg)
        @test is_bot("arsystem@ect.enron.com", cfg)
        @test is_bot("team.outlook@enron.com", cfg)
        @test !is_bot("alice@corp.com", cfg)
        @test !is_bot("bob@lawfirm.com", cfg)

        senders = ["alice@corp.com", "mailer-daemon@corp.com", "charlie@corp.com"]
        result = identify_bots(senders, cfg)
        @test nrow(result) == 3
        @test result[result.sender .== "mailer-daemon@corp.com", :is_bot][1]
        @test !result[result.sender .== "alice@corp.com", :is_bot][1]
    end

    include("../src/network/edges.jl")

    @testset "build_edges" begin
        cfg = CorpusConfig(; FIXTURE_CONFIG_ARGS...,
            roles = RoleConfig[],
            bot_senders = Set(["eve@corp.com"]),
            internal_domain = "",
        )

        edges = build_edges(FIXTURE_CORPUS, cfg)

        @test !any(edges.sender .== "eve@corp.com")

        one_to_one = filter(r -> r.sender == "alice@corp.com" && r.recipient == "charlie@corp.com", edges)
        @test !isempty(one_to_one)
        @test all(isapprox.(one_to_one.weight, 1/log(3), atol=1e-6))

        @test :sender ∈ propertynames(edges)
        @test :recipient ∈ propertynames(edges)
        @test :date ∈ propertynames(edges)
        @test :weight ∈ propertynames(edges)
        @test :hash ∈ propertynames(edges)
    end

    include("../src/network/community.jl")

    @testset "community detection" begin
        cfg   = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = RoleConfig[])
        edges = build_edges(FIXTURE_CORPUS, cfg)
        nodes = unique(vcat(edges.sender, edges.recipient))
        node_idx = Dict(n => i for (i, n) in enumerate(nodes))
        g = build_snapshot_graph(edges, node_idx, length(nodes))

        @test nv(g) == length(nodes)
        @test ne(g) > 0

        @test jaccard(Set([1,2,3]), Set([2,3,4])) ≈ 0.5
        @test jaccard(Set{Int}(), Set{Int}()) == 1.0

        python_ok = try; pyimport("leidenalg"); true; catch; false; end
        if python_ok
            result = leiden_communities(g, nodes)
            @test :node ∈ propertynames(result)
            @test :community_id ∈ propertynames(result)
            @test nrow(result) == length(nodes)
        else
            @test_skip "leidenalg not available"
        end
    end

    include("../src/network/history.jl")

    @testset "build_node_history" begin
        cfg     = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = RoleConfig[])
        edges   = build_edges(FIXTURE_CORPUS, cfg)
        history = build_node_history(edges, cfg)

        @test :node ∈ propertynames(history)
        @test :week_start ∈ propertynames(history)
        @test :message_count ∈ propertynames(history)
        @test :recipient_count ∈ propertynames(history)
        @test :entropy ∈ propertynames(history)

        @test nrow(history) > 0
        @test all(history.week_start .>= Date(cfg.corpus_start))
        @test all(history.week_start .<= Date(cfg.corpus_end))
    end

    include("../src/discovery/roles.jl")

    @testset "find_roles" begin
        cfg_net = CorpusConfig(;
            FIXTURE_CONFIG_ARGS...,
            roles = RoleConfig[],
            bot_senders = Set(["eve@corp.com"]),
        )
        edges = build_edges(FIXTURE_CORPUS, cfg_net)
        nodes = unique(vcat(edges.sender, edges.recipient))
        node_reg = DataFrame(node = nodes)

        cfg = enron_config()
        # Override explicit addresses to match fixture nodes
        in_house_role = RoleConfig("in_house_counsel", InHouse,
            Regex[], String[], Set(["alice@corp.com"]))
        outside_role  = RoleConfig("outside_counsel", OutsideFirm,
            [r".*@lawfirm\.com"], String[], Set{String}())
        cfg_roles = CorpusConfig(; FIXTURE_CONFIG_ARGS...,
            roles = [in_house_role, outside_role])

        result = find_roles(node_reg, cfg_roles)
        @test :roles ∈ propertynames(result)
        @test :is_counsel ∈ propertynames(result)

        bob_row = filter(r -> r.node == "bob@lawfirm.com", result)
        @test !isempty(bob_row)
        @test "outside_counsel" ∈ bob_row[1, :roles]

        charlie_row = filter(r -> r.node == "charlie@corp.com", result)
        @test !isempty(charlie_row)
        @test isempty(charlie_row[1, :roles])

        alice_row = filter(r -> r.node == "alice@corp.com", result)
        @test !isempty(alice_row)
        @test alice_row[1, :is_counsel]
    end

    include("../src/discovery/clusters.jl")

    @testset "DiscoverySession" begin
        cfg   = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = RoleConfig[])
        edges = build_edges(FIXTURE_CORPUS, cfg)
        nodes = unique(vcat(edges.sender, edges.recipient))
        result = DataFrame(node = nodes, community_id = Int32.(ones(length(nodes))))

        S = DiscoverySession(FIXTURE_CORPUS, result, edges, cfg)
        @test S.cfg === cfg
        @test nrow(S.corpus_df) == 30
        @test nrow(S.result) == length(nodes)
    end
end
