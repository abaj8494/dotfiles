#!/usr/bin/env python3
"""Generate a self-contained HTML dashboard for a Garmin activity.

Reads activity data from GarminDB SQLite databases and produces an HTML file
with Chart.js charts: HR, cadence, elevation, speed over time, HR zones,
and pace splits.
"""

import argparse
import html
import json
import os
import sqlite3
import sys


def get_activity(db_path, activity_id):
    """Return activity summary dict."""
    db = sqlite3.connect(db_path)
    db.row_factory = sqlite3.Row
    cur = db.cursor()
    cur.execute("SELECT * FROM activities WHERE activity_id = ?", (activity_id,))
    row = cur.fetchone()
    db.close()
    if row:
        return dict(row)
    return None


def get_records(db_path, activity_id):
    """Return list of record dicts for the activity."""
    db = sqlite3.connect(db_path)
    db.row_factory = sqlite3.Row
    cur = db.cursor()
    cur.execute(
        """SELECT record, timestamp, distance, cadence, altitude, hr, speed, temperature
           FROM activity_records WHERE activity_id = ? ORDER BY record""",
        (activity_id,),
    )
    rows = [dict(r) for r in cur.fetchall()]
    db.close()
    return rows


def parse_time_to_seconds(t):
    """Parse 'HH:MM:SS.ffffff' to total seconds."""
    if not t:
        return 0
    parts = t.split(":")
    return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])


def format_elapsed(seconds):
    """Format seconds to H:MM:SS or M:SS."""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    if h > 0:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


def compute_splits(records, split_distance_km=1.0):
    """Compute per-km splits from records. Returns list of (split_num, pace_sec)."""
    splits = []
    if not records or records[0].get("distance") is None:
        return splits

    current_split = 1
    split_start_idx = 0
    split_start_dist = 0.0

    for i, rec in enumerate(records):
        dist = rec.get("distance") or 0
        if dist is None:
            continue
        if dist - split_start_dist >= split_distance_km:
            # Compute time for this split
            start_ts = records[split_start_idx].get("timestamp", "")
            end_ts = rec.get("timestamp", "")
            if start_ts and end_ts:
                from datetime import datetime
                fmt = "%Y-%m-%d %H:%M:%S.%f"
                try:
                    dt_start = datetime.strptime(start_ts, fmt)
                    dt_end = datetime.strptime(end_ts, fmt)
                    elapsed = (dt_end - dt_start).total_seconds()
                    splits.append((current_split, elapsed))
                except ValueError:
                    pass
            current_split += 1
            split_start_idx = i
            split_start_dist = dist

    return splits


def compute_hr_zones(activity):
    """Return list of (zone_label, seconds) from activity HR zone times."""
    zones = []
    for z in range(1, 6):
        time_key = f"hrz_{z}_time"
        hr_key = f"hrz_{z}_hr"
        t = activity.get(time_key)
        hr = activity.get(hr_key)
        secs = parse_time_to_seconds(t) if t else 0
        label = f"Zone {z}"
        if hr:
            label += f" (<{hr})"
        zones.append((label, secs))
    return zones


def downsample(data, max_points=300):
    """Downsample a list to at most max_points using simple striding."""
    if len(data) <= max_points:
        return data
    stride = len(data) / max_points
    return [data[int(i * stride)] for i in range(max_points)]


def generate_html(activity, records, dark=False):
    """Generate self-contained HTML dashboard string."""
    bg = "#1a1a1a" if dark else "#ffffff"
    fg = "#e4e4ef" if dark else "#333333"
    card_bg = "#252525" if dark else "#f5f5f5"
    border = "#444" if dark else "#ddd"
    accent = "#e74c3c"
    grid_color = "rgba(255,255,255,0.1)" if dark else "rgba(0,0,0,0.1)"

    # Summary stats
    sport = activity.get("sport", "Activity")
    name = activity.get("name", sport.capitalize())
    dist_km = activity.get("distance") or 0
    elapsed_s = parse_time_to_seconds(activity.get("elapsed_time"))
    moving_s = parse_time_to_seconds(activity.get("moving_time"))
    calories = activity.get("calories") or 0
    avg_hr = activity.get("avg_hr") or "N/A"
    max_hr = activity.get("max_hr") or "N/A"
    avg_cadence = (activity.get("avg_cadence") or 0) * 2 or "N/A"
    max_cadence = (activity.get("max_cadence") or 0) * 2 or "N/A"
    ascent = activity.get("ascent") or 0
    descent = activity.get("descent") or 0
    avg_speed = activity.get("avg_speed") or 0
    max_speed = activity.get("max_speed") or 0
    avg_temp = activity.get("avg_temperature")

    # Pace
    if avg_speed and avg_speed > 0 and sport in ("running", "walking", "hiking"):
        pace_min_per_km = 60.0 / avg_speed
        pace_min = int(pace_min_per_km)
        pace_sec = int((pace_min_per_km - pace_min) * 60)
        pace_str = f"{pace_min}:{pace_sec:02d} /km"
    elif avg_speed and avg_speed > 0:
        pace_str = f"{avg_speed:.1f} km/h"
    else:
        pace_str = "N/A"

    # Time series data (downsampled)
    timestamps_raw = []
    hr_data = []
    cadence_data = []
    altitude_data = []
    speed_data = []
    distance_data = []

    for rec in records:
        ts = rec.get("timestamp", "")
        # Extract just HH:MM:SS
        time_part = ts.split(" ")[-1].split(".")[0] if ts else ""
        timestamps_raw.append(time_part)
        hr_data.append(rec.get("hr") or None)
        raw_cad = rec.get("cadence")
        cadence_data.append(raw_cad * 2 if raw_cad else None)
        altitude_data.append(rec.get("altitude") or None)
        sp = rec.get("speed") or 0
        speed_data.append(round(sp, 1) if sp else None)
        distance_data.append(rec.get("distance") or 0)

    # Downsample for chart performance
    ds_indices = list(range(len(timestamps_raw)))
    if len(ds_indices) > 300:
        stride = len(ds_indices) / 300
        ds_indices = [int(i * stride) for i in range(300)]

    ds_timestamps = [timestamps_raw[i] for i in ds_indices]
    ds_hr = [hr_data[i] for i in ds_indices]
    ds_cadence = [cadence_data[i] for i in ds_indices]
    ds_altitude = [altitude_data[i] for i in ds_indices]
    ds_speed = [speed_data[i] for i in ds_indices]

    # HR zones
    hr_zones = compute_hr_zones(activity)
    zone_labels = [z[0] for z in hr_zones]
    zone_values = [round(z[1], 1) for z in hr_zones]
    zone_colors = ["#3498db", "#2ecc71", "#f1c40f", "#e67e22", "#e74c3c"]

    # Pace splits
    splits = compute_splits(records)
    split_labels = [f"km {s[0]}" for s in splits]
    split_values = [round(s[1], 1) for s in splits]

    # Format split pace for tooltips
    def fmt_pace(secs):
        m = int(secs // 60)
        s = int(secs % 60)
        return f"{m}:{s:02d}"

    split_pace_labels = [fmt_pace(s[1]) for s in splits]

    summary_rows = f"""
        <tr><td>Distance</td><td>{dist_km:.2f} km</td></tr>
        <tr><td>Elapsed Time</td><td>{format_elapsed(elapsed_s)}</td></tr>
        <tr><td>Moving Time</td><td>{format_elapsed(moving_s)}</td></tr>
        <tr><td>Avg Pace/Speed</td><td>{pace_str}</td></tr>
        <tr><td>Calories</td><td>{calories} kcal</td></tr>
        <tr><td>Avg HR</td><td>{avg_hr} bpm</td></tr>
        <tr><td>Max HR</td><td>{max_hr} bpm</td></tr>
        <tr><td>Avg Cadence</td><td>{avg_cadence} spm</td></tr>
        <tr><td>Max Cadence</td><td>{max_cadence} spm</td></tr>
        <tr><td>Ascent</td><td>{ascent:.0f} m</td></tr>
        <tr><td>Descent</td><td>{descent:.0f} m</td></tr>
        <tr><td>Avg Speed</td><td>{avg_speed:.1f} km/h</td></tr>
        <tr><td>Max Speed</td><td>{max_speed:.1f} km/h</td></tr>
    """
    if avg_temp is not None:
        summary_rows += f'<tr><td>Avg Temp</td><td>{avg_temp:.1f} C</td></tr>'

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{html.escape(name)} - Activity Dashboard</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
<style>
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  body {{
    background: {bg}; color: {fg};
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    padding: 24px; max-width: 1400px; margin: 0 auto;
  }}
  h1 {{ font-size: 28px; margin-bottom: 4px; }}
  .subtitle {{ color: {fg}88; font-size: 14px; margin-bottom: 24px; }}
  .grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px; }}
  .card {{
    background: {card_bg}; border: 1px solid {border}; border-radius: 10px;
    padding: 20px; position: relative;
  }}
  .card h2 {{ font-size: 16px; margin-bottom: 12px; color: {fg}cc; }}
  .card.full {{ grid-column: 1 / -1; }}
  table {{ width: 100%; border-collapse: collapse; }}
  td {{ padding: 6px 12px; border-bottom: 1px solid {border}44; font-size: 14px; }}
  td:first-child {{ color: {fg}99; }}
  td:last-child {{ text-align: right; font-weight: 600; font-variant-numeric: tabular-nums; }}
  canvas {{ width: 100% !important; height: 250px !important; }}
  .zones-container {{ display: flex; gap: 20px; align-items: center; }}
  .zones-canvas {{ flex: 0 0 200px; height: 200px !important; width: 200px !important; }}
  .zones-legend {{ flex: 1; }}
  .zones-legend div {{ display: flex; justify-content: space-between; padding: 4px 0; font-size: 13px; }}
  .zones-legend .dot {{ width: 10px; height: 10px; border-radius: 50%; display: inline-block; margin-right: 8px; }}
</style>
</head>
<body>
<h1>{html.escape(name)}</h1>
<div class="subtitle">{html.escape(sport.capitalize())} &bull; {activity.get('start_time', '')[:10]}</div>

<div class="grid">
  <div class="card">
    <h2>Summary</h2>
    <table>{summary_rows}</table>
  </div>

  <div class="card">
    <h2>HR Zones</h2>
    <div class="zones-container">
      <canvas id="hrZonesChart" class="zones-canvas"></canvas>
      <div class="zones-legend" id="zonesLegend"></div>
    </div>
  </div>

  <div class="card full">
    <h2>Heart Rate</h2>
    <canvas id="hrChart"></canvas>
  </div>

  <div class="card full">
    <h2>Elevation Profile</h2>
    <canvas id="elevationChart"></canvas>
  </div>

  <div class="card">
    <h2>Cadence</h2>
    <canvas id="cadenceChart"></canvas>
  </div>

  <div class="card">
    <h2>Speed</h2>
    <canvas id="speedChart"></canvas>
  </div>

  {"" if not splits else '''<div class="card full"><h2>Pace Splits</h2><canvas id="splitsChart"></canvas></div>'''}
</div>

<script>
const fg = "{fg}";
const gridColor = "{grid_color}";
const accent = "{accent}";

const chartDefaults = {{
  responsive: true,
  maintainAspectRatio: false,
  plugins: {{ legend: {{ display: false }} }},
  scales: {{
    x: {{
      ticks: {{ color: fg + "88", maxTicksLimit: 10 }},
      grid: {{ color: gridColor }}
    }},
    y: {{
      ticks: {{ color: fg + "88" }},
      grid: {{ color: gridColor }}
    }}
  }}
}};

function lineChart(id, labels, data, color, label, fill) {{
  const ctx = document.getElementById(id);
  if (!ctx) return;
  new Chart(ctx, {{
    type: "line",
    data: {{
      labels: labels,
      datasets: [{{
        label: label,
        data: data,
        borderColor: color,
        backgroundColor: fill ? color + "33" : undefined,
        fill: !!fill,
        borderWidth: 1.5,
        pointRadius: 0,
        tension: 0.3,
        spanGaps: true
      }}]
    }},
    options: chartDefaults
  }});
}}

const timestamps = {json.dumps(ds_timestamps)};

lineChart("hrChart", timestamps, {json.dumps(ds_hr)}, "#e74c3c", "HR (bpm)", false);
lineChart("elevationChart", timestamps, {json.dumps(ds_altitude)}, "#3498db", "Elevation (m)", true);
lineChart("cadenceChart", timestamps, {json.dumps(ds_cadence)}, "#2ecc71", "Cadence (spm)", false);
lineChart("speedChart", timestamps, {json.dumps(ds_speed)}, "#f39c12", "Speed (km/h)", false);

// HR Zones doughnut
const zoneLabels = {json.dumps(zone_labels)};
const zoneValues = {json.dumps(zone_values)};
const zoneColors = {json.dumps(zone_colors)};
const zonePaces = {json.dumps(split_pace_labels)};

new Chart(document.getElementById("hrZonesChart"), {{
  type: "doughnut",
  data: {{
    labels: zoneLabels,
    datasets: [{{
      data: zoneValues,
      backgroundColor: zoneColors,
      borderWidth: 0
    }}]
  }},
  options: {{
    responsive: false,
    plugins: {{
      legend: {{ display: false }},
      tooltip: {{
        callbacks: {{
          label: function(ctx) {{
            const secs = ctx.raw;
            const m = Math.floor(secs / 60);
            const s = Math.round(secs % 60);
            return ctx.label + ": " + m + ":" + String(s).padStart(2, "0");
          }}
        }}
      }}
    }}
  }}
}});

// Build zones legend
const legendDiv = document.getElementById("zonesLegend");
zoneLabels.forEach((label, i) => {{
  const secs = zoneValues[i];
  const m = Math.floor(secs / 60);
  const s = Math.round(secs % 60);
  const timeStr = m + ":" + String(s).padStart(2, "0");
  const row = document.createElement("div");
  row.innerHTML = '<span><span class="dot" style="background:' + zoneColors[i] + '"></span>' + label + '</span><span>' + timeStr + '</span>';
  legendDiv.appendChild(row);
}});

// Pace splits bar chart
const splitLabels = {json.dumps(split_labels)};
const splitValues = {json.dumps(split_values)};
const splitPaces = {json.dumps(split_pace_labels)};

if (splitLabels.length > 0) {{
  new Chart(document.getElementById("splitsChart"), {{
    type: "bar",
    data: {{
      labels: splitLabels,
      datasets: [{{
        label: "Pace (sec/km)",
        data: splitValues,
        backgroundColor: "#9b59b6",
        borderRadius: 4
      }}]
    }},
    options: {{
      ...chartDefaults,
      plugins: {{
        legend: {{ display: false }},
        tooltip: {{
          callbacks: {{
            label: function(ctx) {{
              return splitPaces[ctx.dataIndex] + " /km";
            }}
          }}
        }}
      }},
      scales: {{
        ...chartDefaults.scales,
        y: {{
          ...chartDefaults.scales.y,
          ticks: {{
            color: fg + "88",
            callback: function(v) {{
              const m = Math.floor(v / 60);
              const s = Math.round(v % 60);
              return m + ":" + String(s).padStart(2, "0");
            }}
          }}
        }}
      }}
    }}
  }});
}}
</script>
</body>
</html>"""


def main():
    parser = argparse.ArgumentParser(description="Generate Garmin activity HTML dashboard")
    parser.add_argument("--activity-id", required=True, help="Activity ID")
    parser.add_argument(
        "--db",
        default="~/HealthData/DBs/garmin_activities.db",
        help="Path to garmin_activities.db",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Output HTML path (default: ~/.cache/emacs/garmin-activity-{id}.html)",
    )
    parser.add_argument("--dark", action="store_true", help="Use dark theme")
    args = parser.parse_args()

    db_path = os.path.expanduser(args.db)
    output_path = args.output
    if output_path is None:
        output_path = os.path.expanduser(
            f"~/.cache/emacs/garmin-activity-{args.activity_id}.html"
        )
    else:
        output_path = os.path.expanduser(output_path)

    if not os.path.exists(db_path):
        print("NO_DB", file=sys.stderr)
        sys.exit(1)

    activity = get_activity(db_path, args.activity_id)
    if not activity:
        print(f"Activity {args.activity_id} not found", file=sys.stderr)
        sys.exit(1)

    records = get_records(db_path, args.activity_id)

    html_content = generate_html(activity, records, dark=args.dark)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w") as f:
        f.write(html_content)

    print(output_path)


if __name__ == "__main__":
    main()
