-- [DALGA BAŞLATMA VE NPC KURULUM]
function StartWaveCountdown()
    waitingForWave = true
    countdown = Config.Combat.WaveWaitTime or 15

    Citizen.CreateThread(function()
        while countdown > 0 and (isSurvivalActive or notifiedDeath) do
            Wait(1000)
            countdown = countdown - 1
        end

        if isSurvivalActive and not notifiedDeath then
            waitingForWave = false
            
            -- [YENİ]: Yeni dalga başlamadan hemen önce yerdeki tüm eski cesetleri temizle
            TriggerEvent('gs-survival:client:clearWorldSpecial')
            
            -- Ardından yeni dalgayı spawn et
            TriggerServerEvent('gs-survival:server:spawnWave', myBucket, currentWave, activeStageId)
        end
    end)
end


RegisterNetEvent('gs-survival:client:initSurvival', function(bucket, wave, partyMembers, stageId)
    currentModeId = 'classic'
    ClearArcBarricades()
    ClearArcOverlay()
    ApplyMinimapLayout(DEFAULT_MINIMAP_LAYOUT)
    activeStageId = stageId or 1
    local stageData = GetModeStageData('classic', activeStageId)

    isSurvivalActive = true
    currentWave = wave or 1
    myBucket = bucket
    spawnedPeds = {}
    notifiedDeath = false
    isEnding = false
    activeSurvivalPlayers = partyMembers or {}
    activeArcRaidPlayers = {}
    activeArcSquadPlayers = {}
    invitedPlayers = {}
    lobbyLeaderId = nil
    pendingInviteLeaderId = nil
    memberReadyState = false
    LocalPlayer.state:set('inLobby', false, true)
    modeBoundaryGraceUntil = GetGameTimer() + GetModeSpawnGraceMs('classic')
    activeBoundaryRadius = GetModeBoundaryRadius('classic', stageData)

    ShowScreenTransition(SCREEN_TRANSITION_ENTER_TITLE)
    CloseNUI()
    Wait(100)
    DoScreenFadeOut(SCREEN_TRANSITION_FADE_DURATION_MS)
    Wait(SCREEN_TRANSITION_FADE_DURATION_MS + 100)

    if DoesEntityExist(startPed) then
        SetEntityVisible(startPed, false, false)
        SetEntityCoords(startPed, Config.Npc.Coords.x, Config.Npc.Coords.y, Config.Npc.Coords.z - 100.0)
    end

    if stageData and stageData.center then
        SetEntityCoords(PlayerPedId(), stageData.center.x, stageData.center.y, stageData.center.z)
    else
        SetEntityCoords(PlayerPedId(), Config.Npc.Coords.x, Config.Npc.Coords.y, Config.Npc.Coords.z)
        print("^1HATA: Survival stage merkezi bulunamadı!^7")
    end

    Wait(SCREEN_TRANSITION_BLACK_HOLD_MS)
    DoScreenFadeIn(SCREEN_TRANSITION_FADE_DURATION_MS)
    StartWaveCountdown()
end)

RegisterNetEvent('gs-survival:client:initArcPvP', function(bucket, squadMembers, raidPlayers, stageId, deploymentData, rejoinData)
    currentModeId = 'arc_pvp'
    ClearArcBarricades()
    arcOverlaySessionVisible = false
    ApplyMinimapLayout(DEFAULT_MINIMAP_LAYOUT)
    activeStageId = stageId or 1
    local stageData = GetModeStageData('arc_pvp', activeStageId)
    activeArcDeployment = deploymentData or {}
    local deploymentCenter = ToVector3(activeArcDeployment.center) or (stageData and stageData.center) or vector3(Config.Npc.Coords.x, Config.Npc.Coords.y, Config.Npc.Coords.z)
    local insertionPoint = ToVector3(activeArcDeployment.insertion) or deploymentCenter
    local reconnectPoint = rejoinData and ToVector3(rejoinData.coords)
    local spawnPoint = reconnectPoint or insertionPoint
    local deploymentLabel = activeArcDeployment.zoneLabel or (stageData and stageData.label) or "ARC Baskın Bölgesi"
    local arrivalNotifyMessage = reconnectPoint and "Son konumunda yeniden doğdun. Takım bağlantısı sabitleniyor..." or "İniş tamamlandı. Takım bağlantısı sabitleniyor..."

    isSurvivalActive = true
    currentWave = 0
    myBucket = bucket
    spawnedPeds = {}
    notifiedDeath = false
    isEnding = false
    waitingForWave = false
    countdown = 0
    activeSurvivalPlayers = squadMembers or {}
    activeArcSquadPlayers = squadMembers or {}
    activeArcRaidPlayers = raidPlayers or squadMembers or {}
    invitedPlayers = {}
    lobbyLeaderId = nil
    pendingInviteLeaderId = nil
    memberReadyState = false
    LocalPlayer.state:set('inLobby', false, true)
    modeBoundaryGraceUntil = GetGameTimer() + GetModeSpawnGraceMs('arc_pvp')
    local boundaryStageData = activeArcDeployment and activeArcDeployment.center and activeArcDeployment or stageData
    activeBoundaryRadius = GetModeBoundaryRadius('arc_pvp', boundaryStageData)
    arcRaidEndAt = GetGameTimer() + (tonumber(activeArcDeployment.raidDurationMs or ((Config.ArcPvP and Config.ArcPvP.RaidDurationSeconds or 1800) * 1000)) or 1800000)
    ClearArcExtractionState()
    if activeArcDeployment and activeArcDeployment.extraction then
        ApplyArcExtractionState(activeArcDeployment.extraction)
    end
    ApplyArcSessionVehicles(activeArcDeployment and activeArcDeployment.sessionVehicles or {})

    RefreshArcOverlayTeam()
    RefreshArcOverlayInfo(ARC_OVERLAY_EMPTY_PROMPT, true)
    ShowScreenTransition(SCREEN_TRANSITION_ENTER_TITLE)
    CloseNUI()
    Wait(100)
    DoScreenFadeOut(SCREEN_TRANSITION_FADE_DURATION_MS)
    Wait(SCREEN_TRANSITION_FADE_DURATION_MS + 100)

    if DoesEntityExist(startPed) then
        SetEntityVisible(startPed, false, false)
        SetEntityCoords(startPed, Config.Npc.Coords.x, Config.Npc.Coords.y, Config.Npc.Coords.z - 100.0)
    end

    SetEntityCoords(PlayerPedId(), spawnPoint.x, spawnPoint.y, spawnPoint.z)

    ClearArcZoneBlips()
    ClearArcDeploymentZoneBlips()
    HideNonArcBlips()
    CreateArcDeploymentZoneBlips()
    CreateArcZoneBlips(activeArcDeployment)
    SpawnArcLootWorld(bucket, activeArcDeployment)
    RefreshArcSessionVehicleBlips()
    RefreshArcFriendlyBlips()
    RefreshArcOverlayTeam()
    RefreshArcOverlayInfo(ARC_OVERLAY_EMPTY_PROMPT, true)
    TriggerServerEvent('gs-survival:server:requestArcBarricadeSync')
    Wait(tonumber(Config.ArcPvP and Config.ArcPvP.DeploymentNotifyDelay or 1200) or 1200)
    Wait(math.max(0, SCREEN_TRANSITION_BLACK_HOLD_MS - (tonumber(Config.ArcPvP and Config.ArcPvP.DeploymentNotifyDelay or 1200) or 1200)))
    DoScreenFadeIn(SCREEN_TRANSITION_FADE_DURATION_MS)
    arcOverlaySessionVisible = true
    RefreshArcOverlayTeam()
    RefreshArcOverlayInfo(ARC_OVERLAY_EMPTY_PROMPT, true)
    NotifyForMode(arrivalNotifyMessage, "success", 3500, "ARC Dağıtım")
    NotifyForMode(string.format("Baskın bölgesi: %s", deploymentLabel), "primary", 5000, "ARC Bölge")
    NotifyForMode("TAB ile envanterini aç, kasaları topla ve tahliye açıldığında extraction hattına yönel.", "success", 6000, "ARC Görev")
end)

RegisterNetEvent('gs-survival:client:updateArcRaidPlayers', function(squadPlayerIds, raidPlayerIds)
    if currentModeId ~= 'arc_pvp' then return end

    activeSurvivalPlayers = squadPlayerIds or {}
    activeArcSquadPlayers = squadPlayerIds or {}
    activeArcRaidPlayers = raidPlayerIds or squadPlayerIds or {}
    RefreshArcFriendlyBlips()
    RefreshArcOverlayTeam()
    RefreshArcOverlayInfo(nil, true)
end)

RegisterNetEvent('gs-survival:client:updateArcExtractionState', function(state, notifyPayload)
    ApplyArcExtractionState(state, notifyPayload)
    if currentScreen == 'menu' then
        DispatchMenuState(false)
    end
end)

RegisterNetEvent('gs-survival:client:updateArcSessionVehicles', function(vehicleStates)
    if currentModeId ~= 'arc_pvp' or isSurvivalActive ~= true then
        return
    end

    ApplyArcSessionVehicles(vehicleStates or {})
    RefreshArcSessionVehicleBlips()
end)

RegisterNetEvent('gs-survival:client:arcExtracted', function()
    DoScreenFadeOut(350)
    Wait(450)
    DoScreenFadeIn(800)
end)

RegisterNetEvent('gs-survival:client:setupNpc', function(npcNetId, multiplier)
    local timeout = 0
    while not NetworkDoesNetworkIdExist(npcNetId) and timeout < 100 do Wait(10) timeout = timeout + 1 end

    local npc = NetToPed(npcNetId)
    local stageMult = multiplier or 1.0

    if DoesEntityExist(npc) then
        table.insert(spawnedPeds, npc)
        SetEntityAsMissionEntity(npc, true, true)
        SetPedRelationshipGroupHash(npc, `HATES_PLAYER`)

        local newAccuracy = math.floor(Config.Combat.NpcAccuracy * stageMult)
        SetPedAccuracy(npc, newAccuracy)

        local newHealth = math.floor(200 * stageMult)
        SetEntityMaxHealth(npc, newHealth)
        SetEntityHealth(npc, newHealth)

        SetPedCombatAttributes(npc, 46, true)
        SetPedCombatAttributes(npc, 5, true)
        SetPedConfigFlag(npc, 184, true)

        local blip = AddBlipForEntity(npc)
        SetBlipSprite(blip, 1)
        SetBlipColour(blip, 1)
        SetBlipScale(blip, 0.7)
        TaskCombatPed(npc, PlayerPedId(), 0, 16)

        local stashTargetName = 'loot_' .. npcNetId
        exports.ox_target:addLocalEntity(npc, {
            {
                name = stashTargetName,
                icon = 'fas fa-hand-holding',
                label = 'Üstünü Ara',
                distance = 2.0,
                canInteract = function(entity) return IsPedDeadOrDying(entity) end,
                onSelect = function(data)
                    QBCore.Functions.TriggerCallback('gs-survival:server:checkLootStatus', function(canLoot)
                        if canLoot then
                            RunUiProgress({
                                title = "Arama",
                                label = "Üstü Aranıyor...",
                                duration = 3000,
                                canCancel = true,
                                disable = {
                                    disableMovement = true,
                                    disableCarMovement = true,
                                    disableMouse = false,
                                    disableCombat = true,
                                },
                                anim = {
                                    dict = "amb@medic@standing@tendtodead@idle_a",
                                    anim = "idle_a",
                                    flags = 1,
                                }
                            }, function()
                                exports.ox_target:removeLocalEntity(data.entity, stashTargetName)
                                TriggerServerEvent('gs-survival:server:createNpcStash', npcNetId, currentWave)
                            end, function()
                                TriggerServerEvent('gs-survival:server:cancelLoot', npcNetId)
                                NotifyForMode("İşlem iptal edildi!", "error", 3500, "Arama")
                            end)
                        end
                    end, npcNetId)
                end
            }
        })
    end
end)

-- [ENVANTER KONTROLÜ]
Citizen.CreateThread(function()
    while true do
        local sleep = 1000
        if isSurvivalActive then
            sleep = 5
            if ShouldBlockInventoryAccess() then
                CloseInventorySafely()
                NotifyForMode("Savaş sırasında envanterini kullanamazsın!", "error", 3500, "Envanter")
            end
        end
        Wait(sleep)
    end
end)

-- [OYUN SONLANDIRMA]
RegisterNetEvent('gs-survival:client:stopEverything', function(isVictory, modeId)
    local endedModeId = modeId or currentModeId
    isSpectating = false
    StopSpectating()
    Wait(200)
    TriggerEvent('gs-survival:client:cleanupBeforeLeave')
    TriggerEvent('gs-survival:client:clearWorldSpecial')

    ShowScreenTransition(SCREEN_TRANSITION_RETURN_TITLE)
    Wait(100)
    DoScreenFadeOut(SCREEN_TRANSITION_FADE_DURATION_MS)
    Wait(SCREEN_TRANSITION_FADE_DURATION_MS + 100)

    if DoesEntityExist(startPed) then
        SetEntityVisible(startPed, true, false)
        SetEntityCoords(startPed, Config.Npc.Coords.x, Config.Npc.Coords.y, Config.Npc.Coords.z - 1.0)
    end

    exports['qb-core']:HideText()
    local ped = PlayerPedId()
    SetEntityCoords(ped, Config.Npc.Coords.x, Config.Npc.Coords.y, Config.Npc.Coords.z)
    SetEntityVisible(ped, true)
    FreezeEntityPosition(ped, false)

    Wait(SCREEN_TRANSITION_BLACK_HOLD_MS)
    DoScreenFadeIn(SCREEN_TRANSITION_FADE_DURATION_MS)
    if endedModeId == 'arc_pvp' then
        SendArcNotify(isVictory and "ARC baskını başarıyla tamamlandı!" or "ARC baskını sona erdi!", isVictory and "success" or "error", 5000, "ARC Sonuç")
        CreateThread(function()
            Wait(SCREEN_TRANSITION_TOTAL_DURATION_MS + 600)
            if endedModeId == 'arc_pvp' and not isSurvivalActive then
                ClearArcOverlay()
            end
        end)
    else
        NotifyForMode(isVictory and "Operasyon Başarıyla Tamamlandı!" or "Operasyon Başarısız Oldu!", isVictory and "success" or "error", 5000, "Operasyon Sonucu")
    end
end)

-- [DÜNYA TEMİZLİĞİ]
RegisterNetEvent('gs-survival:client:clearWorldSpecial', function()
    ClearArcContainers()
    -- Sadece bu client'ın spawn ettiği/tablosuna giren pedleri temizler
    if spawnedPeds and #spawnedPeds > 0 then
        for i = #spawnedPeds, 1, -1 do
            local ped = spawnedPeds[i]
            if DoesEntityExist(ped) then
                -- Blip temizliği
                local blip = GetBlipFromEntity(ped)
                if DoesBlipExist(blip) then
                    RemoveBlip(blip)
                end
                
                -- NPC'yi dünyadan sil
                SetEntityAsMissionEntity(ped, true, true)
                DeleteEntity(ped)
            end
            table.remove(spawnedPeds, i)
        end
    end
    -- Tabloyu tamamen sıfırla
    spawnedPeds = {}
end)
-- [SPECTATE SİSTEMİ]
function StartSurvivalSpectate()
    if isSpectating then return end
    local function getLiving()
        local living = {}
        local myServerId = GetPlayerServerId(PlayerId())
        local trackedPlayers = currentModeId == 'arc_pvp' and activeArcSquadPlayers or activeSurvivalPlayers
        for _, id in ipairs(trackedPlayers or {}) do
            if tonumber(id) ~= tonumber(myServerId) then
                local pIdx = GetPlayerFromServerId(id)
                if pIdx ~= -1 and NetworkIsPlayerActive(pIdx) then
                    local targetPed = GetPlayerPed(pIdx)
                    if DoesEntityExist(targetPed) and not IsPedFatallyInjured(targetPed) then
                        table.insert(living, pIdx)
                    end
                end
            end
        end
        return living
    end

    local initialMembers = getLiving()
    if #initialMembers == 0 then return end

    isSpectating = true
    spectateIndex = 1
    Citizen.CreateThread(function()
        local lastInstructionText = nil
        while isSpectating do
            local livingMembers = getLiving()
            if #livingMembers > 0 then
                local instructionText = "← Önceki | Sonraki →"
                if currentModeId == 'arc_pvp' then
                    instructionText = instructionText .. " | BACKSPACE Lobiye Dön"
                end
                if instructionText ~= lastInstructionText then
                    exports['qb-core']:DrawText(instructionText, 'right')
                    lastInstructionText = instructionText
                end

                if spectateIndex > #livingMembers then spectateIndex = 1 end
                local targetPed = GetPlayerPed(livingMembers[spectateIndex])

                if not spectateCam then 
                    spectateCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
                    RenderScriptCams(true, false, 0, true, true)
                end

                if DoesEntityExist(targetPed) then
                    local targetCoords = GetEntityCoords(targetPed)
                    local offset = GetOffsetFromEntityInWorldCoords(targetPed, 0.0, -3.5, 1.5)
                    SetCamCoord(spectateCam, offset.x, offset.y, offset.z)
                    PointCamAtEntity(spectateCam, targetPed, 0, 0, 0, true)
                end

                if IsControlJustPressed(0, 34) then
                    spectateIndex = spectateIndex - 1
                    if spectateIndex < 1 then spectateIndex = #livingMembers end
                elseif IsControlJustPressed(0, 35) then
                    spectateIndex = spectateIndex + 1
                    if spectateIndex > #livingMembers then spectateIndex = 1 end
                elseif currentModeId == 'arc_pvp' and IsControlJustPressed(0, 177) then
                    StopSpectating()
                    NotifyForMode("İzlemeyi bıraktın, lobiye dönüyorsun...", "primary", 3500, "ARC Ölüm")
                    TriggerServerEvent('gs-survival:server:returnArcToLobby')
                    break
                end
            else
                isSpectating = false
                StopSpectating()
                break
            end
            Wait(5)
        end
    end)
end

function StopSpectating()
    isSpectating = false
    spectateIndex = 1
    exports['qb-core']:HideText()
    RenderScriptCams(false, false, 0, true, true)
    if spectateCam then
        DestroyCam(spectateCam, true)
        spectateCam = nil
    end
    DestroyAllCams(true)
    local ped = PlayerPedId()
    SetEntityVisible(ped, true)
    FreezeEntityPosition(ped, false)
    SetFocusEntity(ped)
end

-- [LOOT SİSTEMİ]
RegisterNetEvent('gs-survival:client:openNpcStash', function(sId)
    Entity(PlayerPedId()).state:set('isLooting', true, true)
    local stashTarget = sId
    exports.ox_inventory:openInventory('stash', stashTarget)
    CreateThread(function()
        while LocalPlayer.state.invOpen do Wait(100) end
        Entity(PlayerPedId()).state:set('isLooting', false, true)
    end)
end)

RegisterNetEvent('gs-survival:client:openArcStash', function(sId, pairedStashId)
    Entity(PlayerPedId()).state:set('isLooting', true, true)
    exports.ox_inventory:openInventory('stash', sId)
    if pairedStashId then
        exports.ox_inventory:setStashTarget(pairedStashId)
    end
    CreateThread(function()
        while LocalPlayer.state.invOpen do Wait(100) end
        Entity(PlayerPedId()).state:set('isLooting', false, true)
    end)
end)

RegisterNetEvent('gs-survival:client:removeArcContainer', function(containerId)
    local blip = arcContainerBlips and arcContainerBlips[containerId]
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
    arcContainerBlips[containerId] = nil

    local container = arcContainers and arcContainers[containerId]
    if not container then return end

    if container.entity and DoesEntityExist(container.entity) then
        if container.targetName then
            exports.ox_target:removeLocalEntity(container.entity, container.targetName)
        end
        DeleteEntity(container.entity)
    end

    arcContainers[containerId] = nil
end)

CreateThread(function()
    while resourceRunning do
        if currentModeId == 'arc_pvp' then
            RefreshArcFriendlyBlips()
            RefreshArcSessionVehicleBlips()
            RefreshArcOverlayTeam()
            Wait(4000)
        else
            Wait(2000)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    resourceRunning = false
    isMenuOpen = false
    menuStateCacheKey = nil
    ApplyMinimapLayout(DEFAULT_MINIMAP_LAYOUT)
    ClearArcOverlay()
    ClearArcDeploymentZoneBlips()
    ClearArcExtractionState()
    ClearArcBarricades()
end)

RegisterNetEvent('gs-survival:client:spawnArcDeathDrop', function(data)
    if not data or not data.id or not data.coords then return end

    local dropModel = Config.ArcPvP and Config.ArcPvP.DropModel
    SpawnArcContainer(
        data.id,
        vector3(data.coords.x, data.coords.y, data.coords.z),
        dropModel,
        data.label or 'Arc Ölüm Kutusu',
        1,
        'gs-survival:server:openArcDeathContainer',
        'arc_death_container',
        true
    )
end)

RegisterNetEvent('gs-survival:client:playSignalFlare', function(data)
    if not data or not data.coords then return end
    if currentModeId ~= 'arc_pvp' or isSurvivalActive ~= true then return end

    local activeBucketId = tonumber(myBucket)
    local targetBucketId = tonumber(data.bucketId)
    if targetBucketId and activeBucketId and targetBucketId ~= activeBucketId then
        return
    end

    PlaySignalFlare(data.coords)
end)

RegisterNetEvent('gs-survival:client:removeFromInvited', function(targetId)
    for i=1, #invitedPlayers do
        if invitedPlayers[i] == targetId then
            table.remove(invitedPlayers, i)
            break
        end
    end
end)
