-- Invoked once on an observed, naturally generated chest by the opt-in route.
local id=GetUpdatedEntityID()
local path=EntityGetFilename(id)
if path=="data/entities/items/pickup/chest_random.xml" then
 dofile("data/scripts/items/chest_random.lua")
elseif path=="data/entities/items/pickup/chest_random_super.xml" then
 dofile("data/scripts/items/chest_random_super.lua")
else return end
local player=(EntityGetWithTag("player_unit") or {})[1]
if player then item_pickup(id,player,"")end
