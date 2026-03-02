# src/schema/config.jl
using DataFrames, Dates

@enum CounselType NotCounsel InHouse OutsideFirm

struct RoleConfig
    label::String
    counsel_type::CounselType
    address_patterns::Vector{Regex}
    domain_list::Vector{String}
    explicit_addresses::Set{String}
end
