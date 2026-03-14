#!/usr/bin/env python3
"""Generate a static PNG route map for Garmin activities on a given date."""

import argparse
import sqlite3
import sys

import staticmap


def get_activities(db_path, date_str):
    """Return activity IDs with GPS data for the given date, preferring runs."""
    db = sqlite3.connect(db_path)
    cur = db.cursor()
    cur.execute(
        """
        SELECT a.activity_id, a.sport, a.name, COUNT(r.record) as pts
        FROM activities a
        JOIN activity_records r ON a.activity_id = r.activity_id
        WHERE r.position_lat IS NOT NULL
          AND date(a.start_time) = ?
        GROUP BY a.activity_id
        HAVING pts > 10
        ORDER BY
            CASE a.sport
                WHEN 'running' THEN 0
                WHEN 'walking' THEN 1
                WHEN 'cycling' THEN 2
                ELSE 3
            END,
            pts DESC
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


def render_map(coords, output_path, dark=False):
    """Render GPS track to a static map PNG."""
    if dark:
        # Use CartoDB dark matter tiles for dark theme
        tile_url = "https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png"
        line_color = "#e74c3c"
        start_color = "#73c936"
        end_color = "#ff6b6b"
    else:
        tile_url = None  # default OSM tiles
        line_color = "#c0392b"
        start_color = "#27ae60"
        end_color = "#e74c3c"

    if tile_url:
        m = staticmap.StaticMap(800, 600, url_template=tile_url)
    else:
        m = staticmap.StaticMap(800, 600)

    # Draw route line
    line_coords = [(lon, lat) for lat, lon in coords]
    m.add_line(staticmap.Line(line_coords, line_color, 3))

    # Start and end markers
    m.add_marker(staticmap.CircleMarker(line_coords[0], start_color, 8))
    m.add_marker(staticmap.CircleMarker(line_coords[-1], end_color, 8))

    img = m.render()
    img.save(output_path)


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

    import os

    db_path = os.path.expanduser(args.db)
    output_path = os.path.expanduser(args.output)

    if not os.path.exists(db_path):
        print("NO_DB", file=sys.stderr)
        sys.exit(1)

    activities = get_activities(db_path, args.date)
    if not activities:
        print("NO_ACTIVITY")
        sys.exit(0)

    # Use the best activity (first after sorting)
    activity_id, sport, name, pts = activities[0]
    coords = get_track(db_path, activity_id)

    if len(coords) < 10:
        print("NO_ACTIVITY")
        sys.exit(0)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    render_map(coords, output_path, dark=args.dark)
    # Print activity info for elisp to use
    print(f"{sport}|{name}|{pts}")


if __name__ == "__main__":
    main()
