# ScooterLog

A native, local-first iPhone and Apple Watch scooter ride logger. Built for a Segway F3 and an Apple Watch Ultra 2, using GPS rather than private Segway Bluetooth protocols. Targets **iOS 27 / watchOS 27**, Swift 6, SwiftUI, and Xcode 27.2.

The phone target is **iPhone-only**; there is no dedicated iPad interface. The Apple Watch companion remains supported.

## What works in this starter

| Component | Implemented behavior |
| --- | --- |
| iPhone and watch apps | Start/end local GPS recording; elapsed time, moving time, estimated stopped time, unknown time, distance, current speed, overall and moving-average speed. Units are explicitly **miles and mph** everywhere. |
| Watch-first use | Start a ride on the watch with the phone pocketed or disconnected. The watch owns that ride and persists its route locally. The same metrics, history, route map, and manual directions are available on watch. |
| Local history | Atomic active checkpoints plus separate completed-route JSON files in Application Support. No account is necessary. A recovered ride is paused until explicitly resumed or ended; the gap remains unknown. |
| Companion sync | Lightweight live snapshots approximately every five seconds when GPS updates arrive, immediate reachable messages plus application-context fallback, reliable completed-route file transfers, UUID deduplication, and application-level save acknowledgements. Outbox files remain until acknowledged. History includes a manual resend action. |
| Siri / Shortcuts | Native Start scooter ride and End scooter ride App Intents, exported as Shortcuts actions on both devices. Starts open the app to respect foreground location and first-run permission restrictions. iOS start uses `LiveActivityIntent`. |
| Live Activity | Real request/update/end lifecycle; Lock Screen, Dynamic Island, and compact `.small` Smart Stack presentation. Freshness derives from the GPS timestamp, not delivery time. It does not record location or keep the app alive. |
| Passive heart rate | Explicit opt-in local HealthKit reads; latest available sample and measurement time/age. No automatic permission prompt. No HR is stored in ride files or sent to CloudKit/companion. |
| Optional watch live HR | Separately confirmed **Other workout session** for sensor collection. Ends/discards its builder without calling `finishWorkout`, including when GPS recording ends. Not enabled by default. See limitations below. |
| Directions | MapKit destination search and walking-route steps on either device. Manual Back/Next progression, network/error states, and a recent GPS-origin requirement. |
| Saved destinations | Add a MapKit search result on iPhone, name it Home, Work, or any name, rename/delete it, then use **Directions to Home/Work/...** on either device. Places persist locally, sync to the watch without replacing ride status, and participate in opt-in manual iCloud sync. |
| Private CloudKit | Optional **manual** completed-ride and saved-place upload/download on iPhone using private-database `CKAsset` route files, stable UUID records, explicit errors/retry, and private-cloud deletion. Local rides and watch recording do not depend on iCloud. |

## Appearance and native UI

Use the **palette button** at the top right of the iPhone dashboard, or **Settings > Color scheme**, to choose **Tron blue** (cyan) or **Ares red**. Both use native charcoal surfaces in Dark Mode and darker, legible accent variants in Light Mode. Appearance follows the device; neither theme forces Dark Mode. The color assets also include Increase Contrast variants. The choice is saved locally on each device; on watch, use **Appearance > Color scheme**. Phone and watch choices are independent.

The selected accent carries through controls, ride metrics, route lines, and the iPhone's Live Activity. Changing the palette also updates an existing local ride's Live Activity. Activity content includes an optional theme value so older activity snapshots continue to decode using blue. Compact Live Activities use the iOS 27 limited-width environment to hide the distance when only a symbol fits.

The dashboard prioritizes starting or controlling a ride and uses native navigation, grouped lists, SF Symbols, and system materials rather than decorative glass or glow. The **Settings** gear contains location status, optional heart-rate consent, and private iCloud sync. Enabled heart-rate readings remain visible on the dashboard. Cloud sync state and errors survive dismissing Settings.

Text uses Dynamic Type; metric rows stack when horizontal space is insufficient. At accessibility sizes, ride controls come before introductory content and the elapsed timer uses spoken units rather than an overflowing clock string. Secondary copy and section headings use adaptive, higher-contrast text colors so they remain readable in Light Mode. Saved-place actions use a menu or swipe actions, with confirmation before deletion. Location denial offers an iPhone Settings link instead of an ineffective repeated permission request. No custom motion is added.

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

The phone and watch targets intentionally leave `ASSETCATALOG_COMPILER_APPICON_NAME` empty: the shared catalog currently contains colors, not release icons. Before distribution, add the appropriate app-icon assets and configure their names in each target's settings in `project.yml`, then regenerate the project.

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

Turning sync off stops subsequent operations (an already submitted request can finish); it does not delete cloud records. **Delete private iCloud data** deletes this app's ride/place records and turns sync off after success. It does not erase local/watch copies. Re-enabling and syncing can upload those copies again. To erase local history in this starter, remove the app from each device; OS backups are managed separately by the user. Ride deletion tombstones and a cloud conflict editor are not implemented.

## Home, Work, and other saved destinations

On iPhone open **Saved places**, search Apple Maps, select the correct result, and enter a name (up to 100 characters). Rename changes the label; delete removes it from the visible list. To change the coordinate, delete the old place and save the correct search result. Search requires network access and transmits the requested query to Apple.

Open **Directions** on either device and tap **Directions to Home**, **Directions to Work**, or any other saved name. A recent accurate origin from a recording ride is still required. Once saved and synced, the destination does not require repeating the address search; route calculation still requires network access. The watch provides one-tap routing to synced destinations; management is on the phone.

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

Directions use **walking**, not a scooter-specific legal/safe route. Verify route safety and local laws yourself. Steps advance manually on the device where requested; no automatic turn detection, haptics, rerouting, or phone-to-watch route handoff is claimed.

## Architecture

- `Sources/ScooterCore`: Sendable/Codable ride engine, explicit units, archive deduplication, split atomic file repository, and saved-place persistence/merge/tombstones. Foundation-only, tested on macOS with Swift Testing.
- `Shared`: Main-actor recorder, native Core Location sessions, WatchConnectivity, SwiftUI dashboards/history/maps/directions, App Intents, HealthKit readers and opt-in watch workout collection.
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

The five iOS UI tests cover ride start/recovery/resume/end/history, palette selection and persistence after relaunch, portrait/landscape interaction, largest Dynamic Type and touch targets, blank-search validation and missing-location recovery, and Settings sync-state persistence after dismissal. First install/launch the app on your chosen simulator and grant location (or use `xcrun simctl privacy <UUID> grant location com.scooterlog.app`), then:

```sh
xcodebuild -project ScooterLog.xcodeproj -scheme ScooterLog \
  -destination 'platform=iOS Simulator,id=<YOUR-BOOTED-IPHONE-UUID>' \
  -parallel-testing-enabled NO -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO test
```

Validated locally with Xcode 27.2 (27B52): **19 shared deterministic tests** (including confirmed 60-second stationary pauses versus unknown gaps, rejected fixes on a non-stationary transition, recovery, saved-place persistence, convergence, deletion, and invalid input), unsigned iPhone/watch/Live Activity simulator builds, an **unsigned generic iOS device build** (including device-only CloudKit code), and **5 passing iOS 27.0 simulator UI tests**. Palette contrast and hit-region audits also pass in Light Mode and with Increase Contrast enabled. The eight accent variants and four secondary-text variants meet a measured 4.5:1 minimum against their applicable native list surfaces and, for accents, filled-button text.

The iOS 27.0 simulator's automatic clipping/scaling heuristics flagged native list labels and section text despite visibly complete, scaling text. Palette tests therefore audit contrast and hit regions; the largest-type test compares actual row growth, checks navigation/control bounds, captures the rendered layout, and retains a clipped-text audit on the initial large-type dashboard. This does not replace a real-device VoiceOver and accessibility review.

A device build is compilation, not a physical-device run. Only iOS 27.0/27.1 simulator runtimes are installed on the implementation Mac; **watch launch was not tested**, although its simulator target compiled. Final App Intents metadata extraction and English phrase training/archiving succeed; actual Siri recognition must still be verified on device.

**Still requiring real devices/account:** signing/provisioning, permission/unlock/Siri behavior, background GPS accuracy/battery and stop thresholds during actual rides, paired/disconnected watch transfers and acknowledgements, Ultra 2 live sensor session/discard behavior and OS Health/ring effects, visible Lock Screen/Dynamic Island/Smart Stack behavior, CloudKit development/production sync/deletion with your provisioned iCloud account, and real network directions. Simulator GPS does not validate any of those physical behaviors. This is a working native starter, not an App Store release; app icons, release accessibility/localization review, data migration/export, and distribution work remain.

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
