# OTCv8 Headless V1 — experimental

The --headless startup flag skips window, graphics, UI, sound, and mouse initialization; the event loop only polls network and scheduled tasks. The normal upstream startup remains available. Graphics libraries are still linked by the existing build system.

## Build and offline smoke test
Compile the full OpenGL configuration, copy otclient_gl.exe as otclient_headless.exe, and run test-headless.cmd from the repository root. Check the log for SMOKE_OK. The smoke test uses no live server and does not render frames.

## Single-character runtime (experimental)
Copy headless-local.example.lua to headless-local.lua. Supply the actual world endpoint, character credentials locally, a matching DAT asset, and optionally an OTC-format OTMM map. Never commit the local file. Run start-headless.cmd. Standard OTCv8 protocol 860 and the existing LocalPlayer::autoWalk pathfinder are reused. The graphical CaveBot UI and existing UI-dependent bot profiles are not supported by this entry point.

The example targets the supplied floor-8 cart. The approach list for other floors must be provided explicitly. USE is requested only for the matching item at the configured coordinate; the example does not claim the server accepted it. No reconnect loop or multi-character manager is implemented. Server-specific protocol compatibility, walking, asset parsing, and desktop-independent execution require testing. Use only with permission from the server operator.
