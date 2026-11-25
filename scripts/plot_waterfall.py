#!/usr/bin/env python3
"""Redraws the A/B waterfall on the open "DBS · Redesign" canvas from the latest run of each flow.

  scripts/plot_waterfall.py                  latest 3x and 1x phone runs, on one time scale
  scripts/plot_waterfall.py --multiplier 3   latest 3x runs only
  scripts/plot_waterfall.py --trace a.json --trace b.json

Needs the services up and the canvas open in Enso. It removes only elements it drew itself,
whose ids it keeps in ~/.paynow-waterfall.json.
"""
import argparse, json, os, pathlib, subprocess, sys, time, urllib.error, urllib.request

VAULT = os.environ.get("ENSO_VAULT_ID", "FA761D73-0EBB-4D02-BB48-6782CC00B1B4")
CANVAS = os.environ.get("ENSO_CANVAS_ID", "C6B3260B-3098-4CA8-BBD3-E53634AE7C2B")
STATE = pathlib.Path.home() / ".paynow-waterfall.json"
COLORS = {"ui": "blue", "biometric": "orange", "backend": "green", "user": "gray", "screen": "purple"}
FLOWS = [("sequential", "DBS Sequential", "orange"), ("router", "Intent Router", "teal")]
LEFT, TOP, WIDTH, BAR_X, BAR_W, ROW = 24050, 28100, 3580, 24720, 2850, 44


def enso(*args, stdin=None):
    run = subprocess.run(["enso", "--vault-id", VAULT, "--canvas-id", CANVAS, *args], input=stdin, capture_output=True, text=True)
    try:
        out = json.loads(run.stdout or run.stderr)
    except json.JSONDecodeError:
        sys.exit(f"enso {' '.join(args)}: {run.stderr or run.stdout}")
    if not out.get("ok"):
        sys.exit(f"enso {' '.join(args)}: {json.dumps(out.get('error'))}")
    return out["data"]


def apply(**spec):
    data = enso("canvas", "apply", "--json", "-", stdin=json.dumps({"canvas": "current", **spec}))
    return data["results"]


def ids_in(value):
    if isinstance(value, dict):
        found = {value["id"]} if isinstance(value.get("id"), str) else set()
        return found.union(*(ids_in(v) for v in value.values()))
    return set().union(*(ids_in(v) for v in value)) if isinstance(value, list) else set()


def latest(flow, multiplier):
    url = f"http://localhost:8081/auth/traces/latest?flow={flow}&multiplier={multiplier}"
    try:
        return json.load(urllib.request.urlopen(url, timeout=5))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            sys.exit(f"No {flow} run at {multiplier}x yet. Record one on the phone first.")
        raise


def union(spans):
    total, edge = 0.0, float("-inf")
    for s in sorted(spans, key=lambda s: s["start_ms"]):
        total += max(0.0, s["end_ms"] - max(edge, s["start_ms"]))
        edge = max(edge, s["end_ms"])
    return total


def seconds(ms):
    return f"{ms / 1000:.2f} s"


def summary(trace):
    path = [s for s in trace["spans"] if s["critical_path"]]
    parts = {k: union([s for s in path if s["kind"] == k]) for k in COLORS}
    machine = union([s for s in path if s["kind"] != "user"])
    pay = next((s["start_ms"] for s in path if s["name"] == "POST /payments/paynow"), float("inf"))
    form = union([s for s in path if s["kind"] != "user" and s["end_ms"] <= pay])
    return machine, parts, form


def main():
    args = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    args.add_argument("--multiplier", type=int, choices=[1, 3], help="plot one speed only")
    args.add_argument("--trace", action="append", help="plot this file instead of the stored run")
    args.add_argument("--pace", type=float, default=0, help="seconds between elements, to watch it draw")
    opts = args.parse_args()
    if opts.trace:
        traces = {t["flow"]: t for t in (json.loads(pathlib.Path(p).read_text()) for p in opts.trace)}
        if set(traces) != {"sequential", "router"}:
            sys.exit("Pass one sequential and one router trace.")
        groups = [traces]
    else:
        groups = [{flow: latest(flow, m) for flow, _, _ in FLOWS} for m in ([opts.multiplier] if opts.multiplier else [3, 1])]
    for traces in groups:
        if len({(t["multiplier"], t["source"], t["biometric_mocked"]) for t in traces.values()}) != 1:
            sys.exit("The two runs differ in multiplier, source or Face ID, so they aren't comparable.")

    old = json.loads(STATE.read_text()) if STATE.exists() else {"marks": [], "lines": [], "regions": []}
    live = ids_in(enso("mark", "list")) | ids_in(enso("primitive", "list"))
    prims = [dict(kind=k, mode="remove", id=i) for k, key in (("line", "lines"), ("region", "regions")) for i in old[key] if i in live]
    marks = [dict(mode="remove", id=i) for i in old["marks"] if i in live]
    if prims or marks:
        apply(primitives=prims, marks=marks)
        time.sleep(opts.pace * 5)

    drawn = {"marks": [], "lines": [], "regions": []}

    def draw(key, items):
        for item in items:
            result = apply(**{"marks" if key == "marks" else "primitives": [item]})
            drawn[key] += [r["id"] for r in result]
            STATE.write_text(json.dumps(drawn))
            time.sleep(opts.pace)

    def mark(text, x, y, width, size):
        return dict(mode="create", text=text, x=x, y=y, width=width, fontSize=size)

    end = max(s["end_ms"] for traces in groups for t in traces.values() for s in t["spans"])
    scale = BAR_W / end
    draw("marks", [mark("Blue: UI. Orange: biometric. Green: backend network. Gray: waiting for the person. Purple: loading screen shown over "
                        "the work it waits for. Dashed: off the critical path. Every bar uses the same time scale. "
                        + next(iter(groups[0].values())).get("note", ""), LEFT, TOP, 3500, 17)])
    y = TOP + 50
    for traces in groups:
        run = next(iter(traces.values()))
        speed = f"{run['multiplier']}x"
        totals = {flow: summary(t) for flow, t in traces.items()}
        (seq, _, seq_form), (router, _, router_form) = totals["sequential"], totals["router"]
        draw("marks", [mark(f"{speed} on {run['source']}. Tap to a form ready to pay: DBS Sequential {seconds(seq_form)}, Intent Router {seconds(router_form)}. "
                            f"To Sent: {seconds(seq)} against {seconds(router)}. The person's own time is left out.", LEFT, y, 3500, 24)])
        y += 60
        for flow, title, color in FLOWS:
            trace = traces[flow]
            height = 100 + ROW * len(trace["spans"])
            draw("regions", [dict(kind="region", mode="create", title=f"Waterfall · {speed} · {title}", x=LEFT + WIDTH / 2, y=y + height / 2,
                                  width=WIDTH, height=height, color=color, fillOpacity=0.06)])
            machine, parts, form = totals[flow]
            draw("marks", [mark(f"Form ready {seconds(form)}. Sent {seconds(machine)}: UI {seconds(parts['ui'])}, biometric {seconds(parts['biometric'])}, "
                                f"backend {seconds(parts['backend'])}, overlaps counted once in the total. Person {seconds(parts['user'])}.",
                                LEFT + 50, y + 34, 2400, 17)])
            for i, span in enumerate(trace["spans"]):
                row = y + 90 + i * ROW
                length = (span["end_ms"] - span["start_ms"]) * scale
                stroke = max(2, min(24 if span["critical_path"] else 12 if span["kind"] == "screen" else 8, length))
                x1 = BAR_X + span["start_ms"] * scale
                # Line caps are round and reach half a stroke past each end, so the line is drawn that much shorter.
                line = dict(kind="line", mode="create", x1=x1 + stroke / 2, y1=row, x2=max(x1 + stroke / 2 + 0.5, x1 + length - stroke / 2),
                            y2=row, color=COLORS[span["kind"]], strokeWidth=stroke)
                if not span["critical_path"] and span["kind"] != "screen":
                    line["lineStyle"] = "dashed"
                off = " (screen)" if span["kind"] == "screen" else "" if span["critical_path"] else ", off path"
                draw("marks", [mark(f"{span['name']}{off} · {round(span['end_ms'] - span['start_ms'])} ms", LEFT + 50, row - 12, 600, 17)])
                draw("lines", [line])
            y += height + 40
            print(f"{speed} {title}: form ready {seconds(form)}, sent {seconds(machine)}", {k: seconds(v) for k, v in parts.items()})
        y += 30


main()
