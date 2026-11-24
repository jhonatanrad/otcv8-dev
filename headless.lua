-- Standalone Lua entry point. Does not load UI, updater, or graphical bot.
-- The local configuration is never committed; it must be supplied by the operator.
G = {}
dofile("/modules/corelib/const.lua")
dofile("/modules/corelib/string.lua")
dofile("/modules/corelib/table.lua")
dofile("/modules/corelib/util.lua")
dofile("/modules/gamelib/const.lua")
dofile("/modules/gamelib/game.lua")

local configPath = "/headless-local.lua"
local config = nil
local scheduled = nil
local lastPosition = nil
local lastAttempt = 0
local lastUse = 0
local lastLoggedPosition = ""
local running = false
local index = 1
local finished = false

local function schedule(callback, delay)
  scheduled = g_dispatcher.scheduleEvent("headless navigation", callback, delay)
end

local function log(message)
  g_logger.info("[HEADLESS] " .. message)
end

local function loadAssets()
  if config.extended then g_game.enableFeature(GameSpritesU32) end
  if config.frameGroups then g_game.enableFeature(GameIdleAnimations) end
  if config.frameDurations then g_game.enableFeature(GameEnhancedAnimations) end
  assert(g_things.loadDat(config.dat or "/data/things/860/Tibia.dat"),
    "Unable to load DAT; check file and format flags")
  if config.minimap and config.minimap ~= "" then
    g_minimap.loadOtmm(config.minimap)
  end
end

local function equals(a, b)
  return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

local function distance(a, b)
  return math.max(math.abs(a.x-b.x), math.abs(a.y-b.y))
end

local function stopRoute(message)
  finished = true
  log(message)
end

local function tick()
  if not running or finished or not g_game.isOnline() then return end
  local player = g_game.getLocalPlayer()
  if not player or player:isDead() then return end
  local pos = player:getPosition()
  if not pos or pos.x == 65535 or pos.z > 15 then schedule(tick, 250); return end

  local key = pos.x .. "," .. pos.y .. "," .. pos.z
  if key ~= lastLoggedPosition then
    log("Player position: " .. key)
    lastLoggedPosition = key
  end

  local target = config.target
  local cart = config.usePosition
  local now = g_clock.millis()
  local current = nil
  if pos.z == target.z then
    -- No previous-floor waypoint may be executed once on the destination floor.
    current = target
  else
    local wp = config.approach or {}
    while wp[index] and equals(pos, wp[index]) do index = index + 1 end
    current = wp[index]
    if not current or current.z ~= pos.z then
      stopRoute("No confirmed approach waypoint on current floor; stopping route.")
      return
    end
  end

  if equals(pos, target) and cart and cart.z == pos.z and distance(pos, cart) <= 1 then
    local tile = g_map.getTile(cart)
    if tile then
      for _, thing in ipairs(tile:getThings()) do
        if thing:isItem() and thing:getId() == config.useItemId then
          if now - lastUse >= 1000 then
            lastUse = now
            g_game.use(thing)
            -- Sending USE is not proof of a successful server action.
            stopRoute("USE requested on configured item; server confirmation not implemented.")
            return
          end
        end
      end
    end
  elseif equals(pos, target) and not cart then
    stopRoute("Destination reached.")
    return
  elseif not equals(pos, current) and not player:isAutoWalking() and not player:isWalking() and now-lastAttempt >= 500 then
    lastAttempt = now
    -- Use OTC's existing asynchronous pathfinder; no UI or render loop.
    player:autoWalk(current, false)
  end
  lastPosition = pos
  schedule(tick, 250)
end

local function onStart()
  log("Game started; waiting for confirmed local-player position")
  running = true
  finished = false
  index = 1
  schedule(tick, 250)
end

local function onEnd()
  running = false
  if scheduled then scheduled:cancel(); scheduled = nil end
  log("Disconnected.")
end

function g_app.onRun()
  log("Running without window or graphical initialization.")
  if not g_resources.fileExists(configPath) then
    log("No local configuration. Copy headless-local.example.lua to headless-local.lua; no login attempted.")
    g_app.exit()
    return
  end
  config = dofile(configPath)
  assert(type(config) == "table", "Local configuration must return a table")
  assert(type(config.host) == "string" and config.host ~= "", "World host required")
  assert(type(config.port) == "number" and config.port >= 1 and config.port <= 65535, "World port required")
  assert(type(config.account) == "string" and config.account ~= "", "Account required")
  assert(type(config.password) == "string" and config.password ~= "", "Password required")
  assert(type(config.character) == "string" and config.character ~= "", "Character required")
  assert(type(config.target) == "table" and config.target.z, "Target position required")
  -- Reuse the standard OTC feature selection with a DAT-only asset adapter.
  modules = { game_things = { load = loadAssets } }
  dofile("/modules/game_features/features.lua")
  g_game.setProtocolVersion(860)
  g_game.setClientVersion(860)
  updateFeatures(860)
  if config.rsa then g_game.setRsa(config.rsa) else g_game.chooseRsa(config.host) end
  if config.customOs then g_game.setCustomOs(config.customOs) end
  connect(g_game, {
    onGameStart = onStart,
    onGameEnd = onEnd,
    onLoginError = function(message) log("Login rejected: " .. tostring(message)) end,
    onConnectionError = function(message) log("Connection error: " .. tostring(message)) end,
    onTextMessage = function(mode, message) log("Server: " .. tostring(message)) end
  })
  -- Direct world endpoint, not a login/character-list endpoint.
  g_game.loginWorld(config.account, config.password, config.world or "OTServer",
    config.host, config.port, config.character, "", "", "")
end

function g_app.onTerminate()
  running = false
  if scheduled then scheduled:cancel(); scheduled = nil end
end
