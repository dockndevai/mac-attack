# Security Policy

## Reporting a vulnerability

Please report security issues privately through
[GitHub Security Advisories](https://github.com/dockndevai/mac-attack/security/advisories/new),
or by email to ankitcs17071993@gmail.com.

Please do not open a public issue for a vulnerability. Expect an initial response within seven days.

## Scope

Mac Attack runs entirely on your Mac. The things worth reporting:

- **The local HTTP endpoints.** The camera helper serves anonymous person boxes on
  `127.0.0.1:8778`, and the Laya sidecar answers on `127.0.0.1:8777`. Both bind to loopback only.
  Anything that makes them reachable off-device, or that leaks data beyond the documented fields,
  is in scope.
- **The camera lease.** The helper must keep the camera off unless the screensaver is on screen.
  A way to keep the camera running, or to start it without the screensaver, is in scope.
- **Privacy guarantees.** Mac Attack must never write camera frames to disk, perform face
  recognition, or send images anywhere. Any path that breaks this is in scope.
- **The launchd agent and the sidecar process** (`local.macattack.helper`): privilege issues,
  unsafe paths, or ways to make either run unintended code.

Out of scope: the Gatekeeper warning on unsigned builds (known and documented), and the behaviour
of the Laya model itself (upstream, Apache-2.0).

## What the app does with your data

- Apple's Vision framework produces body rectangles. No face recognition, no identification.
- Camera frames are processed in memory and released. Nothing is written to disk, ever.
- Only abstract state crosses any boundary: `{id, x, y, width, height, movement, dwell}`.
- There is no telemetry, no account, and no network access beyond `127.0.0.1` — the model
  checkpoint download during optional setup is the single exception, and it comes from Hugging Face.

## Supported versions

The latest release is supported. Older releases are not patched.
