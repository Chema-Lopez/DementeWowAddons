local ADDON="SimpleTransmogWishlist"
local STW=CreateFrame("Frame")

STW_DB=STW_DB or {
  items={}, order={}, tracked={}, sources={}, pending={},
  ui={x=300,y=300,shown=false}
}

SLASH_STW1="/stw"

-- English by default; Spanish when the client is esES.
local L = setmetatable({}, { __index = function(_, k) return k end })
if GetLocale() == "esES" then
  for k, v in pairs({
    ["Boss"] = "Jefe",
    ["Instance"] = "Instancia",
    ["(No known sources for this appearance)"] = "(Sin fuentes conocidas para esta apariencia)",
    ["Invalid ID"] = "ID inválido",
    ["Already on the list."] = "Ya estaba en la lista.",
    ["You already know that appearance."] = "Ya conoces esa apariencia.",
    ["Appearance already learned, not added."] = "Apariencia ya aprendida, no se añade.",
    ["No known source, not added."] = "Sin origen conocido, no se añade.",
    ["Added: "] = "Añadido: ",
    ["Loading item data..."] = "Cargando datos del objeto...",
    ["Not on the list."] = "No estaba en la lista.",
    ["Removed: "] = "Eliminado: ",
    ["Commands: /stw add <itemID> | /stw del <itemID> | /stw ui | /stw refresh"] = "Comandos: /stw add <itemID> | /stw del <itemID> | /stw ui | /stw refresh",
    ["Unknown command: "] = "Comando desconocido: ",
    ["Appearance learned and removed!"] = "¡Apariencia aprendida y eliminada!",
    ["[▲ Up]"] = "[▲ Subir]",
    ["[▼ Down]"] = "[▼ Bajar]",
    ["[X Remove]"] = "[X Eliminar]",
    ["[Loading…]"] = "[Cargando…]",
    ["LOADING ITEM DATA…"] = "CARGANDO DATOS DEL OBJETO…",
    ["The list is empty"] = "No hay objetos en la lista",
    ["Add ID"] = "Añadir ID",
  }) do L[k] = v end
end

local function msg(t) DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88STW|r "..t) end

local function indexOf(tbl, val)
  for i,v in ipairs(tbl) do if v==val then return i end end
end

local function ensureOrderHas(id)
  if not indexOf(STW_DB.order,id) then table.insert(STW_DB.order,id) end
end

local function ensureItemLink(itemID)
  local l=select(2,C_Item.GetItemInfo(itemID))
  if l then return l end
  C_Item.RequestLoadItemDataByID(itemID)
  STW_DB.pending[itemID]=true
  return nil
end

local function collectSourcesForAppearance(appID)
  local out={}
  local add=function(srcID)
    if srcID and not out[srcID] then
      local info=C_TransmogCollection.GetSourceInfo(srcID)
      if info then out[srcID]=info end
    end
  end
  local s
  local ok,res=pcall(function()
    if Enum and Enum.TransmogType and Enum.TransmogType.Appearance then
      return C_TransmogCollection.GetAppearanceSources(appID, Enum.TransmogType.Appearance)
    else
      return C_TransmogCollection.GetAppearanceSources(appID)
    end
  end)
  if ok then s=res end
  if s then for _,v in ipairs(s) do add(v.sourceID) end end
  if (not s or next(out)==nil) and C_TransmogCollection.GetAllAppearanceSources then
    local ids=C_TransmogCollection.GetAllAppearanceSources(appID)
    if ids then for _,srcID in ipairs(ids) do add(srcID) end end
  end
  local list={} for _,info in pairs(out) do list[#list+1]=info end
  return list
end

local function hasKnownOrigin(sourceID, si)
  if not si then return false end
  if si.sourceText and si.sourceText~="" then return true end
  local drops=C_TransmogCollection.GetAppearanceSourceDrops and C_TransmogCollection.GetAppearanceSourceDrops(sourceID)
  if drops and #drops>0 then return true end
  return false
end

local function anyCollectedSource(pool)
  for _,si in pairs(pool or {}) do if si.isCollected then return true end end
  return false
end

local function resolveItem(itemID)
  if not itemID then return end
  local link=ensureItemLink(itemID)
  if not link then return false end
  local appID,srcID=C_TransmogCollection.GetItemInfo(link)
  if not appID then return false end
  STW_DB.tracked[itemID]={appearanceID=appID,sourceID=srcID}
  local srcs=collectSourcesForAppearance(appID)
  local kept={}
  for _,si in ipairs(srcs) do
    if hasKnownOrigin(si.sourceID,si) then kept[si.sourceID]=si end
  end
  STW_DB.sources[appID]=kept
  STW_DB.pending[itemID]=nil
  return true
end

local function dropLines(sourceID)
  local t={}
  local drops=C_TransmogCollection.GetAppearanceSourceDrops and C_TransmogCollection.GetAppearanceSourceDrops(sourceID)
  if drops then
    for _,d in ipairs(drops) do
      local enc=d.encounter or L["Boss"]
      local inst=d.instance or L["Instance"]
      local diff=d.difficulty or ""
      t[#t+1]=enc.." — "..inst.." "..diff
    end
  end
  return t
end

local function sourceBaseName(si)
  local link=si.itemID and select(2,C_Item.GetItemInfo(si.itemID))
  return link or si.name or ("ID "..tostring(si.sourceID))
end

local function sourcesText(appID)
  local pool=STW_DB.sources[appID] or {}
  local lines={}
  for _,si in pairs(pool) do
    local drops=dropLines(si.sourceID)
    local base=sourceBaseName(si)
    if drops and #drops>0 then
      for _,dl in ipairs(drops) do lines[#lines+1]=("|cffffd100"..base.."|r — "..dl) end
    elseif si.sourceText and si.sourceText~="" then
      lines[#lines+1]=("|cffffd100"..base.."|r — "..si.sourceText)
    end
  end
  if #lines==0 then lines[1]=L["(No known sources for this appearance)"] end
  return table.concat(lines,"\n")
end

local function removeAppearance(appID)
  local del={}
  for itemID,rec in pairs(STW_DB.tracked) do
    if rec.appearanceID==appID then del[#del+1]=itemID end
  end
  for _,id in ipairs(del) do
    STW_DB.items[id]=nil
    STW_DB.tracked[id]=nil
    local i=indexOf(STW_DB.order,id); if i then table.remove(STW_DB.order,i) end
  end
  STW_DB.sources[appID]=nil
end

local function addItem(itemID)
  if not tonumber(itemID) then msg(L["Invalid ID"]); return end
  itemID=tonumber(itemID)
  if STW_DB.items[itemID] then ensureOrderHas(itemID) STW_UpdateUI() msg(L["Already on the list."]); return end
  local link=select(2,C_Item.GetItemInfo(itemID))
  if link and C_TransmogCollection.PlayerHasTransmogByItemInfo(link) then msg(L["You already know that appearance."]); return end
  STW_DB.items[itemID]=true
  ensureOrderHas(itemID)
  local ok=resolveItem(itemID)
  if ok then
    link=select(2,C_Item.GetItemInfo(itemID)) or ("item:"..itemID)
    local rec=STW_DB.tracked[itemID]; local appID=rec and rec.appearanceID
    local pool=appID and STW_DB.sources[appID]
    if appID and C_TransmogCollection.PlayerHasTransmog(appID) then
      removeAppearance(appID) msg(L["Appearance already learned, not added."])
    elseif pool and not next(pool) then
      STW_DB.items[itemID]=nil STW_DB.tracked[itemID]=nil
      local i=indexOf(STW_DB.order,itemID); if i then table.remove(STW_DB.order,i) end
      msg(L["No known source, not added."])
    else
      msg(L["Added: "]..link)
    end
  else
    msg(L["Loading item data..."])
  end
  STW_UpdateUI()
end

local function delItem(itemID)
  itemID=tonumber(itemID)
  if not itemID or not STW_DB.items[itemID] then msg(L["Not on the list."]); return end
  local appID=STW_DB.tracked[itemID] and STW_DB.tracked[itemID].appearanceID
  STW_DB.items[itemID]=nil STW_DB.tracked[itemID]=nil STW_DB.pending[itemID]=nil
  local i=indexOf(STW_DB.order,itemID); if i then table.remove(STW_DB.order,i) end
  if appID then
    local still=false
    for _,rec in pairs(STW_DB.tracked) do if rec.appearanceID==appID then still=true break end end
    if not still then STW_DB.sources[appID]=nil end
  end
  STW_UpdateUI() msg(L["Removed: "]..(select(2,C_Item.GetItemInfo(itemID)) or itemID))
end

local function visibleIDs()
  local ids={}
  for _,id in ipairs(STW_DB.order) do
    if STW_DB.items[id] then
      local rec=STW_DB.tracked[id]
      local appID=rec and rec.appearanceID or 0
      local pend=STW_DB.pending[id]
      local pool=STW_DB.sources[appID]
      local known=C_TransmogCollection.PlayerHasTransmog(appID) or anyCollectedSource(pool)
      if not known and (pend or (pool and next(pool))) then table.insert(ids,id) end
    end
  end
  return ids
end

local function moveVisible(id,dir)
  local vis=visibleIDs()
  local pos
  for i,v in ipairs(vis) do if v==id then pos=i break end end
  if not pos then return end
  local target=dir==-1 and (pos-1) or (pos+1)
  if target<1 or target>#vis then return end
  local a,b=vis[pos],vis[target]
  local ia=indexOf(STW_DB.order,a); local ib=indexOf(STW_DB.order,b)
  if ia and ib then STW_DB.order[ia],STW_DB.order[ib]=STW_DB.order[ib],STW_DB.order[ia] end
end

local function refreshResolutions()
  for _,id in ipairs(STW_DB.order) do ensureItemLink(id) end
  C_Timer.After(0.3,function()
    for _,id in ipairs(STW_DB.order) do resolveItem(id) end
    local clean={}
    for _,rec in pairs(STW_DB.tracked) do
      if C_TransmogCollection.PlayerHasTransmog(rec.appearanceID) then clean[#clean+1]=rec.appearanceID end
    end
    for _,appID in ipairs(clean) do removeAppearance(appID) end
    STW_UpdateUI()
  end)
end

SlashCmdList["STW"]=function(txt)
  local cmd,arg=txt:match("^(%S+)%s*(.-)$")
  if not cmd or cmd=="" or cmd=="help" then
    msg(L["Commands: /stw add <itemID> | /stw del <itemID> | /stw ui | /stw refresh"])
    return
  end
  if cmd=="add" then addItem(tonumber(arg))
  elseif cmd=="del" then delItem(tonumber(arg))
  elseif cmd=="ui" then STW_ToggleUI()
  elseif cmd=="refresh" then refreshResolutions()
  else msg(L["Unknown command: "]..cmd) end
end

STW:SetScript("OnEvent",function(_,e,...)
  if e=="ADDON_LOADED" then
    local n=...
    if n==ADDON then
      STW_DB.items=STW_DB.items or {}
      STW_DB.order=STW_DB.order or {}
      STW_DB.tracked=STW_DB.tracked or {}
      STW_DB.sources=STW_DB.sources or {}
      STW_DB.pending=STW_DB.pending or {}
      C_Timer.After(0.1,function()
        for _,id in ipairs(STW_DB.order) do ensureItemLink(id) end
        C_Timer.After(0.3,function() for _,id in ipairs(STW_DB.order) do resolveItem(id) end STW_UpdateUI() end)
      end)
      STWAddBtn:SetText(L["Add ID"])
      if STW_DB.ui.shown then STW_ShowUI() end
    end
  elseif e=="GET_ITEM_INFO_RECEIVED" or e=="ITEM_DATA_LOAD_RESULT" then
    local id=...
    if id and STW_DB.items[id] then resolveItem(id) STW_UpdateUI() end
  elseif e=="TRANSMOG_COLLECTION_SOURCE_ADDED" then
    local sid=...
    local si=C_TransmogCollection.GetSourceInfo(sid)
    if si and si.appearanceID then removeAppearance(si.appearanceID) msg(L["Appearance learned and removed!"]) STW_UpdateUI() end
  end
end)

STW:RegisterEvent("ADDON_LOADED")
STW:RegisterEvent("GET_ITEM_INFO_RECEIVED")
STW:RegisterEvent("ITEM_DATA_LOAD_RESULT")
STW:RegisterEvent("TRANSMOG_COLLECTION_SOURCE_ADDED")

local function htmlEscape(s) s=tostring(s or "") s=s:gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;") return s end

function STW_GetRows()
  local rows={}
  for i,id in ipairs(STW_DB.order) do
    if STW_DB.items[id] then
      local link=select(2,C_Item.GetItemInfo(id)) or ("item:"..id)
      local rec=STW_DB.tracked[id]
      local appID=rec and rec.appearanceID or 0
      local pend=STW_DB.pending[id]
      local pool=STW_DB.sources[appID]
      local known=C_TransmogCollection.PlayerHasTransmog(appID) or anyCollectedSource(pool)
      if not known and (pend or (pool and next(pool))) then
        local up=(i>1) and ("|Hstwup:"..id.."|h|cff99ccff"..L["[▲ Up]"].."|r|h") or ("|cff555555"..L["[▲ Up]"].."|r")
        local dn=(i<#STW_DB.order) and ("|Hstwdown:"..id.."|h|cff99ccff"..L["[▼ Down]"].."|r|h") or ("|cff555555"..L["[▼ Down]"].."|r")
        local del="|Hstwdel:"..id.."|h|cffff5555"..L["[X Remove]"].."|r|h"
        local head=(pend and "|cffffa000"..L["[Loading…]"].."|r " or "")..up.."  "..dn.."  "..del.."  "..(link or ("item:"..id)).."  |cffa0a0a0app:"..appID.."|r"
        local body=pend and L["LOADING ITEM DATA…"] or sourcesText(appID)
        rows[#rows+1]={id=id,head=head,body=body}
      end
    end
  end
  return rows
end

function STW_UpdateUI()
  if not STWFrame or not STWFrame:IsShown() then return end
  local rows=STW_GetRows()
  local html="<html><body>"
  if #rows==0 then
    html=html.."<p>"..L["The list is empty"].."</p>"
  else
    for _,r in ipairs(rows) do
      html=html.."<p>"..r.head.."</p>"
      html=html.."<p>"..htmlEscape(r.body):gsub("\n","<br/>").."</p><br/>"
    end
  end
  html=html.."</body></html>"
  STWHTML:SetText(html)
end

function STW_ShowUI()
  STWFrame:ClearAllPoints()
  STWFrame:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",STW_DB.ui.x or 300, STW_DB.ui.y or 300)
  STWFrame:Show()
end

function STW_HideUI() STWFrame:Hide() end
function STW_ToggleUI() if STWFrame:IsShown() then STW_HideUI() else STW_ShowUI() end end

function STW_OnHTMLClick(self,link,text,btn)
  if IsControlKeyDown() and link and link:find("^item:") then DressUpItemLink(link) return end
  local cmd,id=link:match("^(%w+):(%d+)$"); id=tonumber(id)
  if cmd=="stwdel" then delItem(id)
  elseif cmd=="stwup" then
    local visIndex
    local vis={}
    for _,r in ipairs(STW_DB.order) do if STW_DB.items[r] then table.insert(vis,r) end end
    for i,v in ipairs(vis) do if v==id then visIndex=i break end end
    if visIndex and visIndex>1 then
      local a=vis[visIndex]; local b=vis[visIndex-1]
      local ia=indexOf(STW_DB.order,a); local ib=indexOf(STW_DB.order,b)
      if ia and ib then STW_DB.order[ia],STW_DB.order[ib]=STW_DB.order[ib],STW_DB.order[ia] end
    end
    STW_UpdateUI()
  elseif cmd=="stwdown" then
    local vis={}
    for _,r in ipairs(STW_DB.order) do if STW_DB.items[r] then table.insert(vis,r) end end
    local visIndex
    for i,v in ipairs(vis) do if v==id then visIndex=i break end end
    if visIndex and visIndex<#vis then
      local a=vis[visIndex]; local b=vis[visIndex+1]
      local ia=indexOf(STW_DB.order,a); local ib=indexOf(STW_DB.order,b)
      if ia and ib then STW_DB.order[ia],STW_DB.order[ib]=STW_DB.order[ib],STW_DB.order[ia] end
    end
    STW_UpdateUI()
  end
end
