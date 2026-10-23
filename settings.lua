dofile("data/scripts/lib/mod_settings.lua")
local mod_id="interesting_seed_filter"
mod_settings_version=3

-- Settings also run while the mod is disabled. Read the engine language for
-- each draw, without relying on init.lua or publishing score gates in the UI.
local i18n=dofile_once("mods/interesting_seed_filter/files/isf/i18n.lua")
local function text(key,args)return i18n.text(key,args)end
local function integer(value,default,maximum)
 if type(value)~="number"or value~=value or value==math.huge or value==-math.huge then return default end
 return math.max(0,math.min(maximum,math.floor(value+0.5)))
end
local function warning(gui,text)
 GuiColorSetForNextWidget(gui,1,0.65,0.2,1)
 GuiText(gui,mod_setting_group_x_offset,0,text)
end
local function slider(mod,gui,in_main_menu,im_id,setting)
 local id=mod_setting_get_id(mod,setting)
 local old=ModSettingGetNextValue(id)
 local value=integer(old,setting.value_default,setting.value_max)
 local caption=setting.id=="luck_level"and text("luck_caption",{level=value,name=text("luck_"..value)})
  or text("depth_caption",{depth=value,name=text("destination_"..value)})
 -- Put changing text on its own row so dragging never moves the track.
 GuiText(gui,mod_setting_group_x_offset,0,setting.ui_name..": "..caption)
 local changed=GuiSlider(gui,im_id,mod_setting_group_x_offset,0,"",
  value,0,setting.value_max,setting.value_default,1," ",180)
 local next_value=integer(changed,setting.value_default,setting.value_max)
 if old~=next_value then
  ModSettingSetNextValue(id,next_value,false)
  mod_setting_handle_change_callback(mod,gui,in_main_menu,setting,value,next_value)
 end
 mod_setting_tooltip(mod,gui,in_main_menu,setting)
 if setting.id=="luck_level"and next_value==6 then
  warning(gui,text("slow_warning"))
 elseif setting.id=="extra_holy_mountains"and next_value>0 then
  warning(gui,text("depth_warning"))
 end
end
mod_settings={
 {id="luck_level",_name="luck",_description="luck_description",
  value_default=1,value_min=0,value_max=6,ui_fn=slider,scope=MOD_SETTING_SCOPE_NEW_GAME},
 {id="extra_holy_mountains",_name="depth",_description="depth_description",
  value_default=0,value_min=0,value_max=4,ui_fn=slider,scope=MOD_SETTING_SCOPE_NEW_GAME},
 {id="new_game_note",_name="next_game",not_setting=true},
 {id="show_rabbit_foot",_name="charm",_description="charm_description",
  value_default=true,scope=MOD_SETTING_SCOPE_RUNTIME},
 {category_id="diagnostics",_name="diagnostics",foldable=true,_folded=true,settings={
  {id="probe_opt_in",_name="capture",_description="capture_description",value_default=false,scope=MOD_SETTING_SCOPE_NEW_GAME},
  {id="probe_disposable_ack",_name="ack",_description="ack_description",value_default="",text_max_length=32,scope=MOD_SETTING_SCOPE_NEW_GAME},
  {id="probe_run_id",_name="run_id",value_default="",text_max_length=80,scope=MOD_SETTING_SCOPE_NEW_GAME},
  {id="probe_capture_initializers",_name="coordinates",value_default=false,scope=MOD_SETTING_SCOPE_NEW_GAME},
 }},
}
local function localize(settings)
 for _,setting in ipairs(settings)do
  if setting._name then setting.ui_name=text(setting._name)end
  if setting._description then setting.ui_description=text(setting._description)end
  if setting.settings then localize(setting.settings)end
 end
end
localize(mod_settings)
function ModSettingsUpdate(init_scope)mod_settings_update(mod_id,mod_settings,init_scope)end
function ModSettingsGuiCount()return mod_settings_gui_count(mod_id,mod_settings)end
function ModSettingsGui(gui,in_main_menu)
 localize(mod_settings)
 mod_settings_gui(mod_id,mod_settings,gui,in_main_menu)
end
