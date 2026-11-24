-- Standalone Lua entry point. Does not load UI, updater, or graphical bot.
-- The local configuration is never committed; it must be supplied by the operator.
G = {}
dofile("/modules/corelib/const.lua")
dofile("/modules/corelib/string.lua")
dofile("/modules/corelib/table.lua")
dofile("/modules/corelib/util.lua")
dofile("/modules/gamelib/const.lua")
dofile("/modules/gamelib/game.lua")
dofile("/modules/corelib/net.lua")
dofile("/modules/gamelib/protocol.lua")
dofile("/modules/gamelib/protocollogin.lua")
if not iptostring then
  function iptostring(ip)
    return string.format("%d.%d.%d.%d", ip % 256, math.floor(ip/256)%256, math.floor(ip/65536)%256, math.floor(ip/16777216)%256)
  end
end
dofile("/headless-dat.lua")
dofile("/headless-cavebot.lua")
local loginProtocol
local cavebot

local profile = os.getenv("OTC_HEADLESS_PROFILE") or ""
local configPath = profile ~= "" and ("/profiles/" .. profile .. ".lua") or "/headless-local.lua"
local config = nil
local scheduled = nil
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
  local dat=config.dat or "/data/things/860/Tibia.dat"
  assert(g_resources.fileExists(dat), "Tibia.dat not found in data/things/860")
  HeadlessDat.load(dat,config,log)
  if config.minimap and config.minimap ~= "" then
    g_minimap.loadOtmm(config.minimap)
  end
end

local function tick()
  if not running or not g_game.isOnline() then return end
  local player=g_game.getLocalPlayer()
  if not player or player:isDead() then schedule(tick,500);return end
  local pos=player:getPosition()
  if not pos or pos.x==65535 or pos.z>15 then schedule(tick,500);return end
  local key=pos.x..","..pos.y..","..pos.z
  if key~=lastLoggedPosition then log("Player position: "..key);lastLoggedPosition=key end
  if cavebot then
    local ok,err=pcall(function() cavebot:tick(pos,g_clock.millis(),player:isWalking() or player:isAutoWalking() or player:isPreWalking()) end)
    if not ok then log("CaveBot stopped: "..tostring(err));cavebot=nil end
  end
  schedule(tick,cavebot and not cavebot.finished and 250 or 1000)
end
local function onStart()
  log("Game started; waiting for confirmed local-player position")
  if not config.enableRoute then log("Login-only test: automatic movement disabled") end
  running = true
  if config.enableRoute then
    local player=g_game.getLocalPlayer()
    cavebot=HeadlessCaveBot.new(config,{
      log=log,
      reachable=function(a,b)
        if a.z~=b.z then return false end
        local path,result=g_map.findPath(a,b,10000,0)
        return type(path)=="table" and #path>0 and result==PathFindResults.Ok
      end,
      walk=function(p) player:autoWalk(p,false) end,
      stop=function() player:stopAutoWalk();g_game.stop() end,
      use=function(p,id)
        local tile=g_map.getTile(p)
        if not tile then return false end
        for _,thing in ipairs(tile:getThings()) do
          if thing:isItem() and thing:getId()==id then g_game.use(thing);return true end
        end
        return false
      end
    })
  end
  schedule(tick, 250)
end

local function onEnd()
  running = false
  cavebot=nil
  if scheduled then scheduled:cancel(); scheduled = nil end
  log("Disconnected.")
  g_dispatcher.scheduleEvent("exit disconnected", function() g_app.exit() end, 100)
end

local function begin()
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
  config.password = os.getenv("OTC_HEADLESS_PASSWORD") or config.password
  assert(type(config.password) == "string" and config.password ~= "", "Password required")
  assert(type(config.character) == "string" and config.character ~= "", "Character required")
  if config.enableRoute then
    assert(type(config.target) == "table" and config.target.z, "Target position required")
  end
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
    onLoginError = function(message) log("Login rejected: " .. tostring(message)); g_dispatcher.scheduleEvent("exit rejected login", function() g_app.exit() end, 100) end,
    onConnectionError = function(message) log("Connection error: " .. tostring(message)); g_dispatcher.scheduleEvent("exit failed connection", function() g_app.exit() end, 100) end,
    onTextMessage = function(mode, message) log("Server: " .. tostring(message)) end
  })
  -- Direct world endpoint, not a login/character-list endpoint.
  log("Configured login port " .. tostring(config.loginPort or 7171) .. "; world port " .. config.port)
  g_dispatcher.scheduleEvent("login deadline", function()
    if not g_game.isOnline() then log("Login timeout"); if loginProtocol then loginProtocol:disconnect() end; g_game.cancelLogin(); g_app.exit() end
  end, 45000)
  local function enterWorld(host, port, world)
    log("Connecting to world endpoint " .. host .. ":" .. port)
    g_game.loginWorld(config.account, config.password, world, host, port, config.character, "", "", "")
    config.password = nil
  end
  if config.loginPort then
    assert(type(config.loginPort) == "number" and config.loginPort >= 1 and config.loginPort <= 65535, "Invalid login port")
    local function readSignature(path)
      local f = io.open(path, "rb")
      if not f then return nil end
      local raw = f:read(4)
      f:close()
      if not raw or #raw ~= 4 then return nil end
      local a,b,c,d=raw:byte(1,4)
      return a+b*256+c*65536+d*16777216
    end
    local spr = readSignature("data/things/860/Tibia.spr.header")
    local pic = readSignature("data/things/860/Tibia.pic.header")
    assert(spr and pic, "Import DAT with matching Tibia.spr and Tibia.pic alongside it (only their headers are copied)")
    G.headlessSprSignature = spr
    PIC_SIGNATURE = pic
    loginProtocol = ProtocolLogin.create()
    loginProtocol.onLoginError = function(_, message)
      log("Login rejected: " .. tostring(message))
      config.password = nil
      g_dispatcher.scheduleEvent("exit rejected login", function() g_app.exit() end, 100)
    end
    loginProtocol.onCharacterList = function(_, characters)
      for _, char in ipairs(characters) do
        if char.name == config.character then
          local host = char.worldIp
          local port = config.port
          if type(host) ~= "string" or host == "" or host == "0.0.0.0" then
            log("Invalid world endpoint returned by login server")
            g_app.exit()
            return
          end
          log("Character authenticated; advertised world port " .. tostring(char.worldPort))
          g_dispatcher.scheduleEvent("enter authenticated world", function()
            enterWorld(host, port, char.worldName or "OTServer")
          end, 100)
          return
        end
      end
      log("Login rejected: configured character not present in account list")
      config.password = nil
      g_app.exit()
    end
    log("Authenticating at " .. config.host .. ":" .. config.loginPort)
    loginProtocol:login(config.host, config.loginPort, config.account, config.password, "", false)
  else
    enterWorld(config.host, config.port, config.world or "OTServer")
  end
end

function g_app.onRun()
  local ok, err = pcall(begin)
  if not ok then
    g_logger.error("[HEADLESS] Startup failed: " .. tostring(err))
    g_app.exit()
  end
end

function g_app.onTerminate()
  running = false
  if scheduled then scheduled:cancel(); scheduled = nil end
end
