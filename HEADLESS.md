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
