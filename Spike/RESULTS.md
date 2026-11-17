# Phase 0 Spike Results (plan Step 1)

Status: **incomplete — automated AX/AE checks blocked by missing permissions in the agent run (see "Run log").**
Chosen strategy: _not yet decided_ (decision rule: P1 → P2 (with P1 fallback) → stop-and-ask; plan §2 D3).
Fallback: _not yet decided_.

## How to run

Build everything: `make -C Spike spike` (or `make spike` from the repo root).

| Tool | Command | Covers |
|---|---|---|
| HideSpike | `Spike/build/HideSpike perm` | permission status + process chain |
| | `Spike/build/HideSpike config` | detected matrix cell (displays / Dock / Stage Manager) |
| | `Spike/build/HideSpike s2` | S2 identity + `optionOnScreenAboveWindow` |
| | `Spike/build/HideSpike probe` | P1 park candidates (br, bl, b, r, l): requested vs actual frame, sliver area |
| | `Spike/build/HideSpike run --strategy all` | automated H-1, H-2 (geometry), H-3, H-4, H-6, show/hide latency for P1, P2, P3 |
| | `Spike/build/HideSpike manual --check H-2 --strategy p1` | guided screenshot check (also H-5, H-7, H-8) |
| | `Spike/build/HideSpike h9 --strategy p1 --duration 120` | display unplug/re-plug/rearrange while hidden |
| | `Spike/build/HideSpike h10 --strategy p1` | Finder relaunch while hidden — **you** run `killall Finder` in another terminal when prompted |
| HotkeySpike | `Spike/build/HotkeySpike carbon --listen 10` | S3(a) |
| | `Spike/build/HotkeySpike tap --seconds 10` | S3(b) (press Option+F in TextEdit during the window) |
| SpikeApp | `make -C Spike run-spike-app` (opens `Spike/build/FinderVisorSpike.app`) | S3(c), S3(d), S4 — log in `~/Library/Logs/FinderVisorSpike.log` |
| frame-dump | `make frame-dump` | table of Finder AX windows + CGWindowList entries |

Prerequisites: the terminal app running HideSpike/HotkeySpike needs **Accessibility** and **Automation → Finder**
(System Settings ▸ Privacy & Security). FinderVisorSpike.app requests its own grants (buttons in its window).
FinderVisorSpike.app is ad-hoc signed unless a code-signing identity exists (`SPIKE_SIGN_IDENTITY=...` overrides),
so its TCC grants reset on every rebuild.

Pass thresholds: H-1 ≤ 100 ms median of 10; show/hide ≤ 150 ms median of 10; H-2 visible area = 0 (any sliver = fail);
H-6 frame ±2 pt and Visor is Finder's key window; create ≤ 1.0 s.
Cell legend: `pass (value)` / `FAIL (value)` / `needs user` / `blocked (reason)`.

## D3 matrix

### P1 — off-screen park (AXPosition outside the display union)

| Display | Dock | Stage Mgr | H-1 | H-2 | H-3 | H-4 | H-5 | H-6 | H-7 | H-8 | H-9 | H-10 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **1 display** (current, Dock autohide on) | bottom | off | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) |
| 1 display | bottom | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 1 display | left | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 1 display | left | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary left | bottom | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary left | bottom | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary left | left | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary left | left | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary above | bottom | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary above | bottom | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary above | left | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary above | left | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |

### P2 — conditional Finder app-hide (P1 fallback when other Finder windows exist)

| Display | Dock | Stage Mgr | H-1 | H-2 | H-3 | H-4 | H-5 | H-6 | H-7 | H-8 | H-9 | H-10 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **1 display** (current, Dock autohide on) | bottom | off | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) |
| 1 display | bottom | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 1 display | left | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 1 display | left | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary left | bottom | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary left | bottom | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary left | left | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary left | left | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary above | bottom | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary above | bottom | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary above | left | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary above | left | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |

### P3 — AXMinimized (information only; animation contradicts "instant")

| Display | Dock | Stage Mgr | H-1 | H-2 | H-3 | H-4 | H-5 | H-6 | H-7 | H-8 | H-9 | H-10 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **1 display** (current, Dock autohide on) | bottom | off | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) | blocked (no AX/AE grant) |
| 1 display | bottom | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 1 display | left | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 1 display | left | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary left | bottom | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary left | bottom | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary left | left | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary left | left | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary above | bottom | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary above | bottom | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary above | left | off | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |
| 2 displays, secondary above | left | on | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user | needs user |

## Show/hide latency (median of 10, target ≤ 150 ms; create ≤ 1.0 s)

| Cell | Strategy | Create ms | Show median ms | Hide median ms (incl. focus return) | H-1 median ms |
|---|---|---|---|---|---|
| 1 display / bottom / off | P1 | blocked | blocked | blocked | blocked |
| 1 display / bottom / off | P2 | blocked | blocked | blocked | blocked |
| 1 display / bottom / off | P3 | blocked | blocked | blocked | blocked |
| other cells | all | needs user | needs user | needs user | needs user |

## P1 park probe (`HideSpike probe`)

| Cell | Edge | Requested | Actual AX | Visible area pt² |
|---|---|---|---|---|
| 1 display / bottom / off | br, bl, b, r, l | blocked (no AX grant) | | |

## S2 — identity

| Question | Result |
|---|---|
| Finder AE `id` == `kCGWindowNumber`? | needs user (`HideSpike s2`) |
| `optionOnScreenAboveWindow` returns the overlapping window and not the Visor? | needs user (`HideSpike s2`) |
| Finder tabs are separate AE windows / AX element or CGWindowID changes when tabs are added? | needs user (`S2-tabs` line of `HideSpike run`) |

## S3 — hotkeys

| Check | Context | Result |
|---|---|---|
| S3(a) Carbon `RegisterEventHotKey` Option+F | CLI (non-terminal host app) | **registration returned noErr (0)** — also Option+Shift+F and Cmd+Option+F. Delivery not yet tested: run `HotkeySpike carbon --listen 10` and press the combos. The plan expected rejection on macOS 15+; if delivery also works, D4's rationale for rejecting Carbon weakens but option B (single active tap) still needs the tap for double-tap. |
| S3(b) active tap swallows Option+F in TextEdit | CLI | `tapCreated=false` in the agent run (host lacks Accessibility; `listenEventAccess=false`). needs user: `HotkeySpike tap --seconds 10` from a terminal with Accessibility. |
| S3(c) tap created after grant works without relaunch | FinderVisorSpike.app | needs user ("S3(c/d) Start tap" then grant Accessibility while it retries) |
| S3(d) Input Monitoring required in addition to Accessibility? | FinderVisorSpike.app | needs user (record `inputMonitoring=` in the S3(c)/S3(d) RESULT lines) |

## S4 — focus return (FinderVisorSpike.app)

| Method | Returned? | ms | ≤ 150 ms |
|---|---|---|---|
| AX `kAXFrontmostAttribute` | needs user | | |
| `NSRunningApplication.activate()` | needs user | | |
| `yieldActivation(to:)` + `activate(from:)` | needs user | | |
| Return target = Finder: previous window re-raised | needs user | | |

## Run log (agent run, 2026-11-17)

- Build: `make -C Spike spike` → all four products built with `-swift-version 6`, 0 warnings, 0 errors.
  `FinderVisorSpike.app` signed **ad-hoc** (no code-signing identity in the keychain), hardened runtime,
  `com.apple.security.automation.apple-events` entitlement, `LSUIElement = true`.
- Detected configuration: 1 display `0,0 1512x982`, Dock bottom (autohide on), Stage Manager off.
- Permissions (`HideSpike perm`): `axTrusted=false`, `aeFinder=notDetermined (-1744)`, `listenEvent=false`.
  Responsible process chain: `HideSpike` → `/bin/zsh` → a GUI host app without Accessibility or Automation grants (TCC host).
  Per instructions no TCC workaround was attempted and no AX/AE check was run; the Apple Events consent prompt was not triggered.
- Ran without permissions: `HotkeySpike carbon` (S3(a) registration), `HotkeySpike tap --seconds 3` (tap not created; nothing installed),
  `frame-dump` (CG part only).
- Observation for P2: Finder owns several layer-0 CG windows that are not browser windows (four `1512x33` strips at 0,0,
  one `64x64`, plus a layer-3 alpha-0 window). P2's "Visor is the sole Finder window" test therefore ignores layer-0 windows
  smaller than 200×150 or with alpha 0; this heuristic needs confirming in the matrix runs.

## Decision

_Pending matrix results. Stop-and-ask points (plan D3): (a) only failure is an H-2 sliver; (b) only P3 passes; (c) nothing passes._

---

## Decision (2026-11-17, user-approved stop-and-ask)

Measured on: single display 1512x982, Dock bottom (autohide), Stage Manager off. Log: `Spike/logs/auto-20261117-141047.log`.

| Strategy | H-1 hide med | H-2 visible area | H-3 | H-4 | H-6 | show med | Verdict |
|---|---|---|---|---|---|---|---|
| P1 off-screen park | never hidden (timeouts 10/10) | 2080 pt² (40x52 corner; 78624 pt² bottom edge) | pass | pass | pass | 13.9 ms | FAIL H-2: macOS clamps windows on-screen (stop-and-ask a) |
| P2 app-hide (+P1 fallback) | 31.8 ms (only-window path) | 2080 pt² on fallback path | pass | pass | FAIL 10/30 key | timeouts | FAIL |
| P3 AXMinimized | 527.5 ms | 0 | pass | pass | pass | 586.1 ms | passes all except "instant" |

Other findings: Finder AE window id == CGWindowID (S2 pass). Each Finder tab is a separate AE window and switching tabs changes the AX element and CGWindowID (Visor identity must follow the active tab). Carbon RegisterEventHotKey(Option+F) returns noErr on macOS 27; delivery untested (no key presses during the run). Active CGEventTap creation succeeds once Accessibility is granted; swallow test untested.

**Chosen strategy: P3 (minimize).** The user accepted the ~0.5 s minimize/restore animation and Dock thumbnail. The 150 ms latency targets for hide/show are waived for P3. P1/P2 are not shipped. Remaining manual checks (H-5, H-7, H-8, H-9, H-10, S3b swallow, S3c/S3d, S4) move to Step 5/§7 QA against the real app.
