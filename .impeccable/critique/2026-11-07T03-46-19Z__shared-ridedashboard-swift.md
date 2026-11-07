---
target: Ride dashboard and Start/End flow with SwiftUI specialist review
total_score: 28
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 1
timestamp: 2026-11-07T03-46-19Z
slug: shared-ridedashboard-swift
---
Method: dual-agent (A: Design assessment A; B: Evidence assessment B; synchronous tool results did not expose agent IDs).

## Verdict

ScooterLog feels native and product-specific, not like a generic dashboard. Preserve the neon scooter identity and system tab bar. The biggest opportunity is making recording state and recovery as prominent as Start/End.

Scope: Shared/RideDashboard.swift, its weather section, and idle/active Start/End flows. Source reviewed; the earlier iPhone screenshot was visually inspected during synthesis. Active, Watch, landscape, and VoiceOver interactions were not exercised in this run. Scores are provisional, not certification.

## Design health: 28/40 — Good

| Heuristic | Score | Key issue |
|---|---:|---|
| System status | 2 | Remote paused rides show a recording icon in the accessory. |
| Real-world language | 3 | Plain actions; recording-owner terminology is technical. |
| User control | 3 | Cancel and Resume exist; offline End needs guidance. |
| Consistency | 3 | Native controls; accessory status disagrees with dashboard status. |
| Error prevention | 3 | End confirmation; disconnected-start warning is detached from Start. |
| Recognition | 3 | Labeled tabs and instruments; device caveat is not always visible. |
| Efficiency | 3 | Persistent action and shortcuts reduce navigation. |
| Minimalism | 3 | Strong hierarchy; secondary ride statistics are densely grouped. |
| Error recovery | 3 | Explicit errors and retries; disabled remote End lacks nearby recovery. |
| Help | 2 | Useful caveats, but little contextual guidance at blocked actions. |

## What's working

- Start/End stays available without making an action masquerade as a tab.
- Neon artwork establishes a distinct scooter identity; native materials keep navigation familiar.
- Labeled instruments, recovery controls, weather timestamps, and road-condition caveats support trust.

## Priority issues

**P1 — The accessory can misrepresent paused remote recording.** Shared/RideDashboard.swift:590–602 uses the recording icon whenever isRemote is true, while line 531 correctly recognizes peer.recording == false as paused. VoiceOver only gets “Ride in progress,” duration, and distance. A rider could believe recording is running when it is not. Derive the accessory icon and accessible status from the same recording state as the dashboard; distinguish offline/stale peer reports. Suggested command: /impeccable harden.

**P2 — Offline End is disabled without a nearby next step.** Shared/RideDashboard.swift:645–651 disables End for an unreachable owner; the explanation lives elsewhere at 530–534. From History or Saved places, the user sees an unavailable action without its reason. Preserve the protective disable, but show “Recording device offline” and explain that the ride must be ended on that device, with a path back to ride status. Suggested command: /impeccable clarify.

**P2 — The custom environment action still contains a closure.** Shared/RideDashboard.swift:79–81 and 1175–1187 wrap a closure inside SetRideBarHiddenAction. The supplied SwiftUI specialist's references/environment.md explicitly says this wrapper does not solve environment comparison: the closure remains incomparable, so readers can invalidate unnecessarily on dashboard updates. Replace the captured behavior with a stable model reference or data-backed action whose method updates the hide reasons, without a stored closure. This is a verified best-practice violation, not a measured frame-drop or compile failure. Suggested command: /impeccable optimize.

## SwiftUI specialist review

Read .agents/swiftui-specialist/SKILL.md and its environment, structure, dataflow, and ForEach guidance. The environment finding above is the most concrete code-quality issue. The dashboard also owns multiple ObservableObject subscriptions and factors substantial sections as computed properties, which do not create independent invalidation boundaries. Extract measured hot sections into View structs with narrow inputs before undertaking a broad observation migration. No performance trace was collected, so do not characterize this as proven jank. Completed-ride rows use ride identity, a positive pattern. Map-segment offset identity warrants a separate check if those segments are edited/reordered; it is not established as a user-facing defect here.

## Cognitive load and emotional journey

The four tabs are appropriate top-level choices, not excessive navigation. Start is visually dominant. The idle screenshot gives substantial space to artwork and cautions; the active source includes five secondary statistics alongside core instruments. This is a candidate for progressive disclosure, not a proven clipping defect. The emotional weak point is encountering disabled End after an otherwise reassuring recording flow.

## Persona red flags

- First-time rider: “Start ride here” can be reached from every tab, while the one-device warning is only in the Ride section (286–288). A known peer ride is already blocked by the controller; this is a visibility problem, not proof of missing duplicate-start protection.
- Distracted rider: paused/offline recording status should be readable beside the persistent action, without navigating elsewhere.
- VoiceOver user: the accessory announces elapsed time and distance but omits paused/recording state.

## Evidence and limits

The deterministic detector returned [] / zero findings, but does not support SwiftUI. That result is unsupported coverage, not evidence of a clean UI. Browser DOM overlays do not apply to this native app. Source review exposed the remote-state mismatch; screenshot inspection confirms clear idle Start/tab hierarchy but cannot establish active, Watch, dark-mode, or largest-type usability.

## Minor observations

Keep the disconnected-device caution close to Start when relevant. Evaluate whether Moving, Stopped estimate, Unknown, and two averages all need to be expanded on Watch. Do not add more warning copy or another confirmation to every normal start.

## Questions to consider

Could the persistent accessory answer “Is this recording, on which device, and what can I do?” without requiring the Ride tab? Which secondary statistics actually affect decisions during a ride rather than afterward?
