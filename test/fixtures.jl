# test/fixtures.jl
# Synthetic 30-message corpus for tests — no external dependencies

using DataFrames, Dates

const FIXTURE_CONFIG_ARGS = (
    sender        = :sender,
    recipients_to = :tos,
    recipients_cc = :ccs,
    timestamp     = :date,
    subject       = :subj,
    hash          = :hash,
    lastword      = :lastword,
    corpus_start  = DateTime(2000, 1, 1),
    corpus_end    = DateTime(2000, 12, 31),
    baseline_start = DateTime(2000, 7, 1),
    baseline_end   = DateTime(2000, 9, 30),
)

function make_fixture_corpus()
    t0 = DateTime(2000, 7, 1)
    rows = NamedTuple{(:hash,:sender,:tos,:ccs,:date,:subj,:lastword),
                      Tuple{String,String,String,String,DateTime,String,Bool}}[]

    # 5 alice→charlie operational (no counsel in recipients)
    for i in 1:5
        push!(rows, (
            hash = lpad(string(i), 32, "0"),
            sender = "alice@corp.com",
            tos = "['charlie@corp.com']",
            ccs = "[]",
            date = t0 + Day(i),
            subj = "Ops update $i",
            lastword = i == 5,
        ))
    end

    # 5 alice→bob (in-house to outside counsel)
    for i in 6:10
        push!(rows, (
            hash = lpad(string(i), 32, "0"),
            sender = "alice@corp.com",
            tos = "['bob@lawfirm.com']",
            ccs = "[]",
            date = t0 + Day(i),
            subj = "subpoena inquiry advice $i",
            lastword = i == 10,
        ))
    end

    # 5 bob→alice (outside counsel response)
    for i in 11:15
        push!(rows, (
            hash = lpad(string(i), 32, "0"),
            sender = "bob@lawfirm.com",
            tos = "['alice@corp.com']",
            ccs = "[]",
            date = t0 + Day(i),
            subj = "Re: subpoena inquiry advice $(i-5)",
            lastword = i == 15,
        ))
    end

    # 5 charlie→diana compliance (no counsel)
    for i in 16:20
        push!(rows, (
            hash = lpad(string(i), 32, "0"),
            sender = "charlie@corp.com",
            tos = "['diana@corp.com']",
            ccs = "[]",
            date = t0 + Day(i),
            subj = "Trade report $i",
            lastword = i == 20,
        ))
    end

    # 5 eve broadcasts (bot sender)
    for i in 21:25
        push!(rows, (
            hash = lpad(string(i), 32, "0"),
            sender = "eve@corp.com",
            tos = "['alice@corp.com', 'bob@lawfirm.com', 'charlie@corp.com', 'diana@corp.com', 'frank@corp.com']",
            ccs = "[]",
            date = t0 + Day(i),
            subj = "Company announcement $i",
            lastword = false,
        ))
    end

    # 5 charlie→frank operational (no counsel)
    for i in 26:30
        push!(rows, (
            hash = lpad(string(i), 32, "0"),
            sender = "charlie@corp.com",
            tos = "['frank@corp.com']",
            ccs = "[]",
            date = t0 + Day(i),
            subj = "Scheduling $i",
            lastword = i == 30,
        ))
    end

    # 2 audit_counsel_coverage fixtures:
    #   row 31: charlie→frank, attorney keyword, no counsel party → should surface
    #   row 32: dave→5 non-counsel (broadcast), attorney keyword  → should surface as broadcast
    push!(rows, (
        hash = lpad("31", 32, "0"),
        sender = "charlie@corp.com",
        tos = "['frank@corp.com']",
        ccs = "[]",
        date = t0 + Day(31),
        subj = "privileged communication re: pipeline",
        lastword = false,
    ))
    push!(rows, (
        hash = lpad("32", 32, "0"),
        sender = "dave@corp.com",
        tos = "['charlie@corp.com', 'frank@corp.com', 'diana@corp.com', 'gary@corp.com', 'helen@corp.com']",
        ccs = "[]",
        date = t0 + Day(32),
        subj = "attorney review required",
        lastword = false,
    ))

    DataFrame(rows)
end

const FIXTURE_CORPUS = make_fixture_corpus()
