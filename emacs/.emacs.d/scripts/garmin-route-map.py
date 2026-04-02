#!/usr/bin/env python3
"""Generate a static PNG route map for Garmin activities on a given date.

Single activity: renders a single map (as before).
Multiple activities: renders a matplotlib grid with one column per activity,
each showing the route map plus key stats.
"""

import argparse
import io
import os
import sqlite3
import sys
import tempfile

import staticmap


def get_activities(db_path, date_str):
    """Return activities with GPS data for the given date."""
    db = sqlite3.connect(db_path)
    cur = db.cursor()
    cur.execute(
        """
        SELECT a.activity_id, a.sport, a.name, COUNT(r.record) as pts,
               a.distance, a.calories, a.avg_hr, a.elapsed_time,
               a.avg_cadence, a.avg_speed
        FROM activities a
        JOIN activity_records r ON a.activity_id = r.activity_id
        WHERE r.position_lat IS NOT NULL
          AND date(a.start_time) = ?
        GROUP BY a.activity_id
        HAVING pts > 10
        ORDER BY a.start_time ASC
        """,
        (date_str,),
    )
    rows = cur.fetchall()
    db.close()
    return rows


def get_track(db_path, activity_id):
    """Return list of (lat, lon) for the activity."""
    db = sqlite3.connect(db_path)
    cur = db.cursor()
    cur.execute(
        """
        SELECT position_lat, position_long
        FROM activity_records
        WHERE activity_id = ? AND position_lat IS NOT NULL
        ORDER BY record
        """,
        (activity_id,),
    )
    coords = cur.fetchall()
    db.close()
    return coords


def render_map_to_image(coords, dark=False):
    """Render GPS track to a PIL Image object."""
    if dark:
        tile_url = "https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png"
        line_color = "#e74c3c"
        start_color = "#73c936"
        end_color = "#ff6b6b"
    else:
        tile_url = None
        line_color = "#c0392b"
        start_color = "#27ae60"
        end_color = "#e74c3c"

    if tile_url:
        m = staticmap.StaticMap(800, 600, url_template=tile_url)
    else:
        m = staticmap.StaticMap(800, 600)

    line_coords = [(lon, lat) for lat, lon in coords]
    m.add_line(staticmap.Line(line_coords, line_color, 3))
    m.add_marker(staticmap.CircleMarker(line_coords[0], start_color, 8))
    m.add_marker(staticmap.CircleMarker(line_coords[-1], end_color, 8))

    return m.render()


def format_elapsed(elapsed_str):
    """Format elapsed time string like '00:10:19.259000' to '10:19'."""
    if not elapsed_str:
        return "N/A"
    parts = elapsed_str.split(":")
    h, m, s = int(parts[0]), int(parts[1]), int(float(parts[2]))
    if h > 0:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


def format_pace(avg_speed_kmh, sport):
    """Format pace from avg speed (km/h). Returns min/km for running/walking."""
    if not avg_speed_kmh or avg_speed_kmh <= 0:
        return "N/A"
    if sport in ("running", "walking", "hiking"):
        pace_min_per_km = 60.0 / avg_speed_kmh
        mins = int(pace_min_per_km)
        secs = int((pace_min_per_km - mins) * 60)
        return f"{mins}:{secs:02d} /km"
    return f"{avg_speed_kmh:.1f} km/h"


def render_single(coords, output_path, dark=False):
    """Render a single activity map to file."""
    img = render_map_to_image(coords, dark=dark)
    img.save(output_path)


def render_grid(activities_data, output_path, dark=False):
    """Render a grid of activity maps with stats using matplotlib."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
    from PIL import Image

    n = len(activities_data)
    bg_color = "#181818" if dark else "#ffffff"
    fg_color = "#e4e4ef" if dark else "#333333"
    accent = "#e74c3c" if dark else "#c0392b"

    fig, axes = plt.subplots(1, n, figsize=(6 * n, 8), facecolor=bg_color)
    if n == 1:
        axes = [axes]

    for i, (activity, coords, map_img) in enumerate(activities_data):
        ax = axes[i]
        activity_id, sport, name, pts, distance, calories, avg_hr, elapsed, cadence, avg_speed = activity

        # Show map image
        ax.imshow(np.array(map_img))
        ax.set_xticks([])
        ax.set_yticks([])
        for spine in ax.spines.values():
            spine.set_visible(False)

        # Title
        title = name or sport.capitalize()
        ax.set_title(title, color=fg_color, fontsize=14, fontweight="bold", pad=10)

        # Stats text below image
        dist_km = distance if distance else 0
        stats_lines = [
            f"Distance: {dist_km:.2f} km",
            f"Time: {format_elapsed(elapsed)}",
            f"Pace: {format_pace(avg_speed, sport)}",
        ]
        if avg_hr:
            stats_lines.append(f"Avg HR: {avg_hr} bpm")
        if cadence:
            stats_lines.append(f"Avg Cadence: {cadence * 2} spm")
        if calories:
            stats_lines.append(f"Calories: {calories} kcal")

        stats_text = "\n".join(stats_lines)
        ax.text(
            0.5, -0.02, stats_text,
            transform=ax.transAxes,
            ha="center", va="top",
            fontsize=11, color=fg_color,
            family="monospace",
            linespacing=1.6,
        )

    plt.tight_layout(rect=[0, 0.15, 1, 0.95])
    plt.savefig(output_path, dpi=150, facecolor=bg_color, bbox_inches="tight")
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description="Generate route map PNG")
    parser.add_argument("date", help="Date in YYYY-MM-DD format")
    parser.add_argument(
        "--db",
        default="~/HealthData/DBs/garmin_activities.db",
        help="Path to garmin_activities.db",
    )
    parser.add_argument(
        "--output",
        default="~/.cache/emacs/garmin-route.png",
        help="Output PNG path",
    )
    parser.add_argument("--dark", action="store_true", help="Use dark map tiles")
    args = parser.parse_args()

    db_path = os.path.expanduser(args.db)
    output_path = os.path.expanduser(args.output)

    if not os.path.exists(db_path):
        print("NO_DB", file=sys.stderr)
        sys.exit(1)

    activities = get_activities(db_path, args.date)
    if not activities:
        print("NO_ACTIVITY")
        sys.exit(0)

    # Filter to activities with enough GPS points
    valid = []
    for act in activities:
        coords = get_track(db_path, act[0])
        if len(coords) >= 10:
            map_img = render_map_to_image(coords, dark=args.dark)
            valid.append((act, coords, map_img))

    if not valid:
        print("NO_ACTIVITY")
        sys.exit(0)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    if len(valid) == 1:
        # Single activity: save map directly (higher quality, no matplotlib overhead)
        valid[0][2].save(output_path)
    else:
        # Multiple activities: render grid
        render_grid(valid, output_path, dark=args.dark)

    # Print activity info lines for elisp to parse
    for act, _, _ in valid:
        activity_id, sport, name, pts = act[0], act[1], act[2], act[3]
        print(f"{activity_id}|{sport}|{name}|{pts}")


if __name__ == "__main__":
    main()
