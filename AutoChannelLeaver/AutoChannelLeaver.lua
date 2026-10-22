-- Leaves the chosen chat channels on any character after logging in.
-- The settings are account-wide (AutoChannelLeaverDB), so they apply to every character.
local ADDON = ...

-- Channels are matched by the start of their name, for English and Spanish clients.
-- Blizzard does not document zoneChannelID values, so they are only shown by /acl list.
local CHANNELS = {
  { key = "trade",        default = true,  patterns = { "^trade", "^comercio" } },
  { key = "services",     default = true,  patterns = { "^services", "^servicios" } },
  { key = "general",      default = false, patterns = { "^general" } },
  { key = "localdefense", default = false, patterns = { "^localdefense", "^defensalocal" } },
  { key = "lfg",          default = false, patterns = { "^lookingforgroup", "^buscargrupo" } },
  { key = "newcomer",     default = false, patterns = { "^newcomerchat", "^novato" } },
}

-- English by default; Spanish when the client is esES.
local L = setmetatable({}, { __index = function(_, k) return k end })
L.trade, L.services, L.general = "Trade", "Services", "General"
L.localdefense, L.lfg, L.newcomer = "Local Defense", "Looking For Group", "Newcomer Chat"
if GetLocale() == "esES" then
  L.trade, L.services, L.general = "Comercio", "Servicios", "General"
  L.localdefense, L.lfg, L.newcomer = "Defensa local", "Buscar grupo", "Novatos"
  for k, v in pairs({
    ["Leave this channel automatically on every character. Unchecking it does not join it again: use /join."] = "Salir de este canal automáticamente en todos los personajes. Al desmarcarlo no se vuelve a entrar: usa /join.",
    ["Joined channels (zoneChannelID):"] = "Canales en los que estás (zoneChannelID):",
    ["leaving"] = "saliendo",
    ["kept"] = "se mantiene",
    ["Commands: /acl (options) | /acl list"] = "Comandos: /acl (opciones) | /acl list",
  }) do L[k] = v end
end

local function msg(t) DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88AutoChannelLeaver|r " .. t) end

local db
local category

local function channelKey(name)
  if not name then return nil end
  name = name:lower()
  for _, ch in ipairs(CHANNELS) do
    for _, p in ipairs(ch.patterns) do
      if name:find(p) then return ch.key end
    end
  end
end

local function shouldLeave(name)
  local key = channelKey(name)
  return key and db and db.leave[key]
end

local function leaveChannels()
  if not db then return end
  local list = { GetChannelList() } -- id, name, disabled, id, name, ...
  for i = 1, #list, 3 do
    local name = list[i + 1]
    if shouldLeave(name) then
      LeaveChannelByName(name)
    end
  end
end

local function listChannels()
  msg(L["Joined channels (zoneChannelID):"])
  local list = { GetChannelList() }
  for i = 1, #list, 3 do
    local id, name = list[i], list[i + 1]
    local info = C_ChatInfo.GetChannelInfoFromIdentifier(name)
    local key = channelKey(name)
    local state = key and (db.leave[key] and ("|cffff6060" .. L["leaving"] .. "|r") or L["kept"]) or "-"
    msg(("  %d. %s (%s) — %s %s"):format(id, name, info and tostring(info.zoneChannelID) or "?", key and L[key] or "?", state))
  end
end

local function registerSettings()
  category = Settings.RegisterVerticalLayoutCategory("AutoChannelLeaver")
  local tooltip = L["Leave this channel automatically on every character. Unchecking it does not join it again: use /join."]
  for _, ch in ipairs(CHANNELS) do
    local variable = "AutoChannelLeaver_" .. ch.key
    local setting = Settings.RegisterAddOnSetting(category, variable, ch.key, db.leave, Settings.VarType.Boolean, L[ch.key], ch.default)
    Settings.CreateCheckbox(category, setting, tooltip)
    Settings.SetOnValueChangedCallback(variable, leaveChannels)
  end
  Settings.RegisterAddOnCategory(category)
end

SLASH_AUTOCHANNELLEAVER1 = "/acl"
SLASH_AUTOCHANNELLEAVER2 = "/autochannelleaver"
SlashCmdList["AUTOCHANNELLEAVER"] = function(txt)
  local cmd = (txt or ""):match("^(%S*)"):lower()
  if cmd == "" then
    Settings.OpenToCategory(category:GetID())
  elseif cmd == "list" then
    listChannels()
  else
    msg(L["Commands: /acl (options) | /acl list"])
  end
end

-- CHANNEL_UI_UPDATE fires in bursts; one pending pass is enough.
local pending = false
local function scheduleLeave(delay)
  if pending then return end
  pending = true
  C_Timer.After(delay, function() pending = false leaveChannels() end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("CHANNEL_UI_UPDATE")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    AutoChannelLeaverDB = AutoChannelLeaverDB or {}
    db = AutoChannelLeaverDB
    db.leave = db.leave or {}
    for _, ch in ipairs(CHANNELS) do
      if db.leave[ch.key] == nil then db.leave[ch.key] = ch.default end
    end
    registerSettings()
    return
  end
  -- Channels are joined a few seconds after logging in; retry with some margin.
  scheduleLeave(3)
  if event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(10, leaveChannels)
  end
end)
