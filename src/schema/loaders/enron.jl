# src/schema/loaders/enron.jl
using Dates, DataFrames

function enron_config()::CorpusConfig
    in_house = RoleConfig(
        "in_house_counsel",
        InHouse,
        Regex[],
        String[],
        Set([
            "sara.shackleton@enron.com",
            "tana.jones@enron.com",
            "gerald.nemec@enron.com",
            "mark.haedicke@enron.com",
            "richard.sanders@enron.com",
            "christian.yoder@enron.com",
            "stinson.gibner@enron.com",
            "janette.elbertson@enron.com",
        ]),
    )

    outside_counsel = RoleConfig(
        "outside_counsel",
        OutsideFirm,
        [r".*@vinson-elkins\.com", r".*@bracepatt\.com", r".*@andrewskurth\.com"],
        ["vinson-elkins.com", "bracepatt.com", "andrewskurth.com",
         "milbank.com", "akin-gump.com"],
        Set{String}(),
    )

    CorpusConfig(
        sender         = :sender,
        recipients_to  = :tos,
        recipients_cc  = :ccs,
        timestamp      = :date,
        subject        = :subj,
        hash           = :hash,
        lastword       = :lastword,
        internal_domain = "enron.com",
        corpus_start   = DateTime(1999, 1,  1),
        corpus_end     = DateTime(2002, 12, 31),
        baseline_start = DateTime(2000, 7,  1),
        baseline_end   = DateTime(2000, 9,  30),
        bot_patterns   = [
            r"^mailer-daemon@", r"^postmaster@", r"^no\.address@",
            r"^noreply@", r"^no-reply@", r"^bounce", r"^arsystem@",
            r"^enron-admin@", r"^listserv@", r"@listserv\.",
            r"^enron\.announcement", r"^ect\.announcement",
            r"^general\.announcement", r"^gpg\.announcement",
            r"^the\.buzz@", r"^office\.chairman@", r"^ect\.chairman@",
            r"^enron\.chairman@", r"^team\.", r"^legal\.[0-9]",
        ],
        bot_senders    = Set([
            "arsystem@ect.enron.com", "arsystem@mailman.enron.com",
            "ect.announcement@enron.com", "ect.chairman@enron.com",
            "enron.announcement@enron.com", "general.announcement@enron.com",
            "gpg.announcement@enron.com", "gpg.center@enron.com",
            "the.buzz@enron.com", "survey.test@enron.com",
            "mailer-daemon@ect.enron.com", "postmaster@enron.com",
        ]),
        roles          = [in_house, outside_counsel],
    )
end

function enron_corpus()::DataFrame
    error("enron_corpus(): Artifacts.toml not yet configured. See implementation plan Task 20.")
end
