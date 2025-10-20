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
    
    timeframe = "all"
    try
        if isdefined(session, :request) && !isnothing(session.request)
            target = session.request.target
            if contains(target, "?days=")
                match_result = match(r"days=(\w+)", target)
                if !isnothing(match_result)
                    timeframe = match_result.captures[1]
                end
            end
        end
    catch e
        println("Error parsing request: ", e)
        timeframe = "all"
    end
    
    filtered = if timeframe == "1"
        filter_data(history, 1)
    elseif timeframe == "7"
        filter_data(history, 7)
    elseif timeframe == "30"
        filter_data(history, 30)
    else
        history
    end
    
    btn_base = "padding:10px 20px; margin:5px; border:none; border-radius:5px; cursor:pointer; font-size:14px;"
    btn_active = btn_base * "background:#2196F3; color:white; font-weight:bold;"
    btn_normal = btn_base * "background:#eee; color:#333;"
    
    buttons = DOM.div([
        DOM.button("Day", 
                  onclick=js"window.location.href='?days=1'",
                  style = timeframe == "1" ? btn_active : btn_normal),
        DOM.button("Week", 
                  onclick=js"window.location.href='?days=7'",
                  style = timeframe == "7" ? btn_active : btn_normal),
        DOM.button("Month", 
                  onclick=js"window.location.href='?days=30'",
                  style = timeframe == "30" ? btn_active : btn_normal),
        DOM.button("All", 
                  onclick=js"window.location.href='?days=all'",
                  style = timeframe == "all" ? btn_active : btn_normal)
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
    
    for h in filtered
        push!(times, get(h, "median_time", 0.0))
        push!(memories, get(h, "memory_mb", 0.0))
        push!(timestamps, get(h, "timestamp", ""))
        push!(commits, get(h, "commit", ""))
    end
    
    df = DataFrame(
        run = 1:length(filtered),
        time = times,
        memory = memories,
        timestamp = timestamps,
        commit = commits
    )
    
    time_chart = df |> @vlplot(
        width = 800,
        height = 400,
        title = "Performance Over Time",
        mark = {:line, point = true, tooltip = true},
        x = {
            :run, 
            title = "Run #",
            axis = {grid = true}
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
        x = {:run, title = "Run #"},
        y = {:memory, title = "Memory (MB)"}
    )
    
    latest = filtered[end]
    median_time = get(latest, "median_time", 0.0)
    memory_mb = get(latest, "memory_mb", 0.0)
    commit = get(latest, "commit", "unknown")
    timestamp = get(latest, "timestamp", "unknown")
    
    change_text = if length(filtered) > 1
        prev = filtered[end-1]
        prev_time = get(prev, "median_time", 0.0)
        change = median_time - prev_time
        change_pct = prev_time > 0 ? (change / prev_time * 100) : 0
        
        color = change > 0 ? "#e74c3c" : "#27ae60"
        symbol = change > 0 ? "↑" : "↓"
        
        DOM.span("$(symbol) $(abs(round(change_pct, digits=1)))%", 
                style="color:$(color); font-weight:bold; margin-left:10px;")
    else
        DOM.span("")
    end
    
    stats = DOM.div([
        DOM.h3("Latest Run Statistics", style="margin-top:0; color:#333;"),
        DOM.div([
            DOM.div([
                DOM.span("Time: ", style="font-weight:bold;"),
                DOM.span("$(round(median_time, digits=2)) ms"),
                change_text
            ], style="margin:5px 0;"),
            DOM.div([
                DOM.span("Memory: ", style="font-weight:bold;"),
                DOM.span("$(round(memory_mb, digits=2)) MB")
            ], style="margin:5px 0;"),
            DOM.div([
                DOM.span("Commit: ", style="font-weight:bold;"),
                DOM.code(commit, style="background:#f4f4f4; padding:2px 5px; border-radius:3px;")
            ], style="margin:5px 0;"),
            DOM.div([
                DOM.span("Timestamp: ", style="font-weight:bold;"),
                DOM.span(timestamp)
            ], style="margin:5px 0;"),
            DOM.div([
                DOM.span("Total runs: ", style="font-weight:bold;"),
                DOM.span("$(length(filtered))")
            ], style="margin:5px 0;")
        ])
    ], style="background:#f8f9fa; padding:20px; margin:20px 0; border-radius:8px; border-left:4px solid #2196F3;")
    
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
    ], style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; padding:20px; max-width:1000px; margin:0 auto; background:white;")
end

server = Bonito.Server(app, "127.0.0.1", 8089)

try
    while true
        sleep(1)
    end
catch e
    if isa(e, InterruptException)
        println("\n down")
    else
        rethrow(e)
    end
end
