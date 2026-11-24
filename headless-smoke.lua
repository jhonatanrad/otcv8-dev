-- Smoke test: no graphics, no server, no credentials.
local started = g_clock.millis()
local event
function g_app.onRun()
  event = g_dispatcher.scheduleEvent("headless smoke", function()
    assert(g_app.getGraphicsFps() == 0, "Graphics frames were produced")
    assert(not g_game.isOnline(), "Smoke test must remain offline")
    g_logger.info("[HEADLESS] SMOKE_OK: Lua and event loop without graphics")
    g_app.exit()
  end, tonumber(os.getenv("OTC_HEADLESS_SMOKE_MS")) or 200)
end
