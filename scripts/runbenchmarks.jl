using Pkg
Pkg.activate(".")

using BenchmarkTools, JSON3, Dates, Statistics, Trixi

include("../src/benchmarks.jl")


tune!(SUITE)
results = run(SUITE, verbose=true)

all_times = Float64[]
all_memory = 0
all_allocs = 0

for (name, group) in results
    for (subname, trial) in group
        append!(all_times, trial.times)
        global all_memory += trial.memory
        global all_allocs += trial.allocs
    end
end

times_ms = all_times ./ 1e6
memory_mb = all_memory / (1024^2)

timestamp = now()
commit = try
    strip(read(`git rev-parse HEAD`, String))[1:8]
catch
    "unknown"
end

entry = Dict(
    "timestamp" => string(timestamp),
    "commit" => commit,
    "median_time" => median(times_ms),
    "mean_time" => mean(times_ms),
    "memory_mb" => memory_mb,
    "allocs" => all_allocs,
    "samples" => length(times_ms)
)

history_file = "../data/history.json"
mkpath("../data")

history = if isfile(history_file)
    content = read(history_file, String)
    isempty(strip(content)) ? Dict{String,Any}[] : JSON3.read(content, Vector{Dict{String,Any}})
else
    Dict{String,Any}[]
end

push!(history, entry)

open(history_file, "w") do f
    JSON3.pretty(f, history)
end

println("Saved to: $history_file")
