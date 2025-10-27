using Pkg
Pkg.activate(".")

using BenchmarkTools, JSON3, Dates, Statistics, UUIDs, Trixi

include("../src/benchmarks.jl")

tune!(SUITE)
results = run(SUITE, verbose=true)

all_times = Float64[]
all_memory = 0
all_allocs = 0
all_gc_times = Float64[]

for (name, group) in results
    for (subname, trial) in group
        append!(all_times, trial.times)
        append!(all_gc_times, trial.gctimes)
        global all_memory += trial.memory
        global all_allocs += trial.allocs
    end
end

times_ms = all_times ./ 1e6
gc_times_ms = all_gc_times ./ 1e6
memory_mb = all_memory / (1024^2)

commit = try
    strip(read(`git rev-parse HEAD`, String))
catch
    "unknown"
end

commit_short = length(commit) >= 7 ? commit[1:7] : commit

branch = try
    strip(read(`git branch --show-current`, String))
catch
    "unknown"
end

commit_msg = try
    first_line = strip(read(`git log -1 --pretty=%B`, String))
    first(split(first_line, '\n'))
catch
    ""
end

author = try
    strip(read(`git log -1 --pretty=%ae`, String))
catch
    ""
end

entry = Dict(
    "timestamp" => Dates.format(now(UTC), "yyyy-mm-ddTHH:MM:SS.sss") * "Z",
    "commit" => commit,
    "commit_short" => commit_short,
    "branch" => branch,
    "commit_message" => commit_msg,
    "author" => author,
    "benchmark_id" => string(uuid4()),
    "benchmark_name" => "trixi_suite",
    "environment" => Dict(
        "julia_version" => string(VERSION),
        "os" => string(Sys.KERNEL),
        "os_version" => string(Sys.KERNEL, " ", Sys.MACHINE),
        "cpu" => Sys.cpu_info()[1].model,
        "cpu_cores" => Sys.CPU_THREADS,
        "ram_total_gb" => round(Sys.total_memory() / 1e9, digits=2),
        "hostname" => gethostname()
    ),
    "time" => Dict(
        "median_ms" => median(times_ms),
        "mean_ms" => mean(times_ms),
        "min_ms" => minimum(times_ms),
        "max_ms" => maximum(times_ms),
        "std_dev_ms" => std(times_ms),
        "samples" => length(times_ms),
        "percentile_95_ms" => quantile(times_ms, 0.95),
        "percentile_99_ms" => quantile(times_ms, 0.99),
        "total_time_ms" => sum(times_ms)
    ),
    "memory" => Dict(
        "allocated_mb" => memory_mb,
        "peak_mb" => memory_mb,
        "gc_time_ms" => sum(gc_times_ms),
        "gc_count" => count(>(0), gc_times_ms),
        "allocations" => all_allocs,
        "bytes_allocated" => all_memory
    ),
    "compilation" => Dict(
        "compile_time_ms" => 0.0,
        "recompile_time_ms" => 0.0,
        "inference_time_ms" => 0.0
    ),
    "results" => Dict(
        "passed" => true,
        "error" => nothing,
        "output_size_bytes" => 0,
        "checksum" => ""
    ),
    "throughput" => Dict(
        "operations_per_sec" => 1000.0 / median(times_ms),
        "items_processed" => 0,
        "mb_per_sec" => 0.0
    ),
    "comparison" => Dict(
        "baseline_commit" => nothing,
        "time_regression_percent" => 0.0,
        "memory_regression_percent" => 0.0
    ),
    "custom_metrics" => Dict{String, Any}(),
    "raw_samples" => Dict(
        "times_ms" => Vector{Float64}(times_ms),
        "gc_times_ms" => Vector{Float64}(gc_times_ms),
        "memory_samples_mb" => fill(memory_mb, length(times_ms)),
        "allocations_per_sample" => fill(all_allocs, length(times_ms))
    ),
    "median_time" => median(times_ms),
    "memory_mb" => memory_mb
)

history_file = "../data/history.json"
mkpath("../data")

history = if isfile(history_file)
    content = read(history_file, String)
    if isempty(strip(content))
        Dict{String, Any}[]
    else
        try
            json_data = JSON3.read(content)
            [Dict{String, Any}(item) for item in json_data]
        catch
            Dict{String, Any}[]
        end
    end
else
    Dict{String, Any}[]
end

push!(history, entry)

open(history_file, "w") do f
    JSON3.pretty(f, history)
end

println("\nDashboard: http://localhost:8089")
