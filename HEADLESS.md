# OTCv8 Headless V1 — experimental

The --headless startup flag skips window, graphics, UI, sound, and mouse initialization; the event loop only polls network and scheduled tasks. The normal upstream startup remains available. Graphics libraries are still linked by the existing build system.

## Build and offline smoke test
Compile the full OpenGL configuration, copy otclient_gl.exe as otclient_headless.exe, and run test-headless.cmd from the repository root. Check the log for SMOKE_OK. The smoke test uses no live server and does not render frames.

## Single-character runtime (experimental)
Copy headless-local.example.lua to headless-local.lua. Supply the actual world endpoint, character credentials locally, a matching DAT asset, and optionally an OTC-format OTMM map. Never commit the local file. Run start-headless.cmd. Standard OTCv8 protocol 860 and the existing LocalPlayer::autoWalk pathfinder are reused. The graphical CaveBot UI and existing UI-dependent bot profiles are not supported by this entry point.

The example targets the supplied floor-8 cart. The approach list for other floors must be provided explicitly. USE is requested only for the matching item at the configured coordinate; the example does not claim the server accepted it. No reconnect loop or multi-character manager is implemented. Server-specific protocol compatibility, walking, asset parsing, and desktop-independent execution require testing. Use only with permission from the server operator.

## V2 login test
The executable now starts in headless mode by default. Open configure-headless.cmd to configure one character, select a matching DAT and start a login-only test. The launcher writes local settings without a password and passes the password only to the child process environment. The world endpoint must be supplied by the operator. No live server test has been performed in CI. Log: otclient-headless.log. The graphical CaveBot, proxy authentication, multi-character operation and running without an interactive Windows session are not validated.

## V3 experimental multi-profile manager
Open manager-headless.cmd, import a matching DAT, create individual profiles and start selected or all profiles. SOCKS5 host/port/user/password is optional and must be a SOCKS5 server; HTTP proxies are not supported. Passwords are stored using Windows DPAPI for the same Windows account and computer. Each client has a separate log and write directory. CPU seconds and working-set memory are displayed; these are not percent utilization. Route execution is optional, and the destination and object position/ID must be verified locally. Only use on servers that authorize automation. The manager uses one process per character and has no fixed profile-count ceiling, but resource and server limits remain. No automatic retries on rejected login. The command start-saved-headless.cmd runs the saved profiles without the management GUI, under the same Windows account; use Windows Task Scheduler if execution outside an interactive session is required. CI tests four offline processes and samples their CPU and memory; it does not prove live login, SOCKS5 compatibility, navigation, native CaveBot profile compatibility or Session 0 execution. Never distribute the profiles folder.

CI also includes loopback-only SOCKS5 negotiation tests with and without authentication and a SYSTEM scheduled-task smoke test in Windows Session 0. These tests do not contact Best Baiak or certify live gameplay or production capacity.

## V3.2 login and DAT diagnostics
The manager now exposes login port 7171 and game port 7172 separately. The login protocol requests the character list and uses the returned world host with the configured game port. When importing the DAT, the manager copies only four-byte signatures from matching SPR and PIC files in the same folder; no sprite rendering is performed. No live login has been validated. The DAT parser reports the failing category, item ID and record offset, rejects invalid sprite counts, and skips graphics-only frame normalization in headless mode. Existing profiles default to login port 7171.

## V3.3 DAT validation and CaveBot waypoint runner
The loader tries the configured standard DAT flags first, then the other standard combinations, accepting only a full parse. Unsupported asset formats are rejected and the header and failing record are logged. A synthetic 8.60 DAT fixture and mocked CaveBot route test gate packaging. The independent waypoint runner uses the native OTC pathfinder, filters waypoints by the confirmed player floor, recalculates stalled movement, and requests a single matching adjacent item use. It does not load graphical vBot configurations or prove server-side action completion. Real Best Baiak assets and live server compatibility have not been validated.
