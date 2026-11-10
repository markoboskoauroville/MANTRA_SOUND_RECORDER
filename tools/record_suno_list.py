#!/usr/bin/env python3
"""record_suno_list.py: record Suno songs one by one through the Star API functions of Sound Recorder (Mantra) and check each take:
duration = Suno's +-1 s, peak, and no speech in the first and last 30 s (Whisper at :8837/hear on checking copies only).
Usage: record_suno_list.py OUTDIR name=url=seconds ...   (a job already running is waited for first). Task 89, 10.11.2026."""
import json, os, subprocess, sys, time, urllib.request

def fn(name, args=None):
    r = subprocess.run(['star', 'fn', 'sound recorder', name] + ([json.dumps(args)] if args is not None else []), capture_output=True, text=True)
    return json.loads(r.stdout)

def wait():
    while True:
        s = fn('record.status')
        if not s.get('recording') and s['job'].get('state') != 'recording':
            return s
        time.sleep(5)

def hear(wav, start, dur):
    tmp = '/tmp/_chk_%d.wav' % start
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', str(start), '-t', str(dur), '-i', wav, '-ac', '1', '-ar', '16000', tmp], check=True)
    req = urllib.request.Request('http://127.0.0.1:8837/hear', open(tmp, 'rb').read(), {'Content-Type': 'audio/wav'})
    try: return json.loads(urllib.request.urlopen(req, timeout=120).read()).get('text', '').strip()
    except Exception as e: return 'hear failed: %s' % e

out = os.path.expanduser(sys.argv[1]); items = [a.split('=', 2) for a in sys.argv[2:]]
for name, url, secs in items:
    wav = os.path.join(out, name + '.wav')
    s = wait()
    if s['job'].get('file') != wav or s['job'].get('state') != 'done':
        r = fn('record.suno', {'out': wav, 'url': url}); print(name, r, flush=True)
        if not r.get('ok'): sys.exit(1)
        time.sleep(3); s = wait()
    j = s['job']; print(name, json.dumps(j), flush=True)
    ok = j.get('state') == 'done' and abs(j['seconds'] - float(secs)) <= 1.0
    total = j.get('seconds', 0)
    first = hear(wav, 0, 30); last = hear(wav, max(0, int(total) - 30), 30)
    print('  duration %.2f vs %s: %s; peak %s dBFS; first 30 s speech: %r; last 30 s speech: %r' % (total, secs, 'OK' if ok else 'MISMATCH', j.get('peak_dbfs'), first, last), flush=True)
print('ALL DONE')
