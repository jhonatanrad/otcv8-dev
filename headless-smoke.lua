-- Smoke test: no graphics, no server, no credentials.
local started = g_clock.millis()
local event
local proxyTest = os.getenv("OTC_HEADLESS_PROXY_TEST") == "1"
local protocol
function g_app.onRun()
  if proxyTest then
    protocol = Protocol.create()
    protocol.onConnect = function()
      assert(protocol:isConnected(), "SOCKS connection not established")
      g_logger.info("[HEADLESS] SOCKS_SMOKE_OK")
      protocol:disconnect()
      g_app.exit()
    end
    protocol.onError = function(message) g_logger.error("SOCKS smoke failed: " .. tostring(message)) end
    protocol:connect("example.invalid", 7172)
    g_dispatcher.scheduleEvent("SOCKS test timeout", function() g_logger.error("SOCKS test timed out") end, 10000)
    return
  end
  event = g_dispatcher.scheduleEvent("headless smoke", function()
    assert(g_app.getGraphicsFps() == 0, "Graphics frames were produced")
    assert(not g_game.isOnline(), "Smoke test must remain offline")
    g_logger.info("[HEADLESS] SMOKE_OK: Lua and event loop without graphics")
    g_app.exit()
  end, tonumber(os.getenv("OTC_HEADLESS_SMOKE_MS")) or 200)
end
