-- Only accept a complete parse; never invent object metadata or ignore invalid records.
HeadlessDat = {}
function HeadlessDat.load(path, preferred, logger)
  local flags = {GameSpritesU32, GameIdleAnimations, GameEnhancedAnimations}
  local candidates, seen = {}, {}
  local function add(a,b,c)
    local key = tostring(a).."/"..tostring(b).."/"..tostring(c)
    if not seen[key] then
      seen[key]=true
      candidates[#candidates+1]={a,b,c}
    end
  end
  add(preferred.extended==true, preferred.frameGroups==true, preferred.frameDurations==true)
  for _, a in ipairs({true,false}) do
    for _, b in ipairs({true,false}) do
      for _, c in ipairs({false,true}) do add(a,b,c) end
    end
  end
  for _, mode in ipairs(candidates) do
    for i, flag in ipairs(flags) do
      if mode[i] then g_game.enableFeature(flag) else g_game.disableFeature(flag) end
    end
    logger("DAT attempt: extended="..tostring(mode[1]).." frameGroups="..tostring(mode[2]).." frameDurations="..tostring(mode[3]))
    local ok, loaded = pcall(g_things.loadDat,path)
    if ok and loaded and g_things.isDatLoaded() then
      logger("DAT loaded successfully; all records consumed")
      return mode
    end
    collectgarbage("collect")
  end
  error("DAT format not recognized. Use an authorized, compatible unencrypted DAT; inspect [DAT] header and record errors.")
end
