-- Copy to headless-local.lua in the executable folder. Keep credentials local.
-- Use only on a server that permits automation. Specify the actual world endpoint.
return {
  host = "",
  loginPort = 7171,
  port = 7172,
  world = "OTServer",
  account = "",
  -- Prefer the launcher, which passes the password through the process environment.
  password = "",
  character = "",
  dat = "/data/things/860/Tibia.dat",
  -- Standard 8.60: false. Best Baiak's supplied OTFI indicates extended + frame groups.
  extended = true,
  frameGroups = true,
  frameDurations = false,
  -- Optional OTC minimap file (OTMM, not the old .map format).
  minimap = "",
  -- Supply confirmed same-floor approach points if starting upstairs.
  enableRoute = false, -- first test: login only
  approach = {},
  target = {x = 160, y = 48, z = 8},
  usePosition = {x = 160, y = 47, z = 8},
  useItemId = 7131
}
