#!/usr/bin/env python3
"""suno_play.py: press the Suno player's Play button with a real BiDi pointer click (JavaScript play()/click() is refused by
Firefox's autoplay rule without a user gesture). Usage: suno_play.py [play|pause]. Task 89, 10.11.2026."""
import importlib.machinery, importlib.util, os, sys, time, json
ldr = importlib.machinery.SourceFileLoader('firefoxctl', os.path.expanduser('~/.local/bin/firefoxctl'))
spec = importlib.util.spec_from_loader('firefoxctl', ldr); fc = importlib.util.module_from_spec(spec); ldr.exec_module(fc)
want = sys.argv[1] if len(sys.argv) > 1 else 'play'
b = fc.Bidi()
try:
    tab = b.pick('suno.com'); ctx = tab['ctx']
    state = "(()=>{const a=[...document.querySelectorAll('audio')].filter(x=>x.duration>5)[0];return a?(a.paused?'paused':'playing'):'none'})()"
    if b.js(ctx, state) == ('paused' if want == 'play' else 'playing') or b.js(ctx, state) == 'none':
        r = b.js(ctx, """(()=>{const e=document.querySelector('button[aria-label="Playbar: Play button"]');if(!e)return null;
          e.scrollIntoView({block:'center'});const r=e.getBoundingClientRect();return {x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)}})()""")
        if r:
            b.call('input.performActions', {'context': ctx, 'actions': [{'type': 'pointer', 'id': 'm', 'parameters': {'pointerType': 'mouse'},
                'actions': [{'type': 'pointerMove', 'x': r['x'], 'y': r['y'], 'origin': 'viewport'},
                            {'type': 'pointerDown', 'button': 0}, {'type': 'pointerUp', 'button': 0}]}]})
            time.sleep(1.2)
    print(b.js(ctx, state))
finally:
    try: b.close()
    except Exception: pass
