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
    rows = []

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
            subj = "FERC inquiry advice $i",
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
            subj = "Re: FERC inquiry advice $(i-5)",
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

    DataFrame(rows)
end

const FIXTURE_CORPUS = make_fixture_corpus()
