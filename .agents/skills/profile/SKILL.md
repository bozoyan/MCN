---
name: profile
description: Profile CPU, memory, rebuild, rendering, or performance regressions before changing code. Use when the user reports high CPU, slow UI, jank, excessive rebuilds, memory growth, Activity Monitor spikes, Flutter DevTools profiling, VM service sampling, native sample/Instruments evidence, or asks to "profile first" / "不要猜".
---

# Profile

Use this skill to collect runtime evidence before diagnosing performance issues. Do not patch from intuition. First capture a bounded profile while the symptom is happening, then name the concrete hot path.

## Rules

- Do not change code until a profile names the hot function, widget, isolate, thread, or native frame.
- If CPU has already dropped, say the profile would be idle and wait for the user to reproduce.
- Do not use screenshots as profiling evidence unless the user asks or visual state is essential.
- Do not request huge VM sample windows such as `timeOriginMicros=0&timeExtentMicros=999999999999999`; it can hang and mixes idle history with the incident.
- On macOS, avoid `date -Is`; use `date "+%Y-%m-%dT%H:%M:%S%z"`.
- Quote file paths passed to Python via `sys.argv`; do not interpolate unquoted paths into `python -c`.
- If enabling Flutter profiling extensions, turn them off after capture.

## Flutter macOS High CPU Workflow

### 1. Identify the Process

Use Activity Monitor PID if the user provides it. Otherwise:

```bash
pgrep -fl Reveric
ps -p <pid> -o pid,ppid,stat,etime,time,%cpu,%mem,command
```

If `%CPU` is low, do not claim a hot path. Prepare profiling and wait for reproduction.

### 2. Find VM Service URL

For `flutter run -d macos`, the app process has a VM service port and Flutter starts a `development-service` process containing the auth code.

```bash
lsof -Pan -p <app-pid> -iTCP -sTCP:LISTEN
ps -Ao pid,ppid,stat,etime,%cpu,%mem,command | rg "development-service|flutter_tools|Reveric"
```

Look for:

```text
dart development-service --vm-service-uri=http://127.0.0.1:<port>/<auth-code>/ ...
```

Use the app VM service base URL:

```text
BASE="http://127.0.0.1:<port>/<auth-code>"
```

Verify it:

```bash
curl -s "$BASE/getVM"
```

If the response says `missing or invalid authentication code`, the auth code is wrong or missing.

### 3. Identify the Main Isolate

```bash
curl -s "$BASE/getVM"
```

Pick the non-system isolate named `main`, e.g. `isolates/3075428996077979`. URL-encode the slash:

```text
ISO="isolates%2F3075428996077979"
```

### 4. Capture a Bounded Hot Window

Capture only while CPU is high. Use VM timeline timestamps to bound `getCpuSamples`.

```bash
BASE="http://127.0.0.1:<port>/<auth-code>"
ISO="isolates%2F<main-isolate-id>"
PID=<app-pid>
OUT=/tmp/reveric-highcpu

echo "capture_start cpu=$(ps -p "$PID" -o %cpu= | tr -d ' ') at=$(date '+%Y-%m-%dT%H:%M:%S%z')"
curl -s -o "$OUT.vm.json" "$BASE/getVM"
curl -s -o "$OUT.isolate.json" "$BASE/getIsolate?isolateId=$ISO"
curl -s -o "$OUT.timeline_start.json" "$BASE/getVMTimelineMicros"
start=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"]["timestamp"])' "$OUT.timeline_start.json")

sample "$PID" 8 -file "$OUT.native-sample.txt" >/tmp/reveric-sample-command.log 2>&1 &
sample_pid=$!
sleep 8

curl -s -o "$OUT.timeline_end.json" "$BASE/getVMTimelineMicros"
end=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"]["timestamp"])' "$OUT.timeline_end.json")
extent=$((end-start))
curl -s -o "$OUT.cpu-samples.json" "$BASE/getCpuSamples?isolateId=$ISO&timeOriginMicros=$start&timeExtentMicros=$extent"
wait "$sample_pid"
ps -p "$PID" -o pid,stat,etime,time,%cpu,%mem,command > "$OUT.ps.txt"
echo "capture_done start=$start extent=$extent cpu=$(ps -p "$PID" -o %cpu= | tr -d ' ') files=$OUT.*"
```

`sample` gives native/main-thread evidence. `getCpuSamples` gives Dart function evidence. Use both.

## Parse CPU Samples

Summarize Dart samples:

```bash
python3 - /tmp/reveric-highcpu.cpu-samples.json <<'PY'
import json, collections, sys
p = sys.argv[1]
data = json.load(open(p))['result']
funcs = data['functions']
samples = data['samples']
exclusive = collections.Counter()
inclusive = collections.Counter()
tags = collections.Counter()
for s in samples:
    tags[s.get('vmTag', '?')] += 1
    stack = s.get('stack') or []
    if stack:
        exclusive[stack[0]] += 1
        inclusive.update(stack)
def name(i):
    f = funcs[i]
    return f"{f.get('function', {}).get('name')} {f.get('resolvedUrl') or ''}"
print('sampleCount', data.get('sampleCount'), 'period', data.get('samplePeriod'), 'extent', data.get('timeExtentMicros'))
print('tags', tags.most_common())
print('\nTop exclusive:')
for i, _ in exclusive.most_common(40):
    print(exclusive[i], 'excl', inclusive[i], 'incl', name(i))
print('\nFirst app frame per sample:')
first = collections.Counter()
for s in samples:
    for i in s.get('stack') or []:
        url = funcs[i].get('resolvedUrl') or ''
        if 'package:reveric' in url or '/reveric-worktrees/' in url:
            first[i] += 1
            break
for i, _ in first.most_common(60):
    print(first[i], name(i))
PY
```

Read the result like this:

- High `Dart` tag with top `framework.dart updateChild/update/performRebuild`: widget rebuild/update hot path.
- High app frame such as `parseStreamingJson`: business code is driving the rebuilds or CPU work.
- High `RegExp_ExecuteMatch`: look for regex in the app frames.
- High native main-thread frame in `sample`: check paint/raster/layout vs Dart invocation.

## Flutter Build/Rebuild Timeline

Use only after CPU samples show Flutter build/update work. Enable, clear timeline, capture a short window, then disable.

```bash
BASE="http://127.0.0.1:<port>/<auth-code>"
ISO="isolates%2F<main-isolate-id>"
PID=<app-pid>
OUT=/tmp/reveric-builds

curl -s "$BASE/ext.flutter.profileWidgetBuilds?isolateId=$ISO&enabled=true"
curl -s "$BASE/ext.flutter.profileUserWidgetBuilds?isolateId=$ISO&enabled=true"
curl -s "$BASE/ext.flutter.inspector.trackRebuildDirtyWidgets?isolateId=$ISO&enabled=true"
curl -s -o "$OUT.clear.json" "$BASE/clearVMTimeline"
echo "timeline_start cpu=$(ps -p "$PID" -o %cpu= | tr -d ' ')"
sleep 5
curl -s -o "$OUT.timeline.json" "$BASE/getVMTimeline"
ps -p "$PID" -o pid,stat,etime,time,%cpu,%mem,command > "$OUT.ps.txt"
curl -s "$BASE/ext.flutter.profileWidgetBuilds?isolateId=$ISO&enabled=false"
curl -s "$BASE/ext.flutter.profileUserWidgetBuilds?isolateId=$ISO&enabled=false"
curl -s "$BASE/ext.flutter.inspector.trackRebuildDirtyWidgets?isolateId=$ISO&enabled=false"
```

Summarize widget event counts and durations:

```bash
python3 - /tmp/reveric-builds.timeline.json <<'PY'
import json, collections, sys
p = sys.argv[1]
events = json.load(open(p))['result']['traceEvents']
print('events', len(events))
print('\nTop event names:')
for name, count in collections.Counter(e.get('name', '') for e in events).most_common(80):
    print(count, name)
stacks = collections.defaultdict(list)
summary = collections.defaultdict(lambda: [0, 0, 0])
for e in events:
    key = (e.get('tid'), e.get('name', ''))
    if e.get('ph') == 'B':
        stacks[key].append(e.get('ts'))
    elif e.get('ph') == 'E' and stacks[key]:
        dur = e.get('ts') - stacks[key].pop()
        row = summary[e.get('name', '')]
        row[0] += 1
        row[1] += dur
        row[2] = max(row[2], dur)
print('\nTop total durations:')
for name, (count, total, max_dur) in sorted(summary.items(), key=lambda kv: kv[1][1], reverse=True)[:100]:
    print(f'{total:>9}us total {count:>5}x avg={total/count:>7.1f}us max={max_dur:>7}us {name}')
PY
```

Use build profiling to identify rebuild fan-out. Example interpretation: a few `NovelEditorPage` builds with large duration means root-level rebuild is expensive; many `SvgPicture`/`VectorGraphic`/`RevericIcon` events means icon-heavy UI is being rebuilt repeatedly.

## Outcome Format

Report evidence before recommendations:

```text
Profile window:     [duration, pid, starting/ending CPU]
Dart samples:       [sampleCount, dominant tags]
Native sample:      [main thread / raster / IO / other dominant stack]
Hot app frames:     [function + file]
Build timeline:     [top widgets by count/duration, if captured]
Root hypothesis:    [specific path that explains all symptoms]
Next code target:   [file/function to inspect or change]
Artifacts:          [/tmp/... files]
```

Only propose a fix after the profile and source trace agree.
