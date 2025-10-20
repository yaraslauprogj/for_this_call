
using Pkg
Pkg.activate("..")

using Bonito, VegaLite, JSON3, DataFrames, Dates

history = if isfile("../data/history.json")
    json_str = read("../data/history.json", String)
    if isempty(strip(json_str))
        []
    else
        JSON3.read(json_str)
    end
else
    []
end

app = App() do session::Session
    if isempty(history)
        return DOM.div([
            DOM.h1("Trixi Benchmarks"),
            DOM.p("No data. Run: julia scripts/runbenchmarks.jl")
        ])
    end
    
    times = Float64[]
    memories = Float64[]
    timestamps = String[]
    commits = String[]
    
    for h in history
        push!(times, get(h, "median_time", 0.0))
        push!(memories, get(h, "memory_mb", 0.0))
        push!(timestamps, get(h, "timestamp", ""))
        push!(commits, get(h, "commit", ""))
    end
    
    df = DataFrame(
        run = 1:length(history),
        time = times,
        memory = memories,
        timestamp = timestamps,
        commit = commits
    )
    
    time_chart = df |> @vlplot(
        width = 900,
        height = 400,
        title = "Performance Over Time",
        mark = {:line, point = true, tooltip = true},
        x = {
            :commit,
            title = "Commit Hash",
            axis = {
                labelAngle = -45,
                labelLimit = 100
            }
        },
        y = {
            :time,
            title = "Median Time (ms)",
            axis = {grid = true}
        },
        tooltip = [
            {field = :time, title = "Time (ms)", format = ".3f"},
            {field = :memory, title = "Memory (MB)", format = ".2f"},
            {field = :commit, title = "Commit"},
            {field = :timestamp, title = "Date"}
        ]
    )
    
    memory_chart = df |> @vlplot(
        width = 900,
        height = 300,
        title = "Memory Usage",
        mark = {:area, opacity = 0.7, color = "#ff6b6b", line = true},
        x = {
            :commit,
            title = "Commit Hash",
            axis = {
                labelAngle = -45,
                labelLimit = 100
            }
        },
        y = {:memory, title = "Memory (MB)"}
    )
    
    latest = history[end]
    median_time = get(latest, "median_time", 0.0)
    memory_mb = get(latest, "memory_mb", 0.0)
    commit = get(latest, "commit", "unknown")
    timestamp = get(latest, "timestamp", "unknown")
    
    avg_time = sum(times) / length(times)
    min_time = minimum(times)
    max_time = maximum(times)
    
    change_info = if length(history) > 1
        prev = history[end-1]
        prev_time = get(prev, "median_time", 0.0)
        change = median_time - prev_time
        change_pct = prev_time > 0 ? (change / prev_time * 100) : 0
        
        color = change > 0 ? "#e74c3c" : "#27ae60"
        symbol = change > 0 ? "↑" : "↓"
        
        DOM.div([
            DOM.span("Change from previous: ", style="font-weight:bold;"),
            DOM.span("$(symbol) $(abs(round(change_pct, digits=1)))%", 
                    style="color:$(color); font-weight:bold;")
        ], style="margin:5px 0;")
    else
        DOM.div("")
    end
    
    stats = DOM.div([
        DOM.h3("Summary", style="margin-top:0; color:#333;"),
        DOM.div([
            DOM.div([
                DOM.span("Latest Time: ", style="font-weight:bold;"),
                DOM.span("$(round(median_time, digits=2)) ms")
            ], style="margin:5px 0;"),
            change_info,
            DOM.div([
                DOM.span("Average Time: ", style="font-weight:bold;"),
                DOM.span("$(round(avg_time, digits=2)) ms")
            ], style="margin:5px 0;"),
            DOM.div([
                DOM.span("Best Time: ", style="font-weight:bold;"),
                DOM.span("$(round(min_time, digits=2)) ms", style="color:#27ae60;")
            ], style="margin:5px 0;"),
            DOM.div([
                DOM.span("Worst Time: ", style="font-weight:bold;"),
                DOM.span("$(round(max_time, digits=2)) ms", style="color:#e74c3c;")
            ], style="margin:5px 0;"),
            DOM.div([
                DOM.span("Memory: ", style="font-weight:bold;"),
                DOM.span("$(round(memory_mb, digits=2)) MB")
            ], style="margin:5px 0;"),
            DOM.div([
                DOM.span("Latest Commit: ", style="font-weight:bold;"),
                DOM.code(commit, style="background:#f4f4f4; padding:2px 5px; border-radius:3px;")
            ], style="margin:5px 0;"),
            DOM.div([
                DOM.span("Total Runs: ", style="font-weight:bold;"),
                DOM.span("$(length(history))")
            ], style="margin:5px 0;")
        ])
    ], style="background:#f8f9fa; padding:25px; margin:20px 0; border-radius:10px; box-shadow: 0 10px 20px rgba(0,0,0,0.1);")
    
    DOM.div([
        DOM.h1("Trixi Performance Tracker",
               style="text-align:center; color:#2c3e50; margin-bottom:30px;"),
        
        stats,
        
        DOM.div([
            DOM.h2("Performance Timeline", style="color:#333; margin-bottom:10px;"),
            DOM.div(time_chart)
        ], style="margin:30px 0; padding:20px; background:#fff; border-radius:10px; box-shadow: 0 2px 10px rgba(0,0,0,0.05);"),
        
        DOM.div([
            DOM.h2("Memory Usage", style="color:#333; margin-bottom:10px;"),
            DOM.div(memory_chart)
        ], style="margin:30px 0; padding:20px; background:#fff; border-radius:10px; box-shadow: 0 2px 10px rgba(0,0,0,0.05);"),
        
        DOM.div([
            DOM.p("Last updated: $(Dates.now())", 
                 style="text-align:center; color:#999; font-size:0.9em;")
        ], style="margin-top:40px;")
        
    ], style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; padding:20px; max-width:1200px; margin:0 auto; background:#f5f7fa; min-height:100vh;")
end

port = 8089
try
    global server = Bonito.Server(app, "127.0.0.1", port)
    println("\n Dashboard running at: http://localhost:$port")
catch e
    port = 8090
    global server = Bonito.Server(app, "127.0.0.1", port)
    println("\n Dashboard running at: http://localhost:$port (port 8089 was busy)")
end
try
    while true
        sleep(1)
    end
catch e
    if !isa(e, InterruptException)
        rethrow(e)
    end
end
