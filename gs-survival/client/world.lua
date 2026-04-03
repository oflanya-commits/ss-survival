-- [MARKET SİSTEMİ]
RegisterNetEvent('gs-survival:client:openMarket', function()
    local upgrades = {}
    for key, upg in pairs(Config.Upgrades) do
        table.insert(upgrades, {
            type  = key,
            label = upg.label,
            price = upg.price,
            value = upg.value
        })
    end
    SendNUIMessage({ type = 'openMarket', data = { upgrades = upgrades } })
end)

RegisterNetEvent('gs-survival:client:setArmor', function(amount)
    Wait(1500)
    SetPedArmour(PlayerPedId(), tonumber(amount))
end)

-- [RECONNECT VE GÜVENLİ BÖLGE KONTROLÜ]
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(5000)
    QBCore.Functions.TriggerCallback('gs-survival:server:checkReconnectBackup', function(result)
        HandleReconnectResult(result)
    end)
end)

-- [İLİŞKİ AYARLARI]
Citizen.CreateThread(function()
    AddRelationshipGroup('HATES_PLAYER')
    SetRelationshipBetweenGroups(5, `HATES_PLAYER`, `PLAYER`)
    SetRelationshipBetweenGroups(5, `PLAYER`, `HATES_PLAYER`)
end)

-- [BAŞLANGIÇ NPC VE TARGET]
local startPed
Citizen.CreateThread(function()
    local model = Config.Npc.Model
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end

    startPed = CreatePed(4, model, Config.Npc.Coords.x, Config.Npc.Coords.y, Config.Npc.Coords.z - 1.0, Config.Npc.Coords.w, false, true)
    FreezeEntityPosition(startPed, true)
    SetEntityInvincible(startPed, true)
    SetBlockingOfNonTemporaryEvents(startPed, true)
    SetEntityAsMissionEntity(startPed, true, true)

    exports.ox_target:addLocalEntity(startPed, {
        {
            name = 'survival_main',
            icon = 'fas fa-users',
            label = Config.Npc.Label,
            canInteract = function(entity) return IsEntityVisible(entity) end,
            onSelect = function() TriggerEvent('gs-survival:client:openMenu') end
        },
        
    })
end)

-- [TEMİZLİK FONKSİYONU]
RegisterNetEvent('gs-survival:client:cleanupBeforeLeave', function()
    if LocalPlayer.state.invOpen then
        CloseInventorySafely()
    end
    Entity(PlayerPedId()).state:set('isLooting', false, true)
    isSurvivalActive = false
    isEnding = true
    notifiedDeath = false
    waitingForWave = false
    countdown = 0
    modeBoundaryGraceUntil = 0
    activeBoundaryRadius = nil
    activeArcDeployment = nil
    arcRaidEndAt = 0
    ClearArcExtractionState()
    invitedPlayers = {}
    ownsLobby = false
    lobbyLeaderId = nil
    pendingInviteLeaderId = nil
    memberReadyState = false
    currentLobbyPublic = nil
    currentModeId = 'classic'
    activeSurvivalPlayers = {}
    activeArcRaidPlayers = {}
    activeArcAlivePlayers = {}
    activeArcSquadPlayers = {}
    LocalPlayer.state:set('inLobby', false, true)
    exports['qb-core']:HideText()
    ClearArcOverlay()
    ApplyMinimapLayout(DEFAULT_MINIMAP_LAYOUT)
    StopSpectating()
    ClearArcZoneBlips()
    ClearArcDeploymentZoneBlips()
    RestoreHiddenBlips()
    ClearArcFriendlyBlips()
    ClearArcSessionVehicles()
    ClearArcContainers()
    ClearArcBarricades()
end)

-- [ÖLÜM VE SPECTATE SİSTEMİ]
Citizen.CreateThread(function()
    while true do
        Wait(1000)
        if isSurvivalActive then
            local ped = PlayerPedId()
            if IsEntityDead(ped) or IsPedFatallyInjured(ped) then
                if not notifiedDeath then
                    notifiedDeath = true
                    if currentModeId == 'arc_pvp' then
                        isSurvivalActive = false
                        TriggerServerEvent('gs-survival:server:handleArcDeath', 'death')
                    else
                        isSurvivalActive = false
                        TriggerServerEvent('gs-survival:server:finishSurvival', false)
                    end
                    
                    local livingOthers = false
                    local myId = GetPlayerServerId(PlayerId())
                    local trackedPlayers = currentModeId == 'arc_pvp' and activeArcSquadPlayers or activeSurvivalPlayers
                    for _, id in ipairs(trackedPlayers or {}) do
                        if tonumber(id) ~= tonumber(myId) then
                            local pIdx = GetPlayerFromServerId(id)
                            if pIdx ~= -1 and NetworkIsPlayerActive(pIdx) then
                                if not IsPedFatallyInjured(GetPlayerPed(pIdx)) then
                                    livingOthers = true
                                    break
                                end
                            end
                        end
                    end

                    if livingOthers and currentModeId == 'arc_pvp' then
                        NotifyForMode("Elendin! Baskın kameralarına bağlanıyorsun...", "primary", 5000, "ARC Ölüm")
                        Wait(1000)
                        StartSurvivalSpectate()
                    elseif currentModeId == 'arc_pvp' then
                        NotifyForMode("Takımından izlenecek kimse kalmadı. Lobiye dönüyorsun...", "primary", 5000, "ARC Ölüm")
                        Wait(1000)
                        TriggerServerEvent('gs-survival:server:returnArcToLobby')
                    elseif livingOthers then
                        NotifyForMode("Öldün! Takım arkadaşlarını izliyorsun...", "error", 5000, "Ölüm")
                        Wait(1000)
                        StartSurvivalSpectate()
                    end
                end
            end
        end
    end
end)

local ARC_AMBIENT_CLEANUP_INTERVAL_MS = 5000
local ARC_AMBIENT_CLEANUP_RADIUS_METERS = 120.0
local ARC_MOVING_VEHICLE_SPEED_THRESHOLD_MPS = 1.0

local function IsPopulationSuppressedMode()
    return isSurvivalActive and (currentModeId == 'classic' or currentModeId == 'arc_pvp')
end

local function IsArcModeRunning()
    return isSurvivalActive and currentModeId == 'arc_pvp'
end

local function IsClassicWaveRunning()
    return isSurvivalActive and currentModeId == 'classic' and currentWave > 0 and not waitingForWave
end

Citizen.CreateThread(function()
    while true do
        if IsPopulationSuppressedMode() then
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetPedDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
            SetParkedVehicleDensityMultiplierThisFrame(currentModeId == 'arc_pvp' and 1.0 or 0.0)
            SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
            Citizen.Wait(0)
        else
            Citizen.Wait(1250)
        end
    end
end)

local function BuildArcSessionVehicleNetIdSet()
    local activeNetIds = {}
    for _, vehicleState in pairs(arcSessionVehicles or {}) do
        local netId = tonumber(vehicleState and vehicleState.netId)
        if netId and netId ~= 0 then
            activeNetIds[netId] = true
        end
    end
    return activeNetIds
end

local function IsWithinArcCleanupRadius(sourceCoords, targetCoords, radiusSq)
    local dx = sourceCoords.x - targetCoords.x
    local dy = sourceCoords.y - targetCoords.y
    local dz = sourceCoords.z - targetCoords.z
    return ((dx * dx) + (dy * dy) + (dz * dz)) <= radiusSq
end

local function ClearArcAmbientPopulation(radius)
    local playerPed = PlayerPedId()
    if not DoesEntityExist(playerPed) then
        return
    end

    local centerCoords = GetEntityCoords(playerPed)
    local radiusSq = radius * radius
    local playerVehicle = GetVehiclePedIsIn(playerPed, false)
    local arcSessionVehicleNetIds = IsArcModeRunning() and BuildArcSessionVehicleNetIdSet() or {}

    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= playerPed and DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsEntityAMissionEntity(ped) then
            local pedCoords = GetEntityCoords(ped)
            if IsWithinArcCleanupRadius(centerCoords, pedCoords, radiusSq) then
                SetEntityAsMissionEntity(ped, true, true)
                DeleteEntity(ped)
            end
        end
    end

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and vehicle ~= playerVehicle and not IsEntityAMissionEntity(vehicle) then
            local vehicleCoords = GetEntityCoords(vehicle)
            local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
            local isArcSessionVehicle = vehicleNetId and vehicleNetId ~= 0 and arcSessionVehicleNetIds[vehicleNetId]
            if not isArcSessionVehicle and IsWithinArcCleanupRadius(centerCoords, vehicleCoords, radiusSq) then
                local driver = GetPedInVehicleSeat(vehicle, -1)
                local hasAmbientDriver = driver ~= 0 and DoesEntityExist(driver) and not IsPedAPlayer(driver)
                local isMovingVehicle = GetEntitySpeed(vehicle) > ARC_MOVING_VEHICLE_SPEED_THRESHOLD_MPS
                local shouldRemoveVehicle = hasAmbientDriver or isMovingVehicle

                if shouldRemoveVehicle then
                    if hasAmbientDriver and not IsEntityAMissionEntity(driver) then
                        SetEntityAsMissionEntity(driver, true, true)
                        DeleteEntity(driver)
                    end

                    SetEntityAsMissionEntity(vehicle, true, true)
                    DeleteEntity(vehicle)
                end
            end
        end
    end
end

Citizen.CreateThread(function()
    while true do
        if IsArcModeRunning() then
            ClearArcAmbientPopulation(ARC_AMBIENT_CLEANUP_RADIUS_METERS)
            Citizen.Wait(ARC_AMBIENT_CLEANUP_INTERVAL_MS)
        elseif IsClassicWaveRunning() then
            local ped = PlayerPedId()
            if DoesEntityExist(ped) then
                local coords = GetEntityCoords(ped)
                ClearAreaOfVehicles(coords.x, coords.y, coords.z, 80.0, false, false, false, false, false)
            end
            Citizen.Wait(15000)
        else
            Citizen.Wait(15000)
        end
    end
end)

-- [MESAFE VE TRAFİK KONTROLÜ]
local teleportLeeway = 0
Citizen.CreateThread(function()
    local lastWarningTime = 0

    while true do
        local sleep = 1000

        if isSurvivalActive and not notifiedDeath then
            sleep = currentModeId == 'arc_pvp' and 1000 or 500
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local stageData = GetActiveArcStageData()
            local stageCenter = stageData and ToVector3(stageData.center)
            if stageCenter and currentModeId ~= 'arc_pvp' then
                local boundaryDistance = activeBoundaryRadius or GetModeBoundaryRadius(currentModeId, stageData)
                local boundaryErrorText, boundaryWarnText = GetModeBoundaryTexts(currentModeId)
                local warningBufferPct = tonumber(Config.Combat and Config.Combat.BoundaryWarningBufferPct or 0.2) or 0.2
                local minWarningBuffer = tonumber(Config.Combat and Config.Combat.MinBoundaryWarningBuffer or 20.0) or 20.0
                local warningCooldownMs = tonumber(Config.Combat and Config.Combat.BoundaryWarningCooldownMs or 15000) or 15000
                local dist = #(coords - stageCenter)
                local isInGracePeriod = GetGameTimer() < modeBoundaryGraceUntil
                if teleportLeeway < 10 then
                    teleportLeeway = teleportLeeway + 1
                    dist = 0
                elseif isInGracePeriod then
                    dist = 0
                end
                if dist > boundaryDistance then
                    isSurvivalActive = false
                    teleportLeeway = 0
                    exports['qb-core']:HideText()
                    NotifyForMode(boundaryErrorText, "error", 4000, "ARC Sınır")
                    if currentModeId == 'arc_pvp' then
                        TriggerServerEvent('gs-survival:server:handleArcDeath', 'boundary')
                    else
                        SetEntityCoords(ped, Config.Npc.Coords.x, Config.Npc.Coords.y, Config.Npc.Coords.z)
                        TriggerServerEvent('gs-survival:server:finishSurvival', false)
                        TriggerEvent('gs-survival:client:stopEverything', false)
                    end
                elseif dist > (boundaryDistance - math.max(minWarningBuffer, boundaryDistance * warningBufferPct)) then
                    if GetGameTimer() - lastWarningTime > warningCooldownMs then
                        NotifyForMode(boundaryWarnText, "error", 3000, "ARC Sınır")
                        lastWarningTime = GetGameTimer()
                    end
                end
            end

            -- UI VE DALGA YÖNETİMİ
            if currentModeId == 'arc_pvp' then
                RefreshArcOverlayInfo()
            elseif not isEnding then
                local aliveCount = 0
                for _, v in pairs(spawnedPeds) do
                    if DoesEntityExist(v) and not IsPedDeadOrDying(v) then aliveCount = aliveCount + 1 end
                end

                -- [DÜZELTME]: Max Waves hesaplaması yeni stage yapısına göre güncellendi
                local maxWaves = 0
                local sId = activeStageId or 1
                local survivalStage = GetModeStageData('classic', sId)
                if survivalStage and survivalStage.Waves then
                    for k, v in pairs(survivalStage.Waves) do
                        maxWaves = maxWaves + 1
                    end
                end

                PushClassicSurvivalOverlay(survivalStage, aliveCount, maxWaves)

                -- DALGA ATLATMA MANTIĞI
                if not waitingForWave and #spawnedPeds > 0 and aliveCount == 0 then
                    -- [DÜZELTME]: Bir sonraki dalga kontrolü mevcut stage altındaki Waves tablosundan yapılıyor
                    if survivalStage and survivalStage.Waves[currentWave + 1] then
                        currentWave = currentWave + 1
                        waitingForWave = true
                        NotifyForMode('Yeni dalga için hazırlan!', 'success', 4500, 'Sektör Temizlendi')
                        StartWaveCountdown()
                    else
                        isEnding = true
                        NotifyForMode('Tüm dalgalar temizlendi! Ganimetleri topla.', 'info', 5000, 'Operasyon Başarılı')

                        Citizen.CreateThread(function()
                            local lootTimer = math.floor(Config.Combat.LootTime / 1000)
                            local forceOverlayRefresh = true
                            while lootTimer > 0 and isSurvivalActive do
                                PushClassicSurvivalOverlay(survivalStage, 0, maxWaves, lootTimer, forceOverlayRefresh)
                                forceOverlayRefresh = false
                                Wait(1000)
                                lootTimer = lootTimer - 1
                            end
                            if isSurvivalActive then
                                isSurvivalActive = false
                                isEnding = false
                                exports['qb-core']:HideText()
                                SetEntityCoords(PlayerPedId(), Config.Npc.Coords.x, Config.Npc.Coords.y, Config.Npc.Coords.z)
                                TriggerServerEvent('gs-survival:server:finishSurvival', true)
                                TriggerEvent('gs-survival:client:stopEverything', true)
                            end
                        end)
                    end
                end
            end
        else
            sleep = 2000
            teleportLeeway = 0
            if currentModeId == 'arc_pvp' then
                ClearArcOverlay()
            elseif not isSurvivalActive then
                ClearArcOverlay()
                exports['qb-core']:HideText()
            end
        end
        Wait(sleep)
    end
end)

Citizen.CreateThread(function()
    while true do
        local sleep = 1000

        if currentModeId == 'arc_pvp' and isSurvivalActive and arcExtractionState and arcExtractionState.enabled == true then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local zoneRadius = tonumber(arcExtractionState.zoneRadius or 12.0) or 12.0
            local nearbyZone = nil
            local nearbyDistance = nil
            local shouldDrawMarkers = false

            for _, zone in ipairs(GetArcExtractionDisplayZones()) do
                local zoneCoords = ToVector3(zone and zone.coords)
                if zoneCoords then
                    local distance = #(coords - zoneCoords)
                    if distance < 150.0 then
                        shouldDrawMarkers = true
                        local markerColor = arcExtractionState.phase == 'ready' and { r = 122, g = 255, b = 122 } or { r = 242, g = 169, b = 0 }
                        DrawMarker(1, zoneCoords.x, zoneCoords.y, zoneCoords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, zoneRadius * 2.0, zoneRadius * 2.0, 1.8, markerColor.r, markerColor.g, markerColor.b, 105, false, false, 2, false, nil, nil, false)
                        DrawMarker(6, zoneCoords.x, zoneCoords.y, zoneCoords.z + 0.35, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, zoneRadius * 1.2, zoneRadius * 1.2, 2.2, 255, 255, 255, 70, false, false, 2, false, nil, nil, false)
                    end

                    if distance <= (zoneRadius + 4.0) and (not nearbyDistance or distance < nearbyDistance) then
                        nearbyZone = zone
                        nearbyDistance = distance
                    end
                end
            end

            if shouldDrawMarkers then
                sleep = 0
            elseif nearbyZone then
                sleep = 100
            else
                sleep = 350
            end

            if nearbyZone then
                if arcExtractionState.phase == 'available' then
                    RefreshArcOverlayInfo("[E] Airlift çağır • Tahliye penceresini başlat")
                    if IsControlJustPressed(0, 38) then
                        TriggerServerEvent('gs-survival:server:startArcExtractionCall', nearbyZone.id)
                    end
                elseif arcExtractionState.phase == 'ready' then
                    local manualDepartureCountdown = tonumber(arcExtractionState.manualDepartureCountdown) or 0
                    if arcExtractionState.departurePending == true then
                        RefreshArcOverlayInfo(("Kalkış sayacı başladı • %s sn sonra içeridekiler çıkacak"):format(GetArcExtractionCountdownSeconds()))
                    elseif arcExtractionState.manualDepartureEnabled ~= false then
                        local autoDepartureCountdown = GetArcExtractionCountdownSeconds()
                        RefreshArcOverlayInfo(("[E] Kalkış sayacını başlat • %s sn sonra çıkış, basılmazsa %s sn sonra otomatik tahliye"):format(manualDepartureCountdown, autoDepartureCountdown))
                        if IsControlJustPressed(0, 38) then
                            TriggerServerEvent('gs-survival:server:departArcExtraction')
                        end
                    else
                        RefreshArcOverlayInfo(("Helikopter hazır • %s sn sonra bölgedekiler otomatik çıkacak"):format(GetArcExtractionCountdownSeconds()))
                    end
                elseif arcExtractionState.phase == 'inbound' or arcExtractionState.phase == 'called' then
                    RefreshArcOverlayInfo(("Airlift inbound • %s sn"):format(GetArcExtractionCountdownSeconds()))
                end
            elseif currentModeId == 'arc_pvp' then
                RefreshArcOverlayInfo(ARC_OVERLAY.EMPTY_PROMPT)
            end

            EnsureArcExtractionScene()
        else
            if currentModeId == 'arc_pvp' then
                RefreshArcOverlayInfo(ARC_OVERLAY.EMPTY_PROMPT)
            end
            if currentModeId ~= 'arc_pvp' then
                ClearArcExtractionScene()
            end
        end

        Wait(sleep)
    end
end)

-- Menüyü Açan Event
