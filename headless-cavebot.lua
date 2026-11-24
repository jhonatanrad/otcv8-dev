-- UI-independent waypoint runner using the OTCv8 native map and movement API.
-- This is not a drop-in replacement for graphical vBot scripts.
HeadlessCaveBot = {}
local function same(a,b) return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
local function dist(a,b) return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y)) end
local function valid(p) return p and type(p.x)=="number" and type(p.y)=="number" and type(p.z)=="number" and p.x>=0 and p.x<65535 and p.y>=0 and p.y<65535 and p.z>=0 and p.z<=15 end
function HeadlessCaveBot.new(config, api)
  assert(valid(config.target),"Invalid destination")
  local bot={floor=nil,index=nil,finished=false,last=nil,lastMove=0,lastAttempt=-1000,goal=nil,blocked={},reason=nil}
  function bot:finish(reason)
    self.finished=true
    self.reason=reason
    api.log(reason)
  end
  function bot:choose(pos,now)
    local target=config.target
    local approach=config.approach or {}
    if pos.z==target.z then
      if same(pos,target) then return target end
      if not self.blocked["target"] or self.blocked["target"]<=now then
        if api.reachable(pos,target) then return target,"target" end
        self.blocked["target"]=now+1500
      end
      -- Optional same-floor intermediate waypoints. Only reachable points that
      -- bring us closer to the destination are selected.
      local best, bestScore, bestKey
      for i,p in ipairs(config.floorWaypoints or approach) do
        if valid(p) and p.z==pos.z and not same(pos,p) and dist(p,target)<dist(pos,target) and (not self.blocked[i] or self.blocked[i]<=now) then
          local score=dist(pos,p)+dist(p,target)
          if (not bestScore or score<bestScore) and api.reachable(pos,p) then best,bestScore,bestKey=p,score,i end
        end
      end
      return best,bestKey
    end
    if self.index then
      while approach[self.index] and same(pos,approach[self.index]) do self.index=self.index+1 end
      local p=approach[self.index]
      if p and p.z==pos.z and (not self.blocked[self.index] or self.blocked[self.index]<=now) and api.reachable(pos,p) then return p,self.index end
    end
    local best,bestDistance,bestIndex
    for i,p in ipairs(approach) do
      if valid(p) and p.z==pos.z and not same(pos,p) and (not self.index or i>=self.index) and (not self.blocked[i] or self.blocked[i]<=now) then
        local d=dist(pos,p)
        if (not bestDistance or d<bestDistance) and api.reachable(pos,p) then best,bestDistance,bestIndex=p,d,i end
      end
    end
    if bestIndex then self.index=bestIndex end
    return best,bestIndex
  end
  function bot:tick(pos,now,busy)
    if self.finished or not valid(pos) then return end
    if self.floor~=pos.z then
      self.floor=pos.z;self.index=nil;self.goal=nil;self.blocked={};self.lastMove=now
      api.log("CaveBot: confirmed floor "..pos.z)
    end
    if not same(self.last,pos) then self.last={x=pos.x,y=pos.y,z=pos.z};self.lastMove=now end
    if self.goal and same(pos,self.goal) then self.goal=nil end
    if busy then
      if now-self.lastMove>5000 and self.goal then
        api.stop()
        if self.goalKey then self.blocked[self.goalKey]=now+1500 end
        self.goal=nil;self.lastAttempt=now
        api.log("CaveBot: movement stalled; recalculating")
      end
      return
    end
    if same(pos,config.target) then
      if not config.usePosition then self:finish("CaveBot: destination reached");return end
      if config.usePosition.z~=pos.z or dist(pos,config.usePosition)>1 then self:finish("CaveBot: object is not adjacent to destination");return end
      if now-self.lastAttempt<500 then return end
      self.lastAttempt=now
      if api.use(config.usePosition,config.useItemId) then self:finish("CaveBot: USE requested; server acknowledgement not verified") end
      return
    end
    if now-self.lastAttempt<500 then return end
    self.lastAttempt=now
    if self.goal and now-self.lastMove>3000 then
      if self.goalKey then self.blocked[self.goalKey]=now+1500 end
      self.goal=nil
    end
    local goal,key=self:choose(pos,now)
    if goal and not same(pos,goal) then
      if not same(self.goal,goal) then self.lastMove=now end
      self.goal=goal;self.goalKey=key
      api.walk(goal)
    end
  end
  return bot
end
