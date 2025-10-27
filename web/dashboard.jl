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

function filter_data(data, days)
    days == 0 && return data
    cutoff = now() - Day(days)
    filter(h -> DateTime(h["timestamp"]) >= cutoff, data)
end

app = App() do session::Session
    if isempty(history)
        return DOM.div([
            DOM.h1("Trixi Benchmarks"),
            DOM.p("No data. Run: julia scripts/runbenchmarks.jl")
        ])
    end
    
    timeframe = Observable("all")
    
    content = map(timeframe) do tf
        btn_day = Bonito.Button("Day")
        btn_week = Bonito.Button("Week")
        btn_month = Bonito.Button("Month")
        btn_all = Bonito.Button("All")
        
        on(btn_day) do click
            timeframe[] = "1"
        end
        
        on(btn_week) do click
            timeframe[] = "7"
        end
        
        on(btn_month) do click
            timeframe[] = "30"
        end
        
        on(btn_all) do click
            timeframe[] = "all"
        end
        
        filtered = if tf == "1"
            filter_data(history, 1)
        elseif tf == "7"
            filter_data(history, 7)
        elseif tf == "30"
            filter_data(history, 30)
        else
            history
        end
        
        btn_base = "padding:10px 20px; margin:5px; border:none; border-radius:5px; font-size:14px; cursor:pointer;"
        
        buttons = DOM.div([
            DOM.div(btn_day, style = tf == "1" ? "display:inline-block; background:#2196F3; color:white; $btn_base" : "display:inline-block; background:#eee; $btn_base"),
            DOM.div(btn_week, style = tf == "7" ? "display:inline-block; background:#2196F3; color:white; $btn_base" : "display:inline-block; background:#eee; $btn_base"),
            DOM.div(btn_month, style = tf == "30" ? "display:inline-block; background:#2196F3; color:white; $btn_base" : "display:inline-block; background:#eee; $btn_base"),
            DOM.div(btn_all, style = tf == "all" ? "display:inline-block; background:#2196F3; color:white; $btn_base" : "display:inline-block; background:#eee; $btn_base")
        ], style="text-align:center; margin:20px 0;")
        
        if isempty(filtered)
            return DOM.div([
                DOM.h1("Trixi Benchmarks", style="text-align:center; color:#333;"),
                buttons,
                DOM.p("No data for this period", style="text-align:center; color:#666;"),
                DOM.p("Total records available: $(length(history))", 
                      style="text-align:center; color:#999; font-size:0.9em;")
            ], style="font-family:Arial, sans-serif; padding:20px; max-width:1000px; margin:0 auto;")
        end
        
        times = Float64[]
        memories = Float64[]
        timestamps = String[]
        commits = String[]
        commit_shorts = String[]
        
        for h in filtered
            median_time = if haskey(h, "time") && haskey(h["time"], "median_ms")
                h["time"]["median_ms"]
            else
                get(h, "median_time", 0.0)
            end
            
            memory_mb = if haskey(h, "memory") && haskey(h["memory"], "allocated_mb")
                h["memory"]["allocated_mb"]
            else
                get(h, "memory_mb", 0.0)
            end
            
            push!(times, median_time)
            push!(memories, memory_mb)
            push!(timestamps, get(h, "timestamp", ""))
            
            full_commit = get(h, "commit", "unknown")
            push!(commits, full_commit)
            
            short_commit = get(h, "commit_short", "")
            if isempty(short_commit) || short_commit == "unknown"
                short_commit = length(full_commit) >= 7 ? full_commit[1:7] : full_commit
            end
            push!(commit_shorts, short_commit)
        end
        
        avg_time = sum(times) / length(times)
        min_time = minimum(times)
        max_time = maximum(times)
        latest = filtered[end]
        
        median_time = if haskey(latest, "time") && haskey(latest["time"], "median_ms")
            latest["time"]["median_ms"]
        else
            get(latest, "median_time", 0.0)
        end
        
        memory_mb = if haskey(latest, "memory") && haskey(latest["memory"], "allocated_mb")
            latest["memory"]["allocated_mb"]
        else
            get(latest, "memory_mb", 0.0)
        end
        
        commit = get(latest, "commit", "unknown")
        
        df = DataFrame(
            run = 1:length(filtered),
            time = times,
            memory = memories,
            timestamp = timestamps,
            commit = commits,
            commit_short = commit_shorts
        )
        
        time_chart = df |> @vlplot(
            width = 800,
            height = 400,
            title = "Performance Over Time ($(length(filtered)) runs)",
            mark = {:line, point = true, tooltip = true},
            x = {
                :commit_short, 
                title = "Commit",
                axis = {
                    grid = true,
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
                {field = :timestamp, title = "Timestamp"}
            ]
        )
        
        memory_chart = df |> @vlplot(
            width = 800,
            height = 300,
            title = "Memory Usage",
            mark = {:area, opacity = 0.7, color = "#ff6b6b"},
            x = {
                :commit_short, 
                title = "Commit",
                axis = {
                    labelAngle = -45,
                    labelLimit = 100
                }
            },
            y = {:memory, title = "Memory (MB)"}
        )
        
        change_text = if length(filtered) > 1
            prev = filtered[end-1]
            prev_time = if haskey(prev, "time") && haskey(prev["time"], "median_ms")
                prev["time"]["median_ms"]
            else
                get(prev, "median_time", 0.0)
            end
            change = median_time - prev_time
            change_pct = prev_time > 0 ? (change / prev_time * 100) : 0
            
            color = change > 0 ? "#e74c3c" : "#27ae60"
            symbol = change > 0 ? "↑" : "↓"
            
            DOM.span("$(symbol) $(abs(round(change_pct, digits=1)))%", 
                    style="color:$(color); font-weight:bold; margin-left:10px;")
        else
            DOM.span("")
        end
        
        period_text = if tf == "1"
            "Last 24 hours"
        elseif tf == "7"
            "Last 7 days"
        elseif tf == "30"
            "Last 30 days"
        else
            "All time"
        end
        
        stats = DOM.div([
            DOM.h3("Statistics - $period_text", style="margin-top:0; color:#333;"),
            DOM.div([
                DOM.div([
                    DOM.span("Latest: ", style="font-weight:bold;"),
                    DOM.span("$(round(median_time, digits=2)) ms"),
                    change_text
                ], style="margin:5px 0;"),
                DOM.div([
                    DOM.span("Average: ", style="font-weight:bold;"),
                    DOM.span("$(round(avg_time, digits=2)) ms")
                ], style="margin:5px 0;"),
                DOM.div([
                    DOM.span("Best: ", style="font-weight:bold;"),
                    DOM.span("$(round(min_time, digits=2)) ms", style="color:#27ae60;")
                ], style="margin:5px 0;"),
                DOM.div([
                    DOM.span("Worst: ", style="font-weight:bold;"),
                    DOM.span("$(round(max_time, digits=2)) ms", style="color:#e74c3c;")
                ], style="margin:5px 0;"),
                DOM.div([
                    DOM.span("Showing: ", style="font-weight:bold;"),
                    DOM.span("$(length(filtered)) of $(length(history)) runs")
                ], style="margin:5px 0;"),
                DOM.div([
                    DOM.span("Latest commit: ", style="font-weight:bold;"),
                    DOM.code(commit, style="background:#f4f4f4; padding:2px 5px; border-radius:3px;")
                ], style="margin:5px 0;")
            ])
        ], style="background:#f8f9fa; padding:20px; margin:20px 0; border-radius:8px;")
        
        return DOM.div([
            DOM.h1("Trixi Performance Tracker", style="text-align:center; color:#2c3e50;"),
            buttons,
            stats,
            DOM.div([
                DOM.h3("Performance Timeline", style="color:#333; margin-bottom:10px;"),
                DOM.div(time_chart)
            ], style="margin:20px 0;"),
            DOM.div([
                DOM.h3("Memory Usage", style="color:#333; margin-bottom:10px;"),
                DOM.div(memory_chart)
            ], style="margin:20px 0;")
        ], style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; padding:20px; max-width:1000px; margin:0 auto; background:white; min-height:100vh;")
    end
    
    return content
end

port = 8089
try
    global server = Bonito.Server(app, "127.0.0.1", port)
    println("Dashboard: http://localhost:$port")
catch e
    port = 8090
    global server = Bonito.Server(app, "127.0.0.1", port)
    println("Dashboard: http://localhost:$port")
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
