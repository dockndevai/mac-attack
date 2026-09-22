---
title: I built a macOS screensaver that throws rubber ducks at you, directed by a local model
published: false
tags: macos, ai, swift, showdev
---

Mac Attack watches the room with the Mac camera, turns each person into a cartoon character, and
fires harmless toy effects at them: bubbles, rubber ducks, tomatoes, confetti. It runs as a normal
app and as a real macOS screensaver.

Everything stays on the Mac. Apple's Vision framework produces body rectangles only (no face
recognition), frames are processed and released, and nothing is uploaded.

Download + code: https://github.com/dockndevai/mac-attack

## The experiment

The point wasn't the ducks. It was this: can a small, fast decision model make a game feel *alive*?

The director is [Laya](https://huggingface.co/convaiinnovations/laya), a non-autoregressive
typed-decision model. You hand it a state plus typed questions (choice / score / yes-no) and it
answers all of them in **one forward pass** with calibrated probabilities — about 340 ms on an M2
Pro through a local sidecar.

Laya never sees pixels. It gets one sentence:

> "2 humans in view. person-1 is the frog on the left, just arrived, moving left. person-2 has been
> standing still for 12s. Last event: duck rain 4s ago."

That sentence is the entire interface between vision and behaviour.

## Three things I measured

### 1. Sampling beats argmax

Taking the model's top answer made the game repetitive. Sampling from its calibrated distribution
made it feel alive: the same scene plays out differently each time, while still following the
model's taste. "Chaos mode" is literally a higher sampling temperature.

Calibration stops being a number on a benchmark and becomes something you build on.

### 2. Policy belongs in code, not in the prompt

The game got boring fast: it fired the same stunt every time. Measuring showed why — for a single
stationary person, Laya put **86-95%** of its probability on one option ("surprise"), every single
time.

I rewrote the question to describe that option as rare. It barely moved: 86% afterwards.

What fixed it was policy in the sampling code:

- a just-used effect drops to 8% weight and recovers over the next few events
- stunts get cooldowns (5 events for one, 3 for another)
- the same effect can never run three times in a row

Result: from ~90% of decisions down to 12%, measured live over a run with 8 different effects.

### 3. Measure the model you are actually running

One question with 11 options came back 100% confident every single time. That option count ships
with an uncalibrated temperature in this checkpoint — the probabilities saturate. Splitting it into
questions with five options or fewer brought the distributions back to life.

Related: passing a text summary instead of raw JSON **halved latency**, because the state is
re-read once per question.

## The part macOS refused

Making it a real screensaver was the hard bit.

**A screensaver can never use the camera.** A `.saver` bundle runs inside Apple's sandboxed
`legacyScreenSaver` host, so the camera request is attributed to that host — which has no camera
permission. It is denied instantly, without ever showing a prompt. Anything the screensaver spawns
inherits that sandbox, and `open` is blocked too.

The architecture that works:

```
MacAttack.app --helper        (launchd agent, normal user session)
  |- camera + Vision          -> anonymous person boxes only
  |- Laya sidecar             -> 127.0.0.1:8777
  \- serves 127.0.0.1:8778    -> { camera, tracks[ id,x,y,w,h,vx,vy,movement,dwell ] }
                                        |   (no images, ever)
MacAttack.saver               <- polls 10x/s, runs the game engine, renders, asks Laya
```

The helper keeps the camera **off** until the screensaver actually asks for people, and switches it
off again seconds after it stops.

Other things macOS says no to: the lock/login screen only runs Apple's own screensavers, and there
is no API to select someone's screensaver for them.

## Reliability

Laya is never in the render loop. Decisions are event-driven, at most one in flight, and bounded by
a 2-second timeout — if the model is slow, loading or missing, a local random director takes over
and the game never stalls. A 40-minute soak with the model killed mid-run and later frozen with
SIGSTOP produced no crash and no memory growth.

## Try it

https://github.com/dockndevai/mac-attack/releases/latest — Mac, unsigned build, so Gatekeeper will warn (right-click, Open).

Source, architecture notes and the full list of what worked and what didn't: https://github.com/dockndevai/mac-attack
