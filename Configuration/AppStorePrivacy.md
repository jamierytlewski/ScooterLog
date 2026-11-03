# App Store privacy and support setup

This worksheet describes the current code, not an assurance of legal compliance.
The Account Holder must verify the release build and actual operating practices
before submitting. App Store privacy labels, the privacy manifest, and the
public policy are separate requirements. Do not choose "Data Not Collected"
just because the app has no developer backend.

## Public URLs

After publishing and verifying HTTPS:

| App Store Connect field | Value |
| --- | --- |
| Privacy Policy URL | `https://scooterlog.j4m13.dev/privacy/` |
| Support URL | `https://scooterlog.j4m13.dev/support/` |
| Marketing URL (optional) | `https://scooterlog.j4m13.dev/` |
| Privacy Choices URL (optional) | `https://scooterlog.j4m13.dev/privacy/#choices` |

Use `privacy@j4m13.dev` as the public support/privacy contact. It forwards to the
maintainer; replies currently use a different address, as disclosed on the site.
This does not replace
the private App Review contact details Apple requests. Confirm the mailbox can
receive mail and that you can reply; neither DNS nor an HTML mail link creates it.

## Recommended conservative disclosure

For the intended operation with developer email support, select **Yes, we
collect data from this app**, and disclose the support data below rather than
assuming the optional-support exemption. This does not mean ride or Health
data is automatically uploaded to you.

| App Store data type | Purpose | Linked to the user? | Used for tracking? |
| --- | --- | --- | --- |
| Contact Info > Email Address | App Functionality (support and privacy requests) | Yes: the sender's email identifies the request | No |
| User Content > Customer Support | App Functionality (support and privacy requests) | Yes: correspondence is associated with its sender | No |

This reflects what the developer actually receives when a user contacts support,
even though correspondence is sent through the user's email app. Apple allows
some infrequent, optional support submissions to be omitted **only if all** of
its optional-disclosure criteria are met. Do not assume that exception without
reviewing the actual submission flow and use of the information.

No advertising or cross-app tracking is implemented. Do not select tracking
purposes for these data types. The app does not need an App Tracking Transparency
prompt for its present behavior.

## Location, HealthKit, Maps, and iCloud

Apple defines collection as off-device transmission that lets you or a
third-party partner access data beyond servicing a real-time request. Data
used by the app is not automatically data collected by the developer.

| Surface | Current behavior | How to answer |
| --- | --- | --- |
| Precise location / ride history | Stored locally; paired-device transfers; user-controlled export. No developer route endpoint. | Do not declare developer collection merely for on-device use or transfer between a user's paired devices. Reassess if you start routinely receiving, retaining, or analyzing routes. |
| Health / Fitness | Opt-in local heart-rate display; optional watch Other session; no HR in ride files, companion payloads, exports, or CloudKit. | No developer collection of Health/Fitness in the current implementation. Explain the watch session and possible watchOS Health/ring effects in policy and review notes. Do not claim "no Health access." |
| MapKit search / directions | Queries, search area, origins, destinations, and reroute origins go to Apple as required for these requests. | Apple's guidance says you are not responsible for declaring data collected by Apple. The app does not receive a developer analytics feed of users' searches. Disclose these transfers in the policy, not as tracking. |
| Private CloudKit | Opt-in manual upload of completed routes and saved places into the user's private database. No public database or developer download service. | Confirm that the developer/partners cannot access users' records. Under that operating model, do not classify Apple-only private storage as developer collection. A public/shared database or developer-accessible backend would require reassessment, including Precise Location and saved-place content. |
| App preferences | Theme, voice preference, sync preference in app-owned UserDefaults. | Local-only, not developer collection. The manifest declares required-reason UserDefaults access (`CA92.1`). |
| Website | Static GitHub Pages, no custom analytics/cookies/forms; provider technical logs. | The website policy discloses hosting. Do not infer the app collects website IP addresses. Reassess if you add an embedded web view, analytics, a form, or developer-accessible visitor data. |

If you retain diagnostics from Apple services, add **Diagnostics > Crash Data**
(and Performance Data or Other Diagnostic Data only when actually received)
for the purposes actually used, such as App Functionality for troubleshooting.
Determine linkage from the report contents; never call a report anonymous
without verifying. TestFlight's crash reports, screenshots, and tester feedback
also need appropriate handling even though the production app has no crash SDK.
Record which diagnostics you actually access before finalizing the release label.

Support attachments can contain additional sensitive data. The pages explicitly
ask users not to send Health records or unredacted routes. If you begin requesting
or routinely retaining these, reassess the relevant data types and update the
policy and App Store answers rather than treating all uploads as Customer Support.

## Pre-submission checks

- Verify all public URLs work without authentication over HTTPS, and the in-app
  Settings links open them. Verify the watch's links or its displayed fallback.
- Confirm the contact mailbox works and that the maintainer identity/contact
  details and retention practices match your actual operation and applicable law.
- Keep CloudKit in the private database; deploy production schemas/indexes and
  exercise sync, deletion, and re-upload behavior on a provisioned device.
- Inspect the release archive's privacy manifests for phone, watch, and extension.
  The existing empty collected-data array describes current app behavior; it
  does not replace App Store Connect answers or the policy for email/website data.
- Ensure optional Health/location behavior and purpose strings match the policy;
  do not imply scooter rides are automatically recorded as exercise workouts.
- Identify any Apple-provided diagnostics you retain and finalize the diagnostic
  rows above. Do not add analytics, ads, subscriptions, or new sharing endpoints
  without revisiting all three disclosures.
- Check provenance for code and artwork before public/commercial release. An MIT
  notice and AI assistance do not establish third-party rights.

## References

- [Apple: App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
  (collection definition, optional disclosure, and additional guidance for
  MapKit/CloudKit/App Analytics and on-device processing).
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
  (especially developer contact information, privacy policies, and Health data).
- [Apple Maps and privacy](https://www.apple.com/legal/privacy/data/en/apple-maps/)
- [GitHub General Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
