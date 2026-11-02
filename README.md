# ScooterLog

<img src="Shared/AppIcon.xcassets/AppIcon.appiconset/AppIcon.png" alt="ScooterLog app icon" width="128" align="right">

A native, local-first iPhone and Apple Watch scooter ride logger. Built for a Segway F3 and an Apple Watch Ultra 2, using GPS rather than private Segway Bluetooth protocols. Targets **iOS 27 / watchOS 27**, Swift 6, SwiftUI, and Xcode 27.2.

The phone target is **iPhone-only**; there is no dedicated iPad interface. The Apple Watch companion remains supported.

## What works in this starter

| Component | Implemented behavior |
| --- | --- |
| iPhone and watch apps | Start/end local GPS recording; elapsed time, moving time, estimated stopped time, unknown time, distance, current speed, overall and moving-average speed. Units are explicitly **miles and mph** everywhere. |
| Watch-first use | Start a ride on the watch with the phone pocketed or disconnected. The watch owns that ride and persists its route locally. The same metrics, history, route map, and manual directions are available on watch. |
| Local history | Atomic active checkpoints plus separate completed-route JSON files in Application Support. No account is necessary. A recovered ride is paused until explicitly resumed or ended; the gap remains unknown. Rides can be deleted from **History** (swipe, **Select** several, or from a ride's detail), always after a confirmation. A small deletion marker stays on the device so a deleted ride is not re-imported from the companion or iCloud. |
| Companion sync | Lightweight live snapshots approximately every five seconds when GPS updates arrive, immediate reachable messages plus application-context fallback, reliable completed-route file transfers, UUID deduplication, and application-level save acknowledgements. Outbox files remain until acknowledged. History includes a manual resend action. Deleting a ride on one device is sent to the other, which removes its copy. |
| Siri / Shortcuts | Native Start scooter ride and End scooter ride App Intents, exported as Shortcuts actions on both devices. Starts open the app to respect foreground location and first-run permission restrictions. iOS start uses `LiveActivityIntent`. |
| Live Activity | Real request/update/end lifecycle; Lock Screen, Dynamic Island, and compact `.small` Smart Stack presentation. Freshness derives from the GPS timestamp, not delivery time. It does not record location or keep the app alive. |
| Passive heart rate | Explicit opt-in local HealthKit reads; latest available sample and measurement time/age. No automatic permission prompt. No HR is stored in ride files or sent to CloudKit/companion. |
| Optional watch live HR | Separately confirmed **Other workout session** for sensor collection. Ends/discards its builder without calling `finishWorkout`, including when GPS recording ends. Not enabled by default. See limitations below. |
| Directions | Plan before a ride on either device, then start ride recording and turn-by-turn guidance together. Walking/cycling alternatives, map preview, live GPS progress, automatic off-route recalculation, optional spoken turns, manual controls, and F3 time/energy estimates. |
| Saved destinations | Pick a place from type-ahead MapKit suggestions on iPhone, name it Home, Work, or any name, rename/delete it, then use **Directions to Home/Work/...** on either device. Places persist locally, sync to the watch without replacing ride status, and participate in opt-in manual iCloud sync. |
| Private CloudKit | Optional **manual** completed-ride and saved-place upload/download on iPhone using private-database `CKAsset` route files, stable UUID records, explicit errors/retry, and private-cloud deletion. Rides deleted on the iPhone are also removed from iCloud on the next sync. Local rides and watch recording do not depend on iCloud. |

## Appearance and native UI

Watch colors have explicit watchOS variants: dark panels, bright theme accents, and readable secondary text, independent of iPhone Light Mode. Watch tool rows use rounded backgrounds and compact theme-colored icon tiles.

Use the **palette button** at the top right of the iPhone dashboard, or **Settings > Color scheme**, to choose **Tron blue** (cyan) or **Ares red**. Both use midnight-blue surfaces in Dark Mode and pale blue-gray surfaces with darker, legible accents in Light Mode. Appearance follows the device; neither theme forces Dark Mode. The color assets also include Increase Contrast variants. The choice is saved locally on each device; on watch, use **Appearance > Color scheme**. Phone and watch choices are independent.

The selected accent carries through controls, ride metrics, route lines, and the iPhone's Live Activity. Changing the palette also updates an existing local ride's Live Activity. Activity content includes an optional theme value so older activity snapshots continue to decode using blue. Compact Live Activities use the iOS 27 limited-width environment to hide the distance when only a symbol fits.

The dashboard brings the app icon's neon scooter and GPS-trail identity into the app with large, theme-matched artwork on iPhone and watch. The illustrated trail is decorative, not a recorded route. Active rides use rounded, monospaced-digit instruments for elapsed time, speed, and distance; history emphasizes distance with date and duration underneath. Coordinated surfaces carry through history, route details, directions, place search, and Settings while retaining native navigation, lists, SF Symbols, and system controls. On watch, **Start ride here** sits directly below the artwork on a transparent list row, before the explanatory copy, so its prominent button does not appear inside a second rounded background. The **Settings** gear contains location status, optional heart-rate consent, and private iCloud sync. Enabled heart-rate readings remain visible on the dashboard. Cloud sync state and errors survive dismissing Settings.

Text uses Dynamic Type; instruments and metric rows stack when horizontal space is insufficient. At accessibility sizes, decorative artwork is hidden, ride controls come before introductory content, and the elapsed timer uses spoken units rather than an overflowing clock string. Secondary copy and section headings use adaptive, higher-contrast text colors so they remain readable in Light Mode. Reduce Motion disables the primary button's subtle press response; the artwork is static and excluded from VoiceOver. Saved-place actions use a menu or swipe actions. In History, swipe a ride to delete it, press and hold for a context menu, tap **Select** to delete several at once, or use the trash button in a ride's detail; every deletion asks for confirmation first. Location denial offers an iPhone Settings link instead of an ineffective repeated permission request.

On iPhone, selecting **Ares red** also switches the Home Screen icon to the red scooter; **Tron blue** restores the original icon. iOS may display its standard icon-change confirmation. A failed change leaves a visible message and retries when you reopen the app. watchOS does not support alternate app icons, so the watch keeps its original icon while the in-app artwork follows its independently selected theme.

Touch and hold the iPhone's Home Screen icon, then choose **Start ride** to open ScooterLog and begin a new local ride. Cold and warm launches wait for foreground activation, return to the dashboard, and use the same location/storage checks as the Start button. If a local or companion ride is already active, ScooterLog shows that ride and a message instead of creating another. On first use, grant location and tap Start again; permission failures never report that recording began.

## Open, sign, and run

1. Open **`ScooterLog.xcodeproj`** directly in Xcode 27.2. The generated project is committed; XcodeGen is only needed after changing `project.yml`. The local `ScooterCore` Swift package has no third-party dependencies.
2. Select your Apple development team for **ScooterLog**, **ScooterWatch**, and **ScooterLiveActivity** in Signing & Capabilities. Use unique bundle identifiers if these are unavailable to your team. Keep the watch identifier nested under the phone identifier, and update `WKCompanionAppBundleIdentifier` in `Configuration/Watch-Info.plist` if the phone identifier changes.
3. Configure HealthKit on the phone and watch targets. HealthKit and iCloud capabilities require a provisioning team that supports them; unsigned simulator builds do not prove device signing will succeed.
4. Configure the phone's CloudKit capability/container as described below, even if you leave sync off. No iCloud account is needed for local recording. For a local-only signing configuration, remove the iCloud keys from `Phone.entitlements` **and set `CLOUDKIT_CONTAINER_IDENTIFIER` to an empty string**. The configuration guard then reports the unavailable service before constructing `CKContainer`; using a nonempty container identifier without matching signing entitlements is not supported.
5. Connect an unlocked iPhone running iOS 27 or later, enable Developer Mode if requested, choose the **ScooterLog** scheme, and Run. Launch once, tap **Allow location**, grant precise When In Use location, then **Start ride here**. Reduced accuracy or poor GPS can leave time unknown.
6. Pair the Ultra 2 with that phone, enable watch Developer Mode when required, install the companion through Xcode/the Watch app, select **ScooterWatch** and the watch destination, and Run. Open the watch app, allow location, and start there for watch-owned recording.
7. Leave location permission enabled. The native `CLServiceSession` and `CLBackgroundActivitySession` support ongoing background location; the app does not use a fake workout to keep GPS alive. A force quit, OS termination, battery restriction, sensor issue, or denied permission can interrupt updates. Reopen to inspect/resume the saved checkpoint.

Only start on **one device**. A local start is refused when the latest companion status reports an active ride. There is no distributed lock while disconnected: independently started rides have distinct IDs and are both preserved, and reconnection shows an ownership-conflict warning. Ending a remote-owned ride requires reachability and an actual owner acknowledgement, with a timeout/error if none arrives. Forgetting offline companion status is explicitly confirmed and **does not stop that device**.

No signing certificates, accounts, API tokens, paid resources, or deployment are configured by this repository.

The iPhone and watch share the original 1024 px neon scooter icon in `Shared/AppIcon.xcassets/AppIcon.appiconset`. The iPhone also bundles `AppIconAres` as an alternate icon via `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`. Matching in-app illustrations live in `Shared/Assets.xcassets`. After replacing the original icon, run `swift Tools/GenerateThemeIcon.swift` from the repository root on macOS to regenerate the red icon and both in-app illustrations. No project regeneration is needed for image changes.

## Siri phrase setup

After launching the app and allowing location, try **"Hey Siri, start a ride in ScooterLog"**. Native actions also appear in Shortcuts under ScooterLog.

For the exact phrase **"Hey Siri, I'm riding my scooter"**, create a personal shortcut named **I'm riding my scooter**, add ScooterLog's **Start scooter ride** action, and run it once. A third-party app cannot reserve that global phrase by itself. Unlocking/opening the app may be necessary, especially on first use; a failed/denied start throws an error rather than claiming recording began.

End with **"Hey Siri, end my ride in ScooterLog"** on the recording owner. End intent deliberately does not claim to stop an unreachable companion. The app's connected End button can request that operation and waits for acknowledgement.

## Private CloudKit setup

CloudKit supersedes the earlier D1 idea. There is **no Cloudflare dependency or automatic location upload**.

1. In your Apple Developer account/Xcode Signing & Capabilities, enable **iCloud > CloudKit** for the phone app and create/select a container owned by your team.
2. Set `CLOUDKIT_CONTAINER_IDENTIFIER` in `project.yml` (then regenerate) or the project's build settings to that exact container, for example `iCloud.com.yourteam.ScooterLog`. It feeds both the entitlement and `ScooterCloudContainer` Info key. The watch uses local storage plus WatchConnectivity, not direct CloudKit.
3. In the CloudKit development schema create record type **CompletedRide**, with fields **route** (`Asset`), **startedAt** (`Date/Time`), and **schemaVersion** (`Int64`), and record type **SavedPlace**, with field **place** (`Bytes`, a small JSON payload). Add a **Queryable** index on `recordName` for **both** types so the fetch-all queries can run. Create both types before the first sync, even if you have no saved places yet.
4. Use a provisioned, signed-in iCloud device. In ScooterLog's **Settings**, enable **Sync rides and saved places**, then tap **Sync now**. This explicitly uploads completed local GPS/timing files and saved-place names/coordinates/deletion markers, and downloads private cloud data. The active ride and HR are excluded. There is no background push or automatic sync schedule.
5. Network/account/schema errors remain visible; retry Sync now after resolving them. UUID imports are idempotent. Local recording never waits for the network. The simulator build explicitly disables CloudKit operations with a visible message; use a signed, provisioned device to exercise this path.
6. Before distribution, deploy the schema/indexes to CloudKit Production and verify with the appropriate signing/environment. This starter has **not** provisioned or verified your container.

Turning sync off stops subsequent operations (an already submitted request can finish); it does not delete cloud records. **Delete private iCloud data** deletes this app's ride/place records and turns sync off after success. It does not erase local/watch copies. Re-enabling and syncing can upload those copies again. Deleting a ride in **History** removes it from that device, asks the paired device to do the same and, when sync is on, the next **Sync now** removes its iCloud record. The deletion marker is saved first and any leftover ride file is purged on the next launch. The marker stays on the device and is sent to the companion, but it is **not** synced through iCloud: if a second iPhone on the same iCloud account still has a ride you deleted, its next sync uploads it again and your next sync removes it again until you delete it there too. To erase everything, remove the app from each device; OS backups are managed separately by the user. A cloud conflict editor is not implemented.

## Home, Work, and other saved destinations

On iPhone open **Saved places** and tap **Search for a place**, then start typing a business, landmark, or address. Suggestions appear as you type, with the matching letters in bold and the area underneath, and are biased toward your last known location when there is one. Tap a suggestion (or press **Search** on the keyboard for a full list); a broad suggestion such as "coffee" expands into the places it matches so you pick the exact one. The place's own name is prefilled and can be changed to Home, Work, or anything else (up to 100 characters), and nothing is saved until you confirm. If Apple Maps cannot be reached, a **Search unavailable** message with **Try again** replaces the list. Use a place's **Actions** menu or swipe its row to rename or delete it; delete asks for confirmation. To change the coordinate, delete the old place and save the correct one. Searching requires network access and sends what you type (including partial text for suggestions) and, when known, a search area centered on your last known location to Apple.

Open **Directions** on either device and tap **Directions to Home**, **Directions to Work**, or any other saved name, or tap **Search for a destination** to choose any other place from the same type-ahead suggestions (**Refresh route** recalculates it). Previewing a route does not record a ride. It requests a single foreground location fix, with a 15-second timeout; use **Starting point** to search for a different origin, including when location is denied or unavailable. Choose **Cycling** (the default) or **Walking**; Apple Maps returns available alternatives, shown on a map with distance and its travel-time estimate. Tap a route to select it and review the manual steps. **Start ride & turn-by-turn** starts local GPS ride recording and navigation in one action; if a local ride is already recording, guidance uses that ride. It requests location access if needed. Optional **Speak turns aloud** announces route instructions. Keep ScooterLog open during guidance: live GPS advances instructions and automatically requests a new route after repeated accurate fixes show that you are off route. **Recalculate route from here** is also available at any time, for example when you see a closure ahead. A successful reroute replaces the selected route; if Apple Maps cannot find one, stop safely and retry or choose another route. **Stop directions (keep ride recording)** leaves the ride active; **End ride and directions** asks for confirmation and saves the ride to History. Changing the origin or mode recalculates the preview and resets its steps. Some regions have no cycling coverage; the app reports this rather than silently substituting a walking route. Once saved and synced, the destination does not require repeating the address search; route calculation and rerouting require network access. The watch provides one-tap routing to synced destinations; management is on the phone.

Automatic rerouting reacts to the rider moving off the currently selected route. MapKit does not provide ScooterLog with a guaranteed feed of sidewalk closures, accidents, hazards, or their exact locations, so it cannot warn about an incident still ahead or guarantee that a recalculated route avoids an unreported blockage. Follow a safe, legal detour; once it takes you off the route, guidance recalculates from your current location. You can also request a recalculation yourself while stopped safely.

The **Scooter estimate** uses the supplied Segway F3 specifications: 20 mph maximum speed, 477 Wh nominal battery energy, 25 miles rated range at 20 mph, and 43.5 miles at 9 mph. **Planning speed** is saved locally per device and can be adjusted from 5 to 20 mph. Time is route distance divided by that speed, rounded up to minutes: it assumes no stops or slower sections and is not a predicted arrival time. Energy is a benchmark band of approximately **11.0–19.1 Wh per mile**, with the corresponding percentage of a full new 477 Wh battery; it is not interpolated by planning speed. Estimates above 100% are not capped and routes beyond the 25-mile full-speed rating show a warning. This is not live battery telemetry, a guaranteed energy bound, or a remaining-range check. Manufacturer tests use a new full battery, roughly 165 lb load, flat pavement and controlled conditions; hills, load, temperature, wind, tire pressure and acceleration/braking can put actual consumption outside the band. Nominal/max motor power and the 20% climbing rating alone do not support reliable terrain or energy modeling.

Places use stable UUIDs and atomic storage. Companion contexts/messages include both ride and place keys, so a place update cannot clobber live ride status. Merging uses modification timestamps with deterministic tie-breaking; deletion markers win ties and are retained, so an older companion/cloud snapshot cannot resurrect a removed place. Device clocks should be correct. Explicitly adding the same address later creates a new UUID. Cloud sync first merges saved places/deletion markers before uploading the converged state; optimistic CloudKit conflicts surface for retry rather than being silently overwritten. These small place records use inline JSON; large ride routes use assets.

## Heart-rate consent and limits

Passive mode only requests heart-rate reads and shows an available sample from the last hour, with its timestamp. A successful Health authorization request **does not prove read permission was granted**; no samples can mean no available data or unreadable data. Refresh is manual/on foreground, not continuous monitoring.

On iPhone, enable these optional reads in **Settings > Heart rate**. On watch, the consent controls remain on the dashboard.

On watch, **Live HR (Other session)** is a separate, per-session confirmation and requires a locally recording ride. It requests workout authorization and explicitly uses `HKWorkoutSession(.other)` plus a live builder for sensors. It ends collection and calls `discardWorkout()` without `finishWorkout()`: **ScooterLog does not save a workout record to Health**. This is not a scooter exercise classification. watchOS may still create raw Health samples, affect rings, or vary sampling frequency; zero OS Health writes/ring effects and continuous HR are **not guaranteed**. Declining Health leaves GPS recording useful. The phone never starts this workout session.

There are no calorie, medical, stress-diagnosis, crash-detection, emergency-response, or guaranteed monitoring claims.

## Timing, GPS, and directions

Elapsed time includes every stop and all unknown gaps. Overall average is accepted distance / elapsed; moving average is accepted distance / moving time. Both handle zero time safely. Current speed is unavailable for negative Core Location speed or a fix older than ten seconds.

The shared engine rejects invalid coordinates, accuracy worse than 25 m, stale/out-of-order samples, speeds above 20 m/s, and jumps above 20 m/s. Moving entry uses 1.5 m/s, moving continuation 0.6 m/s. A stop from the moving state requires at least two low-speed samples spanning at least three seconds; a brief noisy dip is folded back into movement. Stationary jitter does not add distance. Core Location uses the scooter-appropriate `.otherNavigation` configuration. An explicit `stationary` event preserves stopped time during the system's automatic pause, including a long stop with no GPS callbacks. Unavailable/denied/unknown-location events end that confirmation; cancellation and relaunch do not extend it. Recovery resets the accounting boundary so a short recording interruption cannot invent motion or distance. Otherwise intervals above 15 seconds, unavailable-speed intervals, and unresolved stop candidates remain unknown. GPS distance and stop estimates are not ground truth and need real-ride tuning. Route maps break polylines at long gaps instead of inventing a connecting path.

**Moving versus stopped time is the core capability. Stopped time is not traffic-light detection.** Although Apple Maps can visually draw signals/signs, MapKit does not expose a documented public stop-sign/traffic-light feature dataset for classifying these stops. No Overpass/third-party route upload is implemented or authorized. MapKit searches/directions send the necessary search/origin/destination to Apple when requested.

Directions use **walking or cycling**, not a scooter-specific legal/safe route. Neither mode guarantees that the scooter can legally or safely traverse every section. Verify route safety and local laws yourself. Active guidance uses GPS to advance MapKit's steps and can request a new route when you go off route. It does not detect every hazard, guarantee closure-aware routing, or hand an active route between phone and watch. Keep the app open and stop safely before interacting with it.

## Architecture

- `Sources/ScooterCore`: Sendable/Codable ride engine, explicit units, archive deduplication, ride deletion with tombstones, split atomic file repository, saved-place persistence/merge/tombstones, and the place-choice ordering/match-highlighting models behind type-ahead search. Foundation-only, tested on macOS with Swift Testing.
- `Shared`: Main-actor recorder, native Core Location sessions, WatchConnectivity, SwiftUI dashboards/history/maps/directions, type-ahead MapKit place search (`MKLocalSearchCompleter` behind a small service protocol, with a DEBUG-only stub for UI tests), App Intents, HealthKit readers and opt-in watch workout collection.
- `App`: iOS entry point, ActivityKit lifecycle, opt-in manual private CloudKit asset sync.
- `WatchApp`: real standalone-capable watchOS app entry point using the shared UI/services.
- `LiveActivity`: WidgetKit extension with Lock Screen, Dynamic Island, and small Smart Stack views. It consumes snapshots only.
- `Configuration`: usage descriptions, background modes, HealthKit/iCloud entitlements. `Shared/PrivacyInfo.xcprivacy` declares app-owned preferences and no developer tracking.

Rides retain one recording owner and stable UUID. Active fixes only rewrite the active checkpoint, not all prior routes. Completion saves the immutable route **before** ending recording/clearing the checkpoint; recovery prefers that completed file after a cleanup interruption. Decode/storage failures preserve the original files and surface errors rather than silently resetting history. JSON was chosen over SwiftData to share deterministic model/storage tests across targets without container migrations or a cloud dependency. A later schema change needs an explicit migration.

Companion files are acknowledged only after the receiver durably saves the ride. Failed transfers/save errors are retryable through reconnection/foreground queue flush or History's resend action. Live metrics are best-effort and show update age; connectivity is not a guarantee of current GPS data.

## Build and verification

Regenerate only if needed:

```sh
xcodegen generate
swift test
xcodebuild -project ScooterLog.xcodeproj -scheme ScooterLog \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ScooterLog.xcodeproj -scheme ScooterWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO build
```

Do not force `-sdk iphonesimulator` onto the phone scheme: it also builds the embedded watch target, which must select its own platform SDK.

The fifteen iOS UI tests cover ride start/recovery/resume/end/history, palette selection and persistence after relaunch, portrait/landscape interaction, largest Dynamic Type and touch targets, Settings sync-state persistence after dismissal, pre-ride route previews, alternatives, walking/cycling switching, F3 estimates, denied-location recovery with a searched origin, turn-by-turn ride start, automatic step advancement, successful off-route recalculation and recovery, failed-reroute retry, routing/search failures, saved destinations, and ride deletion. Search tests use `-ScooterLogStubPlaceSearch`; route tests also use `-ScooterLogStubDirections`, and turn-by-turn UI tests use `-ScooterLogStubNavigation` to feed controlled GPS positions and reroutes, including `-ScooterLogStubRerouteFailure` (all DEBUG-only). These don't need network access; live guidance tests do need location permission because the feature intentionally starts a real recording. First install/launch the app on your chosen simulator and grant location (for example `xcrun simctl privacy <UUID> grant location com.scooterlog.app`), then:

```sh
xcodebuild -project ScooterLog.xcodeproj -scheme ScooterLog \
  -destination 'platform=iOS Simulator,id=<YOUR-BOOTED-IPHONE-UUID>' \
  -parallel-testing-enabled NO -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO test
```

Validated locally with Xcode 27.2 (27B52): **40 shared deterministic tests** (including confirmed 60-second stationary pauses versus unknown gaps, rejected fixes on a non-stationary transition, recovery, saved-place persistence, convergence, ride and saved-place deletion, place-choice ordering/highlighting, and invalid input), unsigned iPhone/watch/Live Activity simulator builds, an **unsigned generic iOS device build** (including device-only CloudKit code), and **11 passing iOS 27.0 simulator UI tests**. Palette contrast and hit-region audits also pass in Light Mode and with Increase Contrast enabled. The eight accent variants and four secondary-text variants meet a measured 4.5:1 minimum against their applicable native list surfaces and, for accents, filled-button text.

The pre-ride directions update additionally passes **43 shared tests** (including F3 benchmark arithmetic, invalid inputs and overflow), **five focused iPhone UI tests** covering routes, saved destinations and error recovery, and unsigned simulator/device builds. A live MapKit cycling request between public New York landmarks returned three alternatives with steps. Route previews support pinch zoom without capturing the form's vertical scrolling gestures. Current-location accuracy and permission prompts still require device verification; synthetic UI-test origins do not validate GPS hardware.

The iOS 27.0 simulator's automatic clipping/scaling heuristics flagged native list labels and section text despite visibly complete, scaling text. Palette tests therefore audit contrast and hit regions; the largest-type test compares actual row growth, checks navigation/control bounds, captures the rendered layout, and retains a clipped-text audit on the initial large-type dashboard. This does not replace a real-device VoiceOver and accessibility review. The History selection-mode audit skips the three floating glass-toolbar buttons (Done, Select all, Delete): the simulator's contrast check mis-measures tinted text on system glass, and the rendered colors were measured separately at about 6:1.

A device build is compilation, not a physical-device run. Only iOS 27.0/27.1 simulator runtimes are installed on the implementation Mac; **watch launch was not tested**, although its simulator target compiled. Final App Intents metadata extraction and English phrase training/archiving succeed; actual Siri recognition must still be verified on device.

**Still requiring real devices/account:** signing/provisioning, permission/unlock/Siri behavior, background GPS accuracy/battery and stop thresholds during actual rides, paired/disconnected watch transfers and acknowledgements, Ultra 2 live sensor session/discard behavior and OS Health/ring effects, visible Lock Screen/Dynamic Island/Smart Stack behavior, CloudKit development/production sync/deletion (including removal of deleted rides) with your provisioned iCloud account, propagation of ride deletions between a paired iPhone and watch, the live MapKit autocomplete service (the UI tests use a stub), and real network directions. Simulator GPS does not validate any of those physical behaviors. This is a working native starter, not an App Store release; release accessibility/localization review, data migration/export, and distribution work remain.

## Official references

- [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), and [adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Live Activity design](https://developer.apple.com/design/human-interface-guidelines/live-activities) and [iOS 27 limited-width Dynamic Island](https://developer.apple.com/documentation/swiftui/environmentvalues/isdynamicislandlimitedinwidth)
- [Core Location background updates](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [CLBackgroundActivitySession](https://developer.apple.com/documentation/corelocation/clbackgroundactivitysession)
- [App Intents](https://developer.apple.com/documentation/appintents) and [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent)
- [WatchConnectivity sessions](https://developer.apple.com/documentation/watchconnectivity/wcsession)
- [ActivityKit live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) and [custom Live Activity views](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities)
- [HealthKit workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions) and [discardWorkout](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/discardworkout())
- [MapKit directions](https://developer.apple.com/documentation/mapkit/mkdirections)
- [CloudKit](https://developer.apple.com/documentation/cloudkit) and [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)
