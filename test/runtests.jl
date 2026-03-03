using Test
using Arrow
using DataFrames, Dates
using Graphs
using PythonCall
using XLSX
using DiscoveryGraph

include("fixtures.jl")

@testset "DiscoveryGraph" begin
    @test nrow(FIXTURE_CORPUS) == 32

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

    @testset "load_corpus" begin
        cfg = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = RoleConfig[])

        df = load_corpus(FIXTURE_CORPUS, cfg)
        @test nrow(df) == 32

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

    @testset "extract_addrs" begin
        @test extract_addrs("['a@corp.com', 'b@corp.com']") == ["a@corp.com", "b@corp.com"]
        @test extract_addrs("['a@corp.com']") == ["a@corp.com"]
        @test extract_addrs("[]") == String[]
        @test extract_addrs(missing) == String[]
        @test extract_addrs("") == String[]
        result = extract_addrs("a@corp.com,b@corp.com")
        @test "a@corp.com" ∈ result
    end

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

    @testset "find_roles" begin
        cfg_net = CorpusConfig(;
            FIXTURE_CONFIG_ARGS...,
            roles = RoleConfig[],
            bot_senders = Set(["eve@corp.com"]),
        )
        edges = build_edges(FIXTURE_CORPUS, cfg_net)
        nodes = unique(vcat(edges.sender, edges.recipient))
        node_reg = DataFrame(node = nodes)

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

    @testset "identify_counsel_communities" begin
        in_house_role = RoleConfig("in_house_counsel", InHouse,
            Regex[], String[], Set(["alice@corp.com"]))
        outside_role  = RoleConfig("outside_counsel", OutsideFirm,
            [r".*@lawfirm\.com"], String[], Set{String}())
        cfg_roles = CorpusConfig(; FIXTURE_CONFIG_ARGS...,
            roles = [in_house_role, outside_role])

        # alice (InHouse) and bob (OutsideFirm) in community 1;
        # charlie and dave (neither) in community 2
        result = DataFrame(
            node         = ["alice@corp.com", "bob@lawfirm.com", "charlie@corp.com", "dave@corp.com"],
            community_id = Int32[1, 1, 2, 2],
        )

        summary = identify_counsel_communities(result, cfg_roles)

        @test nrow(summary) == 1
        @test summary[1, :community_id] == 1
        @test summary[1, :n_members]    == 2
        @test summary[1, :n_counsel]    == 2
        @test "in_house_counsel" ∈ summary[1, :roles]
        @test "outside_counsel"  ∈ summary[1, :roles]
        @test "alice@corp.com"   ∈ summary[1, :counsel_nodes]

        # No counsel nodes → empty DataFrame with correct schema
        cfg_no_roles = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = RoleConfig[])
        empty_summary = identify_counsel_communities(result, cfg_no_roles)
        @test nrow(empty_summary) == 0
        @test :community_id ∈ propertynames(empty_summary)
    end

    @testset "audit_counsel_coverage" begin
        in_house_role = RoleConfig("in_house_counsel", InHouse,
            Regex[], String[], Set(["alice@corp.com"]))
        outside_role  = RoleConfig("outside_counsel", OutsideFirm,
            [r".*@lawfirm\.com"], String[], Set{String}())
        cfg_audit = CorpusConfig(; FIXTURE_CONFIG_ARGS...,
            roles       = [in_house_role, outside_role],
            bot_senders = Set(["eve@corp.com"]),
        )
        all_nodes = unique(vcat(
            FIXTURE_CORPUS.sender,
            reduce(vcat, extract_addrs.(FIXTURE_CORPUS.tos)),
        ))
        node_reg = find_roles(DataFrame(node=all_nodes), cfg_audit)

        result = audit_counsel_coverage(FIXTURE_CORPUS, node_reg, cfg_audit)

        @test :suspicious_senders ∈ keys(result)
        @test :uncovered_count    ∈ keys(result)
        @test :keywords_used      ∈ keys(result)

        ss = result.suspicious_senders
        @test ss isa DataFrame
        for col in [:sender, :n_messages, :n_broadcast, :broadcast_fraction, :sample_subjects]
            @test col ∈ propertynames(ss)
        end

        # alice (in_house) and bob (outside_counsel) must NOT appear
        @test !("alice@corp.com"   ∈ ss.sender)
        @test !("bob@lawfirm.com"  ∈ ss.sender)
        # eve is a bot sender — must NOT appear
        @test !("eve@corp.com"     ∈ ss.sender)

        # charlie sent one attorney-flavored message (row 31, non-broadcast)
        charlie = filter(r -> r.sender == "charlie@corp.com", ss)
        @test nrow(charlie) == 1
        @test charlie[1, :n_broadcast] == 0

        # dave sent one attorney-flavored broadcast (row 32, 5 recipients)
        dave = filter(r -> r.sender == "dave@corp.com", ss)
        @test nrow(dave) == 1
        @test dave[1, :n_broadcast] == 1
        @test dave[1, :broadcast_fraction] ≈ 1.0

        @test result.uncovered_count == 2

        # Missing column guard
        bad_reg = select(node_reg, Not(:is_counsel))
        @test_throws ErrorException audit_counsel_coverage(FIXTURE_CORPUS, bad_reg, cfg_audit)
    end

    @testset "DiscoverySession" begin
        cfg   = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = RoleConfig[])
        edges = build_edges(FIXTURE_CORPUS, cfg)
        nodes = unique(vcat(edges.sender, edges.recipient))
        result = DataFrame(node = nodes, community_id = Int32.(ones(length(nodes))))

        S = DiscoverySession(FIXTURE_CORPUS, result, edges, cfg)
        @test S.cfg === cfg
        @test nrow(S.corpus_df) == 32
        @test nrow(S.result) == length(nodes)
    end

    @testset "generate_outputs" begin
        outside_role = RoleConfig("outside_counsel", OutsideFirm,
            [r".*@lawfirm\.com"], String[], Set{String}())
        cfg = CorpusConfig(;
            FIXTURE_CONFIG_ARGS...,
            roles = [outside_role],
            bot_senders = Set(["eve@corp.com"]),
        )

        edges  = build_edges(FIXTURE_CORPUS, cfg)
        nodes  = unique(vcat(edges.sender, edges.recipient))
        result = DataFrame(node=nodes, community_id=Int32.(ones(length(nodes))),
                           is_kernel=trues(length(nodes)))
        node_reg = find_roles(result, cfg)

        S = DiscoverySession(FIXTURE_CORPUS, result, edges, cfg)
        outputs = generate_outputs(S, node_reg)

        @test :community_table ∈ keys(outputs)
        @test :review_queue    ∈ keys(outputs)
        @test :tier1           ∈ keys(outputs)
        @test :tier2           ∈ keys(outputs)
        @test :tier3           ∈ keys(outputs)
        @test :tier4           ∈ keys(outputs)
        @test :anomaly_list    ∈ keys(outputs)

        @test nrow(outputs.review_queue) > 0
        @test all(t != Tier5 for t in outputs.review_queue.tier)

        # Per-tier frames are filtered subsets of review_queue
        @test nrow(outputs.tier1) + nrow(outputs.tier2) +
              nrow(outputs.tier3) + nrow(outputs.tier4) == nrow(outputs.review_queue)
        # Keyword classifier: "subpoena inquiry advice" → subpoena → tier1;
        # "Ops update" → no signal → tier4
        @test nrow(outputs.tier1) > 0
        @test all(r.tier == Tier1 for r in eachrow(outputs.tier1))
        @test all(r.tier == Tier4 for r in eachrow(outputs.tier4))

        for col in [:hash, :date, :sender, :recipients, :subject, :roles_implicated, :tier, :basis]
            @test col ∈ propertynames(outputs.review_queue)
        end
    end

    @testset "detect_anomalies" begin
        cfg     = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = RoleConfig[])
        edges   = build_edges(FIXTURE_CORPUS, cfg)
        history = build_node_history(edges, cfg)

        anomalies = detect_anomalies(history, cfg)

        @test :node         ∈ propertynames(anomalies)
        @test :week_start   ∈ propertynames(anomalies)
        @test :anomaly_type ∈ propertynames(anomalies)
        @test :z_score      ∈ propertynames(anomalies)
        @test :basis        ∈ propertynames(anomalies)
        @test anomalies isa DataFrame
    end

    @testset "build_community_vocabulary stub" begin
        cfg    = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = RoleConfig[])
        edges  = build_edges(FIXTURE_CORPUS, cfg)
        nodes  = unique(vcat(edges.sender, edges.recipient))
        result = DataFrame(node=nodes, community_id=Int32.(ones(length(nodes))))

        vocab = build_community_vocabulary(FIXTURE_CORPUS, result, cfg)
        @test vocab isa Dict
        @test all(isempty(v) for v in values(vocab))
    end

    @testset "build_corpus_config" begin
        cfg = build_corpus_config(
            internal_domain      = "corp.com",
            corpus_start         = Date(2000, 1, 1),
            corpus_end           = Date(2000, 12, 31),
            baseline_start       = Date(2000, 7, 1),
            baseline_end         = Date(2000, 9, 30),
            in_house_attorneys   = ["alice@corp.com"],
            outside_firm_domains = ["lawfirm.com"],
            hotbutton_keywords   = ["raptors", "ljm"],
        )
        @test cfg.internal_domain == "corp.com"
        @test cfg.hotbutton_keywords == ["raptors", "ljm"]
        @test length(cfg.roles) == 2
        @test any(r.counsel_type == InHouse    for r in cfg.roles)
        @test any(r.counsel_type == OutsideFirm for r in cfg.roles)
        ih = filter(r -> r.counsel_type == InHouse, cfg.roles)[1]
        @test "alice@corp.com" ∈ ih.explicit_addresses
        oc = filter(r -> r.counsel_type == OutsideFirm, cfg.roles)[1]
        @test "lawfirm.com" ∈ oc.domain_list
        @test cfg.tier1_keywords == DEFAULT_TIER1_KEYWORDS
    end

    @testset "xlsx config round-trip" begin
        tmp = tempname() * ".xlsx"
        try
            # write_config_template produces a valid workbook
            path = write_config_template(tmp)
            @test isfile(path)

            # config_from_xlsx reads a hand-completed workbook correctly
            XLSX.openxlsx(tmp, mode="rw") do xf
                meta = xf["Metadata"]
                meta["B2"] = "corp.com"          # internal_domain
                meta["B3"] = "2000-01-01"        # corpus_start
                meta["B4"] = "2000-12-31"        # corpus_end
                meta["B5"] = "2000-07-01"        # baseline_start
                meta["B6"] = "2000-09-30"        # baseline_end
                meta["B7"] = "test-v1"           # schema_version

                atty = xf["InHouseAttorneys"]
                atty["A2"] = "alice@corp.com"

                firms = xf["OutsideFirmDomains"]
                firms["A2"] = "lawfirm.com"

                kws = xf["HotbuttonKeywords"]
                kws["A2"] = "raptors"
                kws["A3"] = "# this is a comment and should be ignored"
                kws["A4"] = "ljm"
            end

            cfg = config_from_xlsx(tmp)
            @test cfg.internal_domain == "corp.com"
            @test Date(cfg.corpus_start) == Date(2000, 1, 1)
            @test Date(cfg.corpus_end)   == Date(2000, 12, 31)
            @test cfg.schema_version     == "test-v1"
            @test cfg.hotbutton_keywords == ["raptors", "ljm"]
            ih = filter(r -> r.counsel_type == InHouse, cfg.roles)[1]
            @test "alice@corp.com" ∈ ih.explicit_addresses
            oc = filter(r -> r.counsel_type == OutsideFirm, cfg.roles)[1]
            @test "lawfirm.com" ∈ oc.domain_list
        finally
            isfile(tmp) && rm(tmp)
        end
    end

    @testset "keyword tier classification" begin
        cfg_kw = CorpusConfig(; FIXTURE_CONFIG_ARGS...,
            roles              = RoleConfig[],
            hotbutton_keywords = ["raptors"],
            tier1_keywords     = ["ferc"],
            tier2_keywords     = ["advice"],
            tier3_keywords     = ["contract"],
        )
        @test DiscoveryGraph._classify_tier("raptors meeting", "", cfg_kw) == (Tier1, "hotbutton: raptors")
        @test DiscoveryGraph._classify_tier("ferc inquiry",    "", cfg_kw) == (Tier1, "tier1 keyword: ferc")
        @test DiscoveryGraph._classify_tier("advice needed",   "", cfg_kw) == (Tier2, "tier2 keyword: advice")
        @test DiscoveryGraph._classify_tier("contract review", "", cfg_kw) == (Tier3, "tier3 keyword: contract")
        @test DiscoveryGraph._classify_tier("ops update",      "", cfg_kw)[1] == Tier4
        # body text also checked
        @test DiscoveryGraph._classify_tier("re: meeting", "ferc subpoena enclosed", cfg_kw)[1] == Tier1
        # hotbutton in body
        @test DiscoveryGraph._classify_tier("weekly update", "raptors unwinding", cfg_kw) == (Tier1, "hotbutton: raptors")
    end

    @testset "hotbutton keyword coverage" begin
        # cfg with all ENRON_HOTBUTTON_EXAMPLES and a tier2 keyword so we can test precedence
        cfg_hb = CorpusConfig(; FIXTURE_CONFIG_ARGS...,
            roles              = RoleConfig[],
            hotbutton_keywords = ENRON_HOTBUTTON_EXAMPLES,
            tier1_keywords     = ["ferc"],
            tier2_keywords     = ["advice"],
            tier3_keywords     = ["contract"],
        )

        # Every hotbutton term triggers Tier1 when present in subject
        for kw in ENRON_HOTBUTTON_EXAMPLES
            @test DiscoveryGraph._classify_tier(kw, "", cfg_hb) == (Tier1, "hotbutton: $kw")
        end

        # Every hotbutton term triggers Tier1 when present in body (neutral subject)
        for kw in ENRON_HOTBUTTON_EXAMPLES
            @test DiscoveryGraph._classify_tier("weekly update", kw, cfg_hb) == (Tier1, "hotbutton: $kw")
        end

        # Case-insensitive: generate_outputs lowercases subject/body before calling
        # _classify_tier; simulate that path by passing lowercase(uppercase(kw)).
        for kw in ENRON_HOTBUTTON_EXAMPLES
            @test DiscoveryGraph._classify_tier(lowercase("Re: $(uppercase(kw)) Project"), "", cfg_hb) == (Tier1, "hotbutton: $kw")
        end
        for kw in ENRON_HOTBUTTON_EXAMPLES
            @test DiscoveryGraph._classify_tier("weekly update", lowercase("$(uppercase(kw)) details"), cfg_hb) == (Tier1, "hotbutton: $kw")
        end

        # Hotbutton in body beats tier2 keyword in subject
        @test DiscoveryGraph._classify_tier("advice needed", "ljm transaction", cfg_hb) == (Tier1, "hotbutton: ljm")

        # Hotbutton in body beats tier3 keyword in subject
        @test DiscoveryGraph._classify_tier("contract review", "prepay structure", cfg_hb) == (Tier1, "hotbutton: prepay")

        # Hotbutton in subject beats tier1 keyword in body
        @test DiscoveryGraph._classify_tier("jedi project update", "ferc filing", cfg_hb) == (Tier1, "hotbutton: jedi")
    end

    @testset "write_outputs" begin
        outside_role = RoleConfig("outside_counsel", OutsideFirm,
            [r".*@lawfirm\.com"], String[], Set{String}())
        cfg = CorpusConfig(; FIXTURE_CONFIG_ARGS...,
            roles = [outside_role], bot_senders = Set(["eve@corp.com"]))
        edges    = build_edges(FIXTURE_CORPUS, cfg)
        nodes    = unique(vcat(edges.sender, edges.recipient))
        result   = DataFrame(node=nodes, community_id=Int32.(ones(length(nodes))),
                             is_kernel=trues(length(nodes)))
        node_reg = find_roles(result, cfg)
        S        = DiscoverySession(FIXTURE_CORPUS, result, edges, cfg)
        outputs  = generate_outputs(S, node_reg)

        dir = mktempdir()
        paths = write_outputs(S, outputs, dir)

        @test isfile(paths.tier1)
        @test isfile(paths.tier2)
        @test isfile(paths.tier3)
        @test isfile(paths.tier4)
        @test isfile(paths.review_queue)
        @test isfile(paths.memo)

        # Arrow files are readable
        t1 = Arrow.Table(paths.tier1) |> DataFrame
        @test t1 isa DataFrame
        rq = Arrow.Table(paths.review_queue) |> DataFrame
        @test nrow(rq) == nrow(outputs.review_queue)

        # Memo file contains expected content
        memo_text = read(paths.memo, String)
        @test occursin("Rule 26(f)", memo_text)

        # overwrite guard
        @test_throws ErrorException write_outputs(S, outputs, dir)
        @test_nowarn write_outputs(S, outputs, dir; overwrite = true)
    end

    @testset "generate_rule26f_memo" begin
        outside_role = RoleConfig("outside_counsel", OutsideFirm,
            [r".*@lawfirm\.com"], String[], Set{String}())
        cfg   = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = [outside_role])
        edges = build_edges(FIXTURE_CORPUS, cfg)
        nodes = unique(vcat(edges.sender, edges.recipient))
        result   = DataFrame(node=nodes, community_id=Int32.(ones(length(nodes))),
                             is_kernel=trues(length(nodes)))
        node_reg = find_roles(result, cfg)
        S        = DiscoverySession(FIXTURE_CORPUS, result, edges, cfg)
        outputs  = generate_outputs(S, node_reg)

        memo = generate_rule26f_memo(S, outputs)
        @test memo isa String
        @test !isempty(memo)
        @test occursin("Rule 26(f)", memo)
        @test occursin("DiscoveryGraph", memo)
        @test occursin("Count", memo)
        @test occursin("| Tier 4 |", memo)
    end
end
