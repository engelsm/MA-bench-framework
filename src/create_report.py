import argparse
import json
import html
import statistics
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(
        description="Generate an HTML report from benchmark result JSON(s)"
    )
    parser.add_argument(
        "json_files",
        nargs="+",
        type=str,
        help="Path(s) to result JSON file(s) to include in the report",
    )
    parser.add_argument(
        "--output",
        nargs="?",
        type=str,
        help="Path to output folder",
    )

    args = parser.parse_args()

    paths = [Path(p).resolve() for p in args.json_files]

    if len(paths) == 0:
        raise ValueError("You must pass at least one JSON file.")

    all_results = []
    for p in paths:
        with open(p) as f:
            all_results.append(json.load(f))

    output_dir = Path(args.output) if args.output else None
    if output_dir:
        if output_dir.exists() and not output_dir.is_dir():
            raise NotADirectoryError(
                f"Output path exists but is not a directory: {output_dir}"
            )

    build_report_html(all_results, output_dir)


def aggregate_perf_results(runs_results):
    # It is possible that perf sometimes misses events unfortunately, for aggregation we only consider runs where the event was recorded
    agg = {}
    all_events = {event for r in runs_results for event in r["perf"].keys()}

    for event in sorted(all_events):
        values = [float(r["perf"][event]) for r in runs_results if event in r["perf"]]
        if not values:
            continue
        agg[event] = {
            "values": values,
            "count": len(values),
            "avg": sum(values) / len(values),
            "min": min(values),
            "max": max(values),
        }

    return agg


def build_report_html(all_results, output_dir):
    """
    Compact HTML report.
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    html_content = f"""
<html>
<head>
<title>amd-secure-bench Report</title>
<style>
    body {{
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        background: #fff;
        color: #111;
        margin: 20px;
    }}

    h1 {{
        text-align: center;
        font-size: 2em;
        margin-bottom: 20px;
        color: #222;
    }}

    h2 {{
        border-left: 3px solid #222;
        padding-left: 10px;
        margin-top: 25px;
        margin-bottom: 8px;
        font-size: 1.4em;
        color: #222;
    }}

    h3 {{
        margin-top: 10px;
        margin-bottom: 5px;
        font-size: 1.1em;
        color: #333;
    }}

    .benchmark-block {{
        display: flex;
        gap: 20px;
        flex-wrap: wrap;
        background: #f5f5f5;
        padding: 15px;
        border-radius: 5px;
        margin-bottom: 15px;
        align-items: stretch;
        width: 100%;
        box-sizing: border-box;
    }}

    .left-col, .right-col {{
        flex: 1 1 0;
        min-width: 300px;
        display: flex;
        flex-direction: column;
        gap: 10px;
    }}

    .left-inner, .right-inner {{
        display: flex;
        flex-direction: column;
        justify-content: flex-start;
        flex-grow: 1;
    }}

    table {{
        border-collapse: collapse;
        font-size: 12px;
        width: 100%;
    }}

    table.meta-table td, table.meta-table th {{
        padding: 4px 6px;
        border: 1px solid #ddd;
        width: 50%;
    }}

    table th {{
        background: #222;
        color: white;
        font-weight: bold;
        text-align: left;
    }}

    table.data-table td, table.data-table th {{
        padding: 4px 6px;
        border: 1px solid #ddd;
        text-align: left;
        width: 25%;
    }}

    tr:nth-child(even) {{ background: #f9f9f9; }}
    tr:nth-child(odd) {{ background: #fff; }}

    .perf-data {{
        font-family: monospace;
        white-space: pre-wrap;
        background: #eee;
        padding: 4px 6px;
        border-radius: 3px;
        font-size: 12px;
    }}

    .show-btn {{
        background: #222;
        color: white;
        border: none;
        padding: 6px 12px;
        border-radius: 4px;
        cursor: pointer;
        margin-bottom: 5px;
        font-weight: bold;
        font-size: 12px;
    }}

    .show-btn:hover {{ background: #555; }}

    .details {{
        background: #eaeaea;
        padding: 6px;
        border-radius: 4px;
        margin-top: 5px;
    }}
</style>
<script>
    function toggleDetails(id){{
        const el = document.getElementById(id);
        el.style.display = (el.style.display === "none" || el.style.display === "") ? "block" : "none";
    }}
</script>
</head>
<body>
<h1>amd-secure-bench Benchmark Report</h1>
"""

    for i, b in enumerate(all_results):
        b_infos = b.get("b_infos", {})

        html_content += (
            f"<h2>Benchmark: {html.escape(b_infos.get('source','Unknown'))}</h2>"
        )
        html_content += "<div class='benchmark-block'>"

        # Left column
        html_content += "<div class='left-col'><div class='left-inner'>"
        html_content += "<b>System & Benchmark Info</b><br><table class='meta-table'>"
        sysinfo = b.get("sys_info", {})
        for key, val in sysinfo.items():
            html_content += (
                f"<tr><th>{key.replace('_',' ').title()}</th><td>{val}</td></tr>"
            )

        html_content += f"<tr><th>Compiler Flags</th><td>{html.escape(' '.join(b_infos.get('compiler_flags', [])))}</td></tr>"
        html_content += f"<tr><th>Runs / Warmup</th><td>{b_infos.get('runs',0)} / {b_infos.get('warmup_runs',0)}</td></tr>"
        html_content += f"<tr><th>Args</th><td>{html.escape(' '.join(b_infos.get('args',[]) or ['None']))}</td></tr>"
        html_content += "</table></div></div>"

        # Right column
        html_content += "<div class='right-col'><div class='right-inner'>"
        runtimes = [r.get("runtime", 0.0) for r in b.get("results", [])]
        runtime_avg = sum(runtimes) / len(runtimes) if runtimes else 0.0
        runtime_min = min(runtimes) if runtimes else 0.0
        runtime_max = max(runtimes) if runtimes else 0.0
        runtime_std = statistics.stdev(runtimes) if len(runtimes) > 1 else 0.0

        html_content += "<h3>Runtime Summary</h3><table class='data-table'>"
        html_content += f"<tr><th>Avg (s)</th><th>Min (s)</th><th>Max (s)</th><th>Stddev (s)</th></tr>"
        html_content += f"<tr><td>{runtime_avg:.6f}</td><td>{runtime_min:.6f}</td><td>{runtime_max:.6f}</td><td>{runtime_std:.6f}</td></tr>"
        html_content += "</table>"

        agg_perf = aggregate_perf_results(b.get("results", []))
        if agg_perf:
            html_content += (
                "<h3>Performance Counter Summary</h3><table class='data-table'>"
            )
            html_content += (
                "<tr><th>Event</th><th>Avg</th><th>Min</th><th>Max</th></tr>"
            )
            for event, stats in agg_perf.items():
                html_content += f"<tr><td>{html.escape(event)}</td><td>{stats['avg']:.2f}</td><td>{stats['min']:.2f}</td><td>{stats['max']:.2f}</td></tr>"
            html_content += "</table>"
        html_content += "</div></div>"

        html_content += "</div>"  # end benchmark-block

        # PER-RUN DETAILS
        detail_id = f"details_{i}"
        html_content += f"<button class='show-btn' onclick=\"toggleDetails('{detail_id}')\">Show Per-Run Details</button>"
        html_content += f"<div class='details' id='{detail_id}' style='display:none;'>"
        html_content += "<h3>Per-Run Results</h3><table class='data-table'><tr><th>Iter</th><th>Runtime (s)</th><th>Perf</th></tr>"

        # Gather union of all perf events across runs
        all_events = set()
        for r in b.get("results", []):
            for ev in r.get("perf", {}):
                all_events.add(ev)
        all_events = sorted(all_events)

        # Print runs
        for r in b.get("results", []):
            perf_list = []
            for ev in all_events:
                val = r.get("perf", {}).get(ev)
                if val is None:
                    val = (
                        "<span style='color:#b00;font-weight:bold;'>NOT RECORDED</span>"
                    )
                perf_list.append(f"{ev}: {val}")

            perf_data_str = "<br>".join(perf_list)

            html_content += (
                f"<tr>"
                f"<td>{r.get('iteration',0)}</td>"
                f"<td>{r.get('runtime',0.0):.6f}</td>"
                f"<td><div class='perf-data'>{perf_data_str}</div></td>"
                f"</tr>"
            )

        html_content += "</table></div>"

    html_content += "</body></html>"

    report_path = output_dir / "report.html"
    with report_path.open("w", encoding="utf-8") as f:
        f.write(html_content)

    print(f"[INFO] HTML report generated: {report_path}")


if __name__ == "__main__":
    main()
