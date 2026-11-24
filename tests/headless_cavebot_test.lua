dofile("/headless-cavebot.lua")
local function p(x,y,z) return {x=x,y=y,z=z} end
local moves,uses={},0
local block=false
local api={log=function() end,reachable=function(a,b) return a.z==b.z and not (block and b.x==160) end,walk=function(q) moves[#moves+1]=q end,stop=function() end,use=function(q,id) uses=uses+1;return id==7131 end}
local bot=HeadlessCaveBot.new({target=p(160,48,8),usePosition=p(160,47,8),useItemId=7131,approach={p(1345,1876,7),p(1346,1876,7),p(155,48,8)}},api)
bot:tick(p(1345,1876,7),1000,false)
assert(moves[1].z==7 and moves[1].x==1346,"approach floor")
block=true
bot:tick(p(152,53,8),2000,false)
assert(moves[2].z==8 and moves[2].x==155,"same floor alternate waypoint")
block=false
bot:tick(p(155,48,8),4000,false)
assert(moves[3].z==8 and moves[3].x==160,"destination after descent")
bot:tick(p(160,48,8),5000,false)
assert(bot.finished and uses==1,"adjacent object use")
bot:tick(p(160,48,8),6000,false)
assert(uses==1,"no duplicate use")
g_logger.info("CAVEBOT_SELFTEST_OK")
