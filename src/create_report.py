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


def build_report_html(compiled_results, output_dir):
    """
    Generate an HTML report from compiled benchmark results.

    compiled_results: list of benchmark dicts
    output_file: path to write the HTML report
    """

    html_content = f"""
<html>
<head>
    <title>amd-secure-bench Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 40px; }}
        h1 {{ text-align: center; }}
        h2 {{ border-left: 5px solid #007acc; padding-left: 10px; margin-top: 40px; }}
        table {{ border-collapse: collapse; width: 100%; margin-bottom: 20px; font-size: 13px; table-layout: fixed; }}
        table th, table td {{ border: 1px solid #bbb; padding: 4px 6px; line-height: 1.2; }}
        table th {{ background: #007acc; color: white; }}
        .meta {{ background: #eef6ff; padding: 10px; border-radius: 4px; margin-bottom: 20px; }}
        .perf-data {{ font-family: monospace; white-space: pre; background: #f2f2f2; padding: 4px 6px; border-radius: 4px; }}
        .details {{ display: none; margin-top: 10px; }}
        .show-btn {{ background: #007acc; color: white; border: none; padding: 6px 10px; border-radius: 4px; cursor: pointer; margin-bottom: 10px; }}
        .show-btn:hover {{ background: #005c99; }}
    </style>
    <script>
        function toggleDetails(id) {{
            const el = document.getElementById(id);
            el.style.display = (el.style.display === "none" || el.style.display === "") ? "block" : "none";
        }}
    </script>
</head>
<body>
    <h1>amd-secure-bench Benchmark Report</h1>
"""

    for i, b in enumerate(compiled_results):
        b_infos = b.get("b_infos", {})
        html_content += (
            f"<h2>Benchmark: {html.escape(b_infos.get('source', 'Unknown'))}</h2>"
        )

        # Meta information
        html_content += "<div class='meta'>"
        html_content += f"<b>Compiler Flags:</b> {html.escape(' '.join(b_infos.get('compiler_flags', [])))}<br>"
        html_content += f"<b>Runs:</b> {b_infos.get('runs', 0)} &nbsp;&nbsp; <b>Warmup:</b> {b_infos.get('warmup_runs', 0)}<br>"
        html_content += f"<b>Args:</b> {html.escape(' '.join(b_infos.get('args', []) or ['None']))}<br>"
        html_content += "</div>"

        # Runtime summary
        runtimes = [r.get("runtime", 0.0) for r in b.get("results", [])]
        if runtimes:
            runtime_avg = sum(runtimes) / len(runtimes)
            runtime_min = min(runtimes)
            runtime_max = max(runtimes)
            runtime_std = statistics.stdev(runtimes) if len(runtimes) > 1 else 0.0
        else:
            runtime_avg = runtime_min = runtime_max = runtime_std = 0.0

        html_content += "<h3>Runtime Summary</h3>"
        html_content += f"""
        <table>
            <tr><th>Average (s)</th><th>Min (s)</th><th>Max (s)</th><th>Stddev (s)</th></tr>
            <tr>
                <td>{runtime_avg:.6f}</td>
                <td>{runtime_min:.6f}</td>
                <td>{runtime_max:.6f}</td>
                <td>{runtime_std:.6f}</td>
            </tr>
        </table>
        """

        # Performance counter summary
        agg_perf = aggregate_perf_results(b.get("results", []))
        if agg_perf:
            html_content += "<h3>Performance Counter Summary</h3>"
            html_content += (
                "<table><tr><th>Event</th><th>Average</th><th>Min</th><th>Max</th></tr>"
            )
            for event, stats in agg_perf.items():
                html_content += f"""
                <tr>
                    <td>{html.escape(event)}</td>
                    <td>{stats.get('avg', 0.0):.2f}</td>
                    <td>{stats.get('min', 0.0):.2f}</td>
                    <td>{stats.get('max', 0.0):.2f}</td>
                </tr>
                """
            html_content += "</table>"

        # Per-run details
        detail_id = f"details_{i}"
        html_content += f"<button class='show-btn' onclick=\"toggleDetails('{detail_id}')\">Show per-run details</button>"
        html_content += f"<div class='details' id='{detail_id}'>"

        html_content += "<h3>Per-Run Results</h3><table><tr><th>Iteration</th><th>Runtime (s)</th><th>Perf Counters</th></tr>"
        for r in b.get("results", []):
            perf_data_str = "<br>".join(
                f"{k}: {v}" for k, v in r.get("perf", {}).items()
            )
            html_content += f"""
            <tr>
                <td>{r.get('iteration', 0)}</td>
                <td>{r.get('runtime', 0.0):.6f}</td>
                <td><div class="perf-data">{perf_data_str}</div></td>
            </tr>
            """
        html_content += "</table></div>"

    html_content += "</body></html>"

    report_path = output_dir / "report.html"
    with report_path.open("w") as f:
        f.write(html_content)

    print(f"[INFO] HTML report generated: {output_dir}/report.html")


if __name__ == "__main__":
    main()
