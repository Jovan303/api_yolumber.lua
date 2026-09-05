script_name("YoLumber_v2_Toxic")
script_author("yokana")
script_version("v2.1-Toxic")

require("lib.moonloader")
local imgui = require("mimgui")
local encoding = require("encoding")
local ffi = require("ffi")

encoding.default = "CP1251"
local u8 = encoding.UTF8

local GTASA = nil
pcall(function() GTASA = ffi.load('GTASA') end)
if not GTASA then pcall(function() GTASA = ffi.load('libGTASA.so') end) end

ffi.cdef([[
    void _Z12AND_OpenLinkPKc(const char* link);
]])

local function openLink(url)
    if GTASA then
        GTASA._Z12AND_OpenLinkPKc(url)
    end
end

local windowState = imgui.new.bool(false)
local currentTab = imgui.new.int(1) 
local espEnabled = imgui.new.bool(true)         
local autoGPS = imgui.new.bool(false)            
local soundAlertEnabled = imgui.new.bool(true)  
local scanRadius = imgui.new.float(300.0)
local soundDistance = imgui.new.float(50.0)
local showDown = imgui.new.bool(true) 
local autoEatDrink = imgui.new.bool(false)

local espWeaponEnabled = imgui.new.bool(true)
local weaponEspDistance = imgui.new.float(150.0)

local reduceDamageEnabled = imgui.new.bool(true)
local autoRepairBody = imgui.new.bool(false)
local autoUnflip = imgui.new.bool(false)
local customDamageVal = imgui.new.float(10.0)
local lastVehHandle = 0
local lastVehHealth = 1000.0

local readyTrees = {}
local activeBlip = nil
local notifiedTrees = {}

local flyingVehicles = {
    [417]=true, [425]=true, [447]=true, [460]=true, [464]=true, [469]=true, [476]=true,
    [487]=true, [488]=true, [497]=true, [511]=true, [512]=true, [513]=true, [519]=true,
    [520]=true, [539]=true, [548]=true, [553]=true, [563]=true, [577]=true, [592]=true,
    [593]=true
}

local weaponNames = {
    [22] = "9mm", [23] = "Silenced 9mm", [24] = "Desert Eagle", [25] = "Shotgun (SG)",
    [26] = "Sawn-off", [27] = "SPAS-12", [28] = "Uzi", [29] = "MP5",
    [30] = "AK-47", [31] = "M4", [32] = "Tec-9", [33] = "Rifle",
    [34] = "Sniper", [35] = "RPG", [38] = "Minigun"
}

local function cleanText(str)
    if not str then return "" end
    return str:gsub("{%x%x%x%x%x%x}", "")
end

local function CustomToggle(label, bool_ref)
    local state = bool_ref[0]
    if state then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.35, 0.15, 0.55, 1.00)) 
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.45, 0.20, 0.70, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.55, 0.25, 0.85, 1.00))
    else
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.15, 0.15, 0.18, 1.00)) 
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.20, 0.25, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.30, 0.30, 0.35, 1.00))
    end
    
    local statusText = state and " [ NYALA ]" or " [ MATI ]"
    if imgui.Button(u8(label .. statusText), imgui.ImVec2(-1, 45)) then
        bool_ref[0] = not bool_ref[0]
    end
    imgui.PopStyleColor(3)
end

function main()
    while not isSampAvailable() do wait(100) end
    while not isPlayerPlaying(PLAYER_HANDLE) do wait(500) end

    sampRegisterChatCommand("yolumber", function() windowState[0] = not windowState[0] end)
    sampRegisterChatCommand("lj", function() windowState[0] = not windowState[0] end)
    
    sampAddChatMessage("{9932CC}[YoLumber V2]{FFFFFF} Script by Yokana aktif! Ketik {9932CC}/yolumber{FFFFFF} buat buka menu, dasar kuli!", -1)

    lua_thread.create(function()
        while true do
            wait(250)
            if isPlayerPlaying(PLAYER_HANDLE) then pcall(doScan, false) end
        end
    end)

    lua_thread.create(function()
        while true do
            wait(900000)
            if isPlayerPlaying(PLAYER_HANDLE) and autoEatDrink[0] then
                sampAddChatMessage("{9932CC}[YoLumber V2]{FFFFFF} Waktunya makan minum! Nyuapin lu 5x Snack & 5x Sprunk biar GK mokad...", -1)
                for i = 1, 5 do sampSendChat("/use snack"); wait(1200) end
                for i = 1, 5 do sampSendChat("/use sprunk"); wait(1200) end
            end
        end
    end)

    lua_thread.create(function()
        while true do
            wait(0)
            if autoUnflip[0] and isCharInAnyCar(PLAYER_PED) then
                local veh = storeCarCharIsInNoSave(PLAYER_PED)
                local model = getCarModel(veh)
                
                if not flyingVehicles[model] then
                    if isCarUpsidedown(veh) then
                        wait(1000) 
                        if isCharInAnyCar(PLAYER_PED) then
                            local currentVeh = storeCarCharIsInNoSave(PLAYER_PED)
                            if currentVeh == veh and isCarUpsidedown(veh) then
                                local speed = getCarSpeed(veh)
                                local heading = getCarHeading(veh)
                                local x, y, z = getCarCoordinates(veh)
                                
                                setCarCoordinates(veh, x, y, z + 0.8)
                                setCarHeading(veh, heading)
                                setCarForwardSpeed(veh, speed)
                            end
                        end
                    end
                end
            end
        end
    end)

    lua_thread.create(vehicleDamageThread)
    wait(-1)
end

function playAlertSound(x, y, z)
    pcall(function() addOneOffSound(x, y, z, 1058) end)
end

function setGPS(x, y, z)
    pcall(function()
        if activeBlip then removeBlip(activeBlip) end
        activeBlip = addBlipForCoord(x, y, z)
        changeBlipColor(activeBlip, 1)
    end)
end

function vehicleDamageThread()
    while true do
        wait(0)
        if isPlayerPlaying(PLAYER_HANDLE) and isCharInAnyCar(PLAYER_PED) then
            local currentVeh = storeCarCharIsInNoSave(PLAYER_PED)
            if currentVeh ~= lastVehHandle then
                lastVehHandle = currentVeh
                lastVehHealth = getCarHealth(currentVeh)
            else
                local currentHealth = getCarHealth(currentVeh)
                if currentHealth < lastVehHealth then
                    if reduceDamageEnabled[0] then
                        local newHealth = lastVehHealth - customDamageVal[0]
                        if newHealth < 0 then newHealth = 0 end
                        if autoRepairBody[0] then fixCar(currentVeh) end
                        setCarHealth(currentVeh, newHealth)
                        lastVehHealth = newHealth
                    else
                        lastVehHealth = currentHealth
                    end
                else
                    lastVehHealth = currentHealth
                end
            end
        else
            lastVehHandle = 0
            lastVehHealth = 1000.0
        end
    end
end

function repairEngine()
    if isCharInAnyCar(PLAYER_PED) then
        local car = storeCarCharIsInNoSave(PLAYER_PED)
        if doesVehicleExist(car) then
            setCarHealth(car, 1000.0)
            lastVehHealth = 1000.0
            sampAddChatMessage("{9932CC}[YoVehicle]{FFFFFF} Mesin udah mulus lagi. Jangan nabrak mulu lu!", -1)
        end
    end
end

function repairBody()
    if isCharInAnyCar(PLAYER_PED) then
        local car = storeCarCharIsInNoSave(PLAYER_PED)
        if doesVehicleExist(car) then
            fixCar(car)
            setCarHealth(car, 1000.0)
            lastVehHealth = 1000.0
            sampAddChatMessage("{9932CC}[YoVehicle]{FFFFFF} Bodi udah diketok magic, kelar urusan.", -1)
        end
    end
end

function doScan(isManual)
    local temp = {}
    local success, px, py, pz = pcall(getCharCoordinates, PLAYER_PED)
    if not success then return end

    local currentReadyNumMap = {}

    for id = 0, 2047 do
        local status, isDefined = pcall(sampIs3dTextDefined, id)
        if status and isDefined then
            local res, text, color, x, y, z = pcall(sampGet3dTextInfoById, id)
            if res and text then
                local clean = cleanText(text)
                local txtLower = clean:lower()

                if txtLower:find("tree") then
                    local dist = getDistanceBetweenCoords3d(px, py, pz, x, y, z)
                    if dist <= scanRadius[0] then
                        local treeNum = txtLower:match("tree%s*%(?(%d+)%)?") or tostring(id)
                        local timeMatch = nil
                        for line in clean:gmatch("[^\r\n]+") do
                            local lLow = line:lower()
                            if lLow:find(":") or lLow:find("menit") or lLow:find("detik") or lLow:find("min") or lLow:find("sec") or lLow:find("cd") or line:match("%d+s") then
                                timeMatch = line
                                break
                            end
                        end
                        if not timeMatch then timeMatch = clean:match("(%d+:%d+)") or clean:match("(%d+%s*[Mm]enit)") or clean:match("(%d+%s*[Dd]etik)") end

                        local isTumbang = (timeMatch ~= nil) or txtLower:find("cooldown") or txtLower:find("cd") or txtLower:find("lumber") or txtLower:find("take") or txtLower:find("tumbang") or txtLower:find("proses") or txtLower:find("%%")

                        if isTumbang then
                            if showDown[0] then
                                table.insert(temp, { type = "TUMBANG", num = treeNum, info = timeMatch or clean:gsub("\n", " "), x = x, y = y, z = z, dist = dist })
                            end
                        else
                            currentReadyNumMap[treeNum] = true
                            if soundAlertEnabled[0] and not notifiedTrees[treeNum] and dist <= soundDistance[0] then
                                playAlertSound(px, py, pz)
                                notifiedTrees[treeNum] = true
                                sampAddChatMessage(string.format("{9932CC}[YoLumber V2]{FFFFFF} Woi! Pohon (%s) SIAP TEBANG! (Jarak: %.1fm). Buruan sikat!", treeNum, dist), -1)
                            end

                            table.insert(temp, { type = "TEBANG", num = treeNum, info = "Siap", x = x, y = y, z = z, dist = dist })
                        end
                    end
                end
            end
        end
    end

    for k, _ in pairs(notifiedTrees) do
        if not currentReadyNumMap[k] then notifiedTrees[k] = nil end
    end
    table.sort(temp, function(a, b) return a.dist < b.dist end)
    readyTrees = temp

    if autoGPS[0] then
        for _, t in ipairs(readyTrees) do
            if t.type == "TEBANG" then setGPS(t.x, t.y, t.z) break end
        end
    end
end

imgui.OnFrame(function() 
    return (espEnabled[0] or espWeaponEnabled[0]) and isPlayerPlaying(PLAYER_HANDLE) 
end, function(player)
    local drawList = imgui.GetBackgroundDrawList()
    local resX, resY = getScreenResolution()
    local startX, startY = resX / 2, resY
    local ok, px, py, pz = pcall(getCharCoordinates, PLAYER_PED)
    
    if not ok then return end

    if espEnabled[0] and #readyTrees > 0 then
        for i, t in ipairs(readyTrees) do
            t.dist = getDistanceBetweenCoords3d(px, py, pz, t.x, t.y, t.z)
            local onScreen = isPointOnScreen(t.x, t.y, t.z, 0.0)
            if onScreen then
                local res, sx, sy = pcall(convert3DCoordsToScreen, t.x, t.y, t.z)
                if res and sx and sy then
                    local colLine, colText, str

                    if t.type == "TEBANG" then
                        colLine = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
                        colText = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
                        str = string.format("[SIAP SIKAT] Tree (%s) [%.1fm]", t.num, t.dist)
                    else
                        colLine = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 0.2, 0.2, 0.9))
                        colText = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 0.3, 0.3, 1.0))
                        str = string.format("[SABAR] Tree (%s) | %s [%.1fm]", t.num, t.info, t.dist)
                    end

                    drawList:AddLine(imgui.ImVec2(startX, startY), imgui.ImVec2(sx, sy), colLine, (t.type == "TEBANG") and 3.0 or 2.0)
                    drawList:AddText(imgui.ImVec2(sx - 55, sy - 15), colText, u8(str))
                end
            end
        end
    end

    if espWeaponEnabled[0] then
        for i = 0, sampGetMaxPlayerId(false) do
            if sampIsPlayerConnected(i) then
                local result, ped = sampGetCharHandleBySampPlayerId(i)
                if result and doesCharExist(ped) and not isCharDead(ped) then
                    local weaponId = getCurrentCharWeapon(ped)
                    
                    if weaponNames[weaponId] then
                        local cx, cy, cz = getCharCoordinates(ped)
                        local dist = getDistanceBetweenCoords3d(px, py, pz, cx, cy, cz)
                        
                        if dist <= weaponEspDistance[0] then
                            if isPointOnScreen(cx, cy, cz, 0.0) then
                                local onScreen, sx, sy = pcall(convert3DCoordsToScreen, cx, cy, cz)
                                if onScreen and sx and sy then
                                    local pName = sampGetPlayerNickname(i)
                                    local wName = weaponNames[weaponId]
                                    
                                    local colWeapLine = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 0.6, 0.0, 0.85))
                                    local colWeapText = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 0.8, 0.0, 1.0))
                                    
                                    local strWeap = string.format("[AWAS DM] %s | %s (ID: %d) [%.1fm]", pName, wName, weaponId, dist)

                                    drawList:AddLine(imgui.ImVec2(startX, startY), imgui.ImVec2(sx, sy), colWeapLine, 2.0)
                                    drawList:AddText(imgui.ImVec2(sx - 70, sy + 15), colWeapText, u8(strWeap))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

imgui.OnFrame(function() 
    return windowState[0] 
end, function(player)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 12.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 8.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 8.0)
    
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.06, 0.06, 0.08, 0.98))       
    imgui.PushStyleColor(imgui.Col.TitleBg, imgui.ImVec4(0.12, 0.12, 0.18, 1.00))        
    imgui.PushStyleColor(imgui.Col.TitleBgActive, imgui.ImVec4(0.20, 0.10, 0.40, 1.00))  
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.95, 0.95, 0.95, 1.00))           
    imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.15, 0.15, 0.18, 1.00))        
    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.09, 0.09, 0.12, 1.00))        
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.40, 0.20, 0.60, 0.50))
    
    imgui.SetNextWindowSize(imgui.ImVec2(550, 720), imgui.Cond.FirstUseEver)
    imgui.Begin(u8"YOLUMBER V2 BY YOKANA", windowState, imgui.WindowFlags.NoCollapse)

    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 1.00, 1.00), u8("=== LUMBERJACK TRACKER TOXIC ==="))
    imgui.TextColored(imgui.ImVec4(0.6, 0.6, 0.6, 1.0), u8("Developed by: Yokana | Edisi Kuli Kasar"))
    imgui.Separator()
    
    imgui.Spacing()
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.145, 0.827, 0.400, 1.0))       
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.070, 0.650, 0.300, 1.0))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.040, 0.500, 0.200, 1.0)) 
    if imgui.Button(u8"[ INFO ] JOIN SALURAN", imgui.ImVec2(-1, 40)) then
        openLink("https://whatsapp.com/channel/0029VbDrYKWLikg0DjWKi82X")
    end
    imgui.PopStyleColor(3) 
    imgui.Spacing()

    local avail = imgui.GetContentRegionAvail().x
    local btnW = (avail - 24) / 4 
    
    local tabs = {"Radar", "Setingan", "Mobil", "Shortcut"}
    for i, name in ipairs(tabs) do
        if currentTab[0] == i then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.35, 0.15, 0.55, 1.00))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.45, 0.20, 0.70, 1.00))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.55, 0.25, 0.85, 1.00))
        else
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.12, 0.15, 1.00))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.20, 0.25, 1.00))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.30, 0.30, 0.35, 1.00))
        end
        
        if imgui.Button(u8(name), imgui.ImVec2(btnW, 40)) then currentTab[0] = i end
        imgui.PopStyleColor(3)
        if i < 4 then imgui.SameLine() end
    end
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    
    if currentTab[0] == 1 then 
        if imgui.Button(u8"REFRESH RADAR SEKARANG (BIAR UPDATE)", imgui.ImVec2(-1, 45)) then
            doScan(true)
        end
        
        imgui.Spacing()
        imgui.TextColored(imgui.ImVec4(0.00, 0.90, 1.00, 1.00), u8("Pohon Yang Ada Di Deket Lu:"))
        imgui.BeginChild(u8("TreeList"), imgui.ImVec2(0, 0), true)
        
        if #readyTrees == 0 then
            imgui.TextColored(imgui.ImVec4(0.5, 0.5, 0.5, 1.0), u8("Kosong bro! Pindah spot lu, dasar ampas."))
        else
            local ok, px, py, pz = pcall(getCharCoordinates, PLAYER_PED)
            for i, t in ipairs(readyTrees) do
                if ok then t.dist = getDistanceBetweenCoords3d(px, py, pz, t.x, t.y, t.z) end
                
                local tag = (t.type == "TEBANG") and "[GAS]" or "[" .. tostring(t.info) .. "]"
                
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.25, 0.25, 0.30, 1.00))
                if imgui.Button(u8("GPS##" .. i), imgui.ImVec2(60, 30)) then
                    setGPS(t.x, t.y, t.z)
                end
                imgui.PopStyleColor(1)

                imgui.SameLine()
                if t.type == "TEBANG" then
                    imgui.TextColored(imgui.ImVec4(1.0, 1.0, 1.0, 1.0), u8(string.format("%s Pohon (%s) - %.1fm", tag, t.num, t.dist)))
                else
                    imgui.TextColored(imgui.ImVec4(1.0, 0.3, 0.3, 1.0), u8(string.format("%s Pohon (%s) - %.1fm", tag, t.num, t.dist)))
                end
            end
        end
        imgui.EndChild()

    elseif currentTab[0] == 2 then 
        imgui.PushItemWidth(-1)
        imgui.SliderFloat(u8("##ScanRadius"), scanRadius, 50.0, 3000.0, u8("Jarak Scan Mata Lu: %.0f Meter"))
        imgui.Spacing()
        imgui.SliderFloat(u8("##WeapDist"), weaponEspDistance, 10.0, 500.0, u8("Jarak Deteksi Player Bawa SG: %.0f Meter"))
        imgui.PopItemWidth()
        
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        CustomToggle("ESP Line (Biar Mata Lu Gak Buta Map)", espEnabled)
        CustomToggle("ESP Senjata (Liat Orang Bawa SG/Pestol)", espWeaponEnabled)
        CustomToggle("Auto GPS (Tinggal Jalan, Dasar Pemalas)", autoGPS)
        CustomToggle("Alarm Suara (Biar Telinga Lu Gak Budek)", soundAlertEnabled)
        CustomToggle("Auto makan minum biar GK mokad", autoEatDrink)
        CustomToggle("Liatin Pohon Cooldown (Warna Merah)", showDown)

    elseif currentTab[0] == 3 then 
        CustomToggle("Anti Penyok (Biar Mobil Gak Cepat Meledak)", reduceDamageEnabled)
        CustomToggle("Auto Mulus (Nabrak Langsung Bener)", autoRepairBody)
        CustomToggle("Auto Unflip (Biar mobil lu gak nyungsep tolol)", autoUnflip)

        imgui.Spacing()
        imgui.PushItemWidth(-1)
        imgui.SliderFloat(u8("##DamageVal"), customDamageVal, 1.0, 2000.0, u8("Batas Ngurang HP Kalau Nabrak: %.1f HP"))
        imgui.PopItemWidth()

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        if imgui.Button(u8("BENERIN MESIN (BURUAN PENCET)"), imgui.ImVec2(-1, 50)) then
            repairEngine()
        end
        imgui.Spacing()
        if imgui.Button(u8("KETOK MAGIC BODI MOBIL (INSTAN)"), imgui.ImVec2(-1, 50)) then
            repairBody()
        end

    elseif currentTab[0] == 4 then 
        if imgui.Button(u8("Tebang Pohon (Biar Cepat Kaya)"), imgui.ImVec2(-1, 50)) then
            sampSendChat("/lum cut")
        end
        imgui.Spacing()
        if imgui.Button(u8("Ambil Kayu Jatuh (Pungut Bang)"), imgui.ImVec2(-1, 50)) then
            sampSendChat("/lum take")
        end
        imgui.Spacing()
        if imgui.Button(u8("Muat ke Mobil (Angkat Yang Bener)"), imgui.ImVec2(-1, 50)) then
            sampSendChat("/lum load")
        end
        imgui.Spacing()
        if imgui.Button(u8("Turunkan Kayu (Bongkar Muatan)"), imgui.ImVec2(-1, 50)) then
            sampSendChat("/lum unload")
        end
        imgui.Spacing()
        if imgui.Button(u8("Potong Log (Jadi Kepingan)"), imgui.ImVec2(-1, 50)) then
            sampSendChat("/lum slice")
        end
    end

    imgui.End()
    imgui.PopStyleColor(7)
    imgui.PopStyleVar(3)
end)
