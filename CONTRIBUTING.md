# Contributing to ScooterLog

ScooterLog is an early-stage, local-first iPhone and Apple Watch scooter ride
logger. Bug reports, real-device feedback, documentation improvements, and
focused pull requests are welcome. Much of the initial implementation was
developed with AI assistance; contributions are judged by their behavior,
clarity, and evidence, not by whether AI tools were used.

## Discuss and report

Use [GitHub Issues](https://github.com/jamierytlewski/ScooterLog/issues) for
non-sensitive bugs and feature proposals:

- **Bug Reports**: Choose the **🐛 Bug Report** form. It guides you through
  providing required context (app/build version, iOS and watchOS versions, device
  models, recording owner device, companion connectivity status, and reproduction steps).
- **Feature Requests**: Choose the **💡 Feature Request** form to propose new
  functionality, UI ideas, or integration enhancements across the iPhone app,
  Apple Watch app, Live Activities, widgets, or Siri Shortcuts.
- **Open Discussions**: Use [GitHub Discussions](https://github.com/jamierytlewski/ScooterLog/discussions)
  for general Q&A, setup questions, or open-ended brainstorming. For substantial
  architectural changes or new dependencies, discuss the approach before implementing it.

**Issues and pull requests are public.** Do not attach real ride exports, home or
work coordinates, Health data, private logs, signing files, tokens, or screenshots
with personal information. Use synthetic routes and redact diagnostics. Send
privacy concerns or suspected vulnerabilities privately to
[privacy@j4m13.dev](mailto:privacy@j4m13.dev), without exploit details in a public
issue.

## Develop

Follow the setup and signing instructions in [README.md](README.md). The app
currently targets iOS 27 / watchOS 27 with Xcode 27.2; the Foundation-only
`ScooterCore` package can be tested independently with a compatible Swift toolchain.
Use your own signing team and CloudKit container, and do not commit personal
signing changes.

Keep changes focused. Preserve Swift 6 concurrency safety, explicit errors,
local-first storage, and the distinction between the recording owner and its
companion. Do not silently upload routes or Health data, add tracking, or treat
walking/cycling directions as guaranteed scooter-legal routes.

Run the smallest checks that cover your change:

```sh
swift test
xcodebuild -project ScooterLog.xcodeproj -scheme ScooterLog \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO build
```

See README for simulator UI-test and watch-build commands. Add regression tests
for behavior changes. GPS accuracy, background recording, WatchConnectivity,
HealthKit sensors, and production CloudKit need real-device checks; distinguish
those from simulator results. Documentation-only changes do not need an app build.

In your pull request, complete the checklist provided in the pull request
template. Explain the problem, the change, and what you actually verified
(simulator vs. real devices). Include redacted before/after screenshots for
visible changes. Disclose meaningful limitations, including untested device
behavior. Review and understand AI-assisted changes before submitting them.

## License and provenance

The project is available under the [MIT license](LICENSE). Contributions are
submitted under that same license. Only contribute work you have the right to
license; preserve required notices for any third-party material. AI assistance
does not establish ownership or remove license obligations. Do not add code,
images, fonts, or other assets with unknown or incompatible provenance.
