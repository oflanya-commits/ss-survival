local QBCore = exports['qb-core']:GetCoreObject()
local MAX_LOBBY_SIZE = 4
local MAX_LOBBY_MEMBERS = MAX_LOBBY_SIZE - 1
local ARC_DEPLOYMENT_BLIP_INIT_DELAY_MS = 1500
local ARC_EXTRACTION_HELI_SPAWN_OFFSET = vector3(110.0, -70.0, 18.0)
local ARC_EXTRACTION_HELI_MIN_SPEED = 4.0
local ARC_EXTRACTION_HELI_MAX_SPEED = 25.0
local ARC_EXTRACTION_HELI_HOVER_SPEED = 6.0
local ARC_EXTRACTION_HELI_RADIUS = 8.0
local ARC_EXTRACTION_HELI_SLOW_DIST = 20.0
local ARC_EXTRACTION_HELI_MISSION_TYPE = 4
local ARC_EXTRACTION_HELI_MISSION_FLAGS = 0
local SCREEN_TRANSITION_FADE_DURATION_MS = 600
local SCREEN_TRANSITION_BLACK_HOLD_MS = 3400
local SCREEN_TRANSITION_TOTAL_DURATION_MS = (SCREEN_TRANSITION_FADE_DURATION_MS * 2) + SCREEN_TRANSITION_BLACK_HOLD_MS
local UI_PROGRESS_CANCEL_CONTROLS = { 177, 200, 202 }
local UI_PROGRESS_MIN_DURATION_MS = 250
local UI_PROGRESS_MAX_DURATION_MS = 60000
local DEFAULT_PROGRESS_TITLE = 'İşlem Sürüyor'
local DEFAULT_PROGRESS_LABEL = 'İşlem sürüyor...'
local SCREEN_TRANSITION_LABEL = 'OTURUM GEÇİŞİ'
local SCREEN_TRANSITION_ENTER_TITLE = "SESSION'A GİRİLİYOR"
local SCREEN_TRANSITION_RETURN_TITLE = 'LOBİYE DÖNÜLÜYOR'
local currentWave, isSurvivalActive, myBucket = 0, false, 0
local activeStageId = 1
local currentModeId = 'classic'
local spawnedPeds, invitedPlayers = {}, {}
local waitingForWave, countdown = false, 0
local notifiedDeath = false
local isEnding = false
local activeSurvivalPlayers = {}
local activeArcRaidPlayers = {}
local arcContainers = {}
local arcPlacedBarricades = {}
local arcSessionVehicles = {}
local arcContainerBlips = {}
local arcFriendlyBlips = {}
local arcZoneRadiusBlip = nil
local arcZoneCenterBlip = nil
local arcDeploymentZoneBlips = {}
local arcDeploymentZoneBlipLookup = {}
local hiddenMapBlips = {}
local MAX_BLIP_SPRITE_ID = 1000
local resourceRunning = true
local lobbyLeaderId = nil
local pendingInviteLeaderId = nil
local ownsLobby = false
local memberReadyState = false
local currentLobbyPublic = nil
local activeArcSquadPlayers = {}
local spectateIndex = 1
local isSpectating = false
local spectateCam = nil
local modeBoundaryGraceUntil = 0
local activeBoundaryRadius = nil
local activeArcDeployment = nil
local arcRaidEndAt = 0
local arcExtractionState = nil
local arcExtractionLocalDeadline = 0
local arcExtractionAvailableAt = 0
local arcExtractionZoneRadiusBlip = nil
local arcExtractionZoneCenterBlip = nil
local arcExtractionHeli = nil
local arcExtractionPilot = nil
local arcExtractionHeliTaskKey = nil
local arcExtractionMenuState = nil
local arcExtractionLastPhase = nil
local arcBarricadePreview = nil
local arcOverlayState = {
    enabled = false,
    showInfo = false,
    title = '',
    subtitle = '',
    lines = {},
    prompt = '',
    teamMembers = {}
}
local arcOverlayCacheKey = nil
local arcOverlayTeamCacheKey = nil
local arcOverlayInfoLastRefreshAt = 0
local arcOverlayInfoVisible = false
local menuStateCacheKey = nil
local isMenuOpen = false
local ARC_OVERLAY_INFO_REFRESH_INTERVAL_MS = 1000
-- Minimap coordinates use normalized screen anchors; clipType 0 restores the default square minimap,
-- while clipType 1 forces the ARC minimap into the top-right rounded layout.
local DEFAULT_MINIMAP_LAYOUT = {
    clipType = 0,
    minimap = { anchorX = 'L', anchorY = 'B', x = -0.0045, y = -0.022, width = 0.150, height = 0.188888 },
    mask = { anchorX = 'L', anchorY = 'B', x = 0.020, y = 0.032, width = 0.111, height = 0.159 },
    blur = { anchorX = 'L', anchorY = 'B', x = -0.03, y = 0.022, width = 0.266, height = 0.237 }
}
local ARC_MINIMAP_LAYOUT = {
    clipType = 1,
    minimap = { anchorX = 'R', anchorY = 'T', x = -0.010, y = 0.018, width = 0.160, height = 0.205 },
    mask = { anchorX = 'R', anchorY = 'T', x = 0.012, y = 0.046, width = 0.122, height = 0.176 },
    blur = { anchorX = 'R', anchorY = 'T', x = -0.040, y = 0.004, width = 0.260, height = 0.245 }
}
local GetCharacterName
local GetModeLabel
local GetActiveArcStageData
local BuildArcExtractionHudState

-- [NUI YARDIMCI FONKSİYONLAR]
local function OpenNUI(data)
    isMenuOpen = true
    SendNUIMessage(data)
    SetNuiFocus(true, true)
end

local function CloseNUI()
    isMenuOpen = false
    SendNUIMessage({ type = 'closeMenu' })
    SetNuiFocus(false, false)
end

local function RefreshMinimapLayout()
    if not resourceRunning then
        -- Resource shutdown does not reliably allow an extra yield, so force one immediate radar refresh pass.
        SetBigmapActive(true, false)
        SetBigmapActive(false, false)
        return
    end

    -- Toggling the big map forces GTA to immediately redraw the minimap with the new component positions.
    SetBigmapActive(true, false)
    -- Yield once so GTA can apply the temporary big map state before restoring the normal minimap view.
    Wait(0)
    SetBigmapActive(false, false)
end

local function ApplyMinimapLayout(layout)
    local minimap = layout.minimap
    local mask = layout.mask
    local blur = layout.blur

    SetMinimapClipType(layout.clipType or 0)
    SetMinimapComponentPosition('minimap', minimap.anchorX, minimap.anchorY, minimap.x, minimap.y, minimap.width, minimap.height)
    SetMinimapComponentPosition('minimap_mask', mask.anchorX, mask.anchorY, mask.x, mask.y, mask.width, mask.height)
    SetMinimapComponentPosition('minimap_blur', blur.anchorX, blur.anchorY, blur.x, blur.y, blur.width, blur.height)
    RefreshMinimapLayout()
end

local function SendArcNotify(message, notifyType, duration, title)
    if not message or message == '' then return end
    SendNUIMessage({
        type = 'arcNotify',
        data = {
            title = title or 'ARC Bildirimi',
            message = message,
            type = notifyType or 'info',
            duration = duration or 4500
        }
    })
end

local function GetNotifyTitle(notifyType, title)
    if title and title ~= '' then
        return title
    end

    if currentModeId == 'arc_pvp' then
        return 'ARC Bildirimi'
    end

    if notifyType == 'success' then
        return 'İşlem Tamamlandı'
    elseif notifyType == 'error' then
        return 'İşlem Başarısız'
    elseif notifyType == 'warning' then
        return 'Uyarı'
    elseif notifyType == 'primary' or notifyType == 'info' then
        return 'Bilgilendirme'
    end

    return 'Operasyon Bildirimi'
end

local function ShowArcResultBanner(title, label, duration, options)
    if not title or title == '' then return end
    options = options or {}
    SendNUIMessage({
        type = 'showArcBanner',
        data = {
            title = title,
            label = label or SCREEN_TRANSITION_LABEL,
            duration = duration or SCREEN_TRANSITION_TOTAL_DURATION_MS,
            transition = options.transition == true
        }
    })
end

local function ShowScreenTransition(title)
    ShowArcResultBanner(title, SCREEN_TRANSITION_LABEL, SCREEN_TRANSITION_TOTAL_DURATION_MS, {
        transition = true
    })
end

local function NotifyForMode(message, notifyType, duration, title)
    SendArcNotify(message, notifyType, duration, GetNotifyTitle(notifyType, title))
end

local function HideUiProgress()
    SendNUIMessage({ type = 'hideArcProgress' })
end

local function RunUiProgress(options, onComplete, onCancel)
    options = options or {}
    local duration = math.floor(tonumber(options.duration) or 0)
    if duration <= 0 then
        if onComplete then
            onComplete()
        end
        return
    end
    duration = math.max(UI_PROGRESS_MIN_DURATION_MS, math.min(duration, UI_PROGRESS_MAX_DURATION_MS))

    local ped = PlayerPedId()
    local disable = options.disable or {}
    local anim = options.anim or {}
    local canCancel = options.canCancel ~= false
    local cancelled = false
    local finished = false
    local endsAt = GetGameTimer() + duration

    if anim.dict and anim.anim then
        RequestAnimDict(anim.dict)
        while not HasAnimDictLoaded(anim.dict) do
            Wait(10)
        end

        TaskPlayAnim(
            ped,
            anim.dict,
            anim.anim,
            anim.blendIn or 3.0,
            anim.blendOut or 1.0,
            duration,
            anim.flags or 1,
            0.0,
            false,
            false,
            false
        )
    end

    SendNUIMessage({
        type = 'showArcProgress',
        data = {
            title = options.title or DEFAULT_PROGRESS_TITLE,
            label = options.label or DEFAULT_PROGRESS_LABEL,
            duration = duration,
            canCancel = canCancel
        }
    })

    CreateThread(function()
        while not finished do
            Wait(0)

            if disable.disableMovement then
                DisableControlAction(0, 21, true)
                DisableControlAction(0, 22, true)
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
                DisableControlAction(0, 36, true)
            end

            if disable.disableCarMovement then
                DisableControlAction(0, 59, true)
                DisableControlAction(0, 60, true)
                DisableControlAction(0, 61, true)
                DisableControlAction(0, 62, true)
                DisableControlAction(0, 63, true)
                DisableControlAction(0, 64, true)
                DisableControlAction(0, 71, true)
                DisableControlAction(0, 72, true)
                DisableControlAction(0, 75, true)
            end

            if disable.disableMouse then
                DisableControlAction(0, 1, true)
                DisableControlAction(0, 2, true)
                DisableControlAction(0, 106, true)
            end

            if disable.disableCombat then
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 37, true)
                DisableControlAction(0, 44, true)
                DisableControlAction(0, 45, true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisableControlAction(0, 143, true)
                DisableControlAction(0, 257, true)
                DisableControlAction(0, 263, true)
                DisableControlAction(0, 264, true)
            end

            local cancelRequested = false
            if canCancel then
                -- ESC ve frontend geri/pause tuşlarını aynı iptal davranışına bağla.
                for _, controlId in ipairs(UI_PROGRESS_CANCEL_CONTROLS) do
                    if IsControlJustPressed(0, controlId) then
                        cancelRequested = true
                        break
                    end
                end
            end

            if cancelRequested then
                cancelled = true
                finished = true
            elseif GetGameTimer() >= endsAt then
                finished = true
            end
        end

        HideUiProgress()

        if anim.dict and anim.anim then
            StopAnimTask(ped, anim.dict, anim.anim, 1.0)
        end

        if cancelled then
            if onCancel then
                onCancel()
            end
        elseif onComplete then
            onComplete()
        end
    end)
end

-- ARC baskın HUD'ı için yerel oyuncu ve aktif takım üyelerini canlı/ölü durumu ile liste haline getirir.
local function BuildArcOverlayTeamMembers()
    local members = {}
    local localServerId = GetPlayerServerId(PlayerId())
    local playerData = QBCore.Functions.GetPlayerData()
    local selfName = GetCharacterName(playerData)
    local selfAlive = not IsPedFatallyInjured(PlayerPedId())
    local trackedMembers = currentModeId == 'arc_pvp' and activeArcSquadPlayers or activeSurvivalPlayers

    members[#members + 1] = {
        name = selfName,
        isSelf = true,
        isAlive = selfAlive
    }

    for _, playerId in ipairs(trackedMembers or {}) do
        local serverId = tonumber(playerId)
        if serverId and serverId ~= tonumber(localServerId) then
            local playerIndex = GetPlayerFromServerId(serverId)
            local playerName = playerIndex ~= -1 and GetPlayerName(playerIndex) or ("Oyuncu #" .. tostring(serverId))
            local playerAlive = false
            if playerIndex ~= -1 and NetworkIsPlayerActive(playerIndex) then
                local targetPed = GetPlayerPed(playerIndex)
                playerAlive = DoesEntityExist(targetPed) and not IsPedFatallyInjured(targetPed)
            end

            members[#members + 1] = {
                name = playerName or ("Oyuncu #" .. tostring(serverId)),
                isSelf = false,
                isAlive = playerAlive
            }
        end
    end

    return members
end

local function BuildArcOverlayCacheKey(state)
    local parts = {
        tostring(state.enabled == true),
        tostring(state.showInfo == true),
        tostring(state.title or ''),
        tostring(state.subtitle or ''),
        tostring(state.prompt or '')
    }

    for _, line in ipairs(state.lines or {}) do
        parts[#parts + 1] = tostring(line)
    end

    for _, member in ipairs(state.teamMembers or {}) do
        parts[#parts + 1] = ("%s:%s:%s"):format(
            tostring(member.name or ''),
            tostring(member.isSelf == true),
            tostring(member.isAlive == true)
        )
    end

    return table.concat(parts, '|')
end

local function BuildArcOverlayTeamCacheKey(members)
    local parts = {}
    for _, member in ipairs(members or {}) do
        parts[#parts + 1] = ("%s:%s:%s"):format(
            tostring(member.name or ''),
            tostring(member.isSelf == true),
            tostring(member.isAlive == true)
        )
    end
    return table.concat(parts, '|')
end

local function PushArcOverlayState(partialState, force)
    if type(partialState) == 'table' then
        for key, value in pairs(partialState) do
            arcOverlayState[key] = value
        end
    end

    local payload = {
        enabled = arcOverlayState.enabled == true,
        showInfo = arcOverlayState.showInfo == true,
        title = arcOverlayState.title or '',
        subtitle = arcOverlayState.subtitle or '',
        lines = arcOverlayState.lines or {},
        prompt = arcOverlayState.prompt or '',
        teamMembers = arcOverlayState.teamMembers or {}
    }

    local cacheKey = BuildArcOverlayCacheKey(payload)
    if not force and cacheKey == arcOverlayCacheKey then
        return
    end

    arcOverlayCacheKey = cacheKey
    SendNUIMessage({
        type = 'setArcHud',
        data = payload
    })
end

local function ClearArcOverlay()
    arcOverlayState = {
        enabled = false,
        showInfo = false,
        title = '',
        subtitle = '',
        lines = {},
        prompt = '',
        teamMembers = {}
    }
    arcOverlayCacheKey = nil
    arcOverlayTeamCacheKey = nil
    arcOverlayInfoLastRefreshAt = 0
    arcOverlayInfoVisible = false
    SendNUIMessage({ type = 'clearArcHud' })
end

local function PushClassicSurvivalOverlay(stageData, aliveCount, maxWaves, lootTimerSeconds, forceRefresh)
    if currentModeId ~= 'classic' then
        return
    end

    local resolvedStageData = stageData or GetModeStageData('classic', activeStageId or 1)
    local resolvedMaxWaves = tonumber(maxWaves) or 0
    local currentWaveData = resolvedStageData and resolvedStageData.Waves and resolvedStageData.Waves[currentWave]
    local displayWave = tonumber(currentWave) or 1
    if displayWave < 1 then
        displayWave = 1
    end
    if resolvedMaxWaves < displayWave then
        resolvedMaxWaves = displayWave
    end
    local lines = {
        ("Dalga: %s/%s"):format(displayWave, resolvedMaxWaves)
    }

    if currentWaveData and currentWaveData.label and currentWaveData.label ~= '' then
        lines[#lines + 1] = ("Düşman: %s"):format(currentWaveData.label)
    end

    if lootTimerSeconds ~= nil then
        lines[#lines + 1] = ("Ganimet Toplama: %s sn"):format(math.max(0, math.floor(lootTimerSeconds)))
    elseif waitingForWave then
        lines[#lines + 1] = ("Hazırlanıyor: %s sn"):format(math.max(0, countdown or 0))
    else
        lines[#lines + 1] = ("Kalan Düşman: %s"):format(math.max(0, aliveCount or 0))
    end

    PushArcOverlayState({
        enabled = isSurvivalActive == true,
        showInfo = isSurvivalActive == true,
        title = (resolvedStageData and resolvedStageData.label) or 'Operasyon',
        subtitle = 'Survival saha telemetri',
        lines = lines,
        prompt = '',
        teamMembers = {}
    }, forceRefresh)
end

-- Sağ alt ARC takım panelini sadece üye listesi veya canlılık durumu değiştiğinde NUI'a tekrar yollar.
local function RefreshArcOverlayTeam()
    if currentModeId ~= 'arc_pvp' then
        return
    end

    local teamMembers = BuildArcOverlayTeamMembers()
    local teamCacheKey = BuildArcOverlayTeamCacheKey(teamMembers)
    if teamCacheKey == arcOverlayTeamCacheKey then
        return
    end

    arcOverlayTeamCacheKey = teamCacheKey
    PushArcOverlayState({
        enabled = isSurvivalActive == true,
        showInfo = arcOverlayInfoVisible == true,
        teamMembers = teamMembers
    })
end

-- Sol üst ARC bilgi panelini günceller; yerel oyuncu activeArcRaidPlayers içinde yoksa canlı sayısını ayrıca telafi eder.
local function RefreshArcOverlayInfo(promptText, force)
    if currentModeId ~= 'arc_pvp' then
        return
    end

    local nextPrompt = promptText
    if nextPrompt == nil then
        nextPrompt = arcOverlayState.prompt or ''
    end

    local now = GetGameTimer()
    local promptUnchanged = nextPrompt == (arcOverlayState.prompt or '')
    local withinThrottleWindow = (now - arcOverlayInfoLastRefreshAt) < ARC_OVERLAY_INFO_REFRESH_INTERVAL_MS
    if force ~= true and promptUnchanged and withinThrottleWindow then
        return
    end

    arcOverlayInfoLastRefreshAt = now

    local stageData = GetActiveArcStageData()
    local stageLabel = stageData and (stageData.zoneLabel or stageData.label) or "ARC Sektörü"
    local modeLabel = GetModeLabel(currentModeId)
    local raidTimeLeft = math.max(0, math.ceil((arcRaidEndAt - GetGameTimer()) / 1000))
    local aliveCount = 0
    local activeContainerCount = 0
    local extractionHud = BuildArcExtractionHudState()
    local lines = {}

    local trackedPlayers = activeArcRaidPlayers or activeSurvivalPlayers or {}
    local localServerId = tonumber(GetPlayerServerId(PlayerId()))
    local localTracked = false

    for _, id in ipairs(trackedPlayers) do
        local playerIndex = GetPlayerFromServerId(id)
        local targetPed = playerIndex ~= -1 and GetPlayerPed(playerIndex) or 0
        if playerIndex ~= -1 and NetworkIsPlayerActive(playerIndex) and DoesEntityExist(targetPed) and not IsPedFatallyInjured(targetPed) then
            aliveCount = aliveCount + 1
        end
        if not localTracked and tonumber(id) == localServerId then
            localTracked = true
        end
    end

    if not IsPedFatallyInjured(PlayerPedId()) then
        -- Bazı ARC güncellemelerinde local oyuncu listesi gecikmeli gelebiliyor; HUD canlı sayısı bu arada eksik görünmesin.
        if not localTracked then
            aliveCount = aliveCount + 1
        end
    end

    for _, container in pairs(arcContainers or {}) do
        if container and container.entity and DoesEntityExist(container.entity) then
            activeContainerCount = activeContainerCount + 1
        end
    end

    lines[#lines + 1] = ("Mod: %s"):format(modeLabel:upper())
    lines[#lines + 1] = ("Aktif Baskıncı: %s"):format(aliveCount)
    lines[#lines + 1] = ("Aktif Loot Kasası: %s"):format(activeContainerCount)
    lines[#lines + 1] = ("Baskın Sonu: %s sn"):format(raidTimeLeft)

    if extractionHud then
        lines[#lines + 1] = ("Tahliye: %s"):format(extractionHud.phaseLabel or "Extraction")
        if extractionHud.phase == 'idle' and extractionHud.availableIn > 0 then
            lines[#lines + 1] = ("Unlock: %s sn"):format(extractionHud.availableIn)
        elseif extractionHud.countdown > 0 then
            lines[#lines + 1] = ("Sayaç: %s sn"):format(extractionHud.countdown)
        end
    end

    PushArcOverlayState({
        enabled = isSurvivalActive == true,
        showInfo = arcOverlayInfoVisible == true,
        title = stageLabel,
        subtitle = "ARC saha telemetrisi",
        lines = lines,
        prompt = nextPrompt,
        teamMembers = arcOverlayState.teamMembers or BuildArcOverlayTeamMembers()
    })
end

local function ClearArcContainers()
    for containerId, blip in pairs(arcContainerBlips or {}) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
        arcContainerBlips[containerId] = nil
    end

    if not arcContainers then
        arcContainers = {}
        return
    end

    for containerId, container in pairs(arcContainers) do
        if container.entity and DoesEntityExist(container.entity) then
            if container.targetName then
                exports.ox_target:removeLocalEntity(container.entity, container.targetName)
            end
            DeleteEntity(container.entity)
        end
        arcContainers[containerId] = nil
    end
end

local function ClearArcBarricades()
    if arcBarricadePreview and arcBarricadePreview.entity and DoesEntityExist(arcBarricadePreview.entity) then
        DeleteEntity(arcBarricadePreview.entity)
    end
    arcBarricadePreview = nil

    for barricadeId, barricade in pairs(arcPlacedBarricades or {}) do
        if barricade and barricade.entity and DoesEntityExist(barricade.entity) then
            DeleteEntity(barricade.entity)
        end
        arcPlacedBarricades[barricadeId] = nil
    end
end

local function SpawnLocalArcBarricade(barricadeData)
    local barricadeId = barricadeData and barricadeData.id
    local coords = ToVector3(barricadeData and barricadeData.coords)
    local model = barricadeData and barricadeData.model
    if not barricadeId or not coords or not model then
        return
    end

    local existingBarricade = arcPlacedBarricades[barricadeId]
    if existingBarricade and existingBarricade.entity and DoesEntityExist(existingBarricade.entity) then
        DeleteEntity(existingBarricade.entity)
    end

    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end

    local entity = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, false, false, false)
    SetEntityAsMissionEntity(entity, true, true)
    SetEntityHeading(entity, tonumber(barricadeData.heading or 0.0) or 0.0)
    FreezeEntityPosition(entity, true)
    PlaceObjectOnGroundProperly(entity)
    SetModelAsNoLongerNeeded(model)

    arcPlacedBarricades[barricadeId] = {
        entity = entity
    }
end

local function GetArcBarricadePreviewPosition(ped, placementState)
    local config = GetArcBarricadeConfig()
    local placementDistance = tonumber(config.PlaceDistance) or 2.2
    local forwardCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, placementDistance, 0.0)
    local testHeight = forwardCoords.z + 5.0
    local foundGround, groundZ = GetGroundZFor_3dCoord(forwardCoords.x, forwardCoords.y, testHeight, false)
    local zCoord = foundGround and groundZ or forwardCoords.z
    return vector3(forwardCoords.x, forwardCoords.y, zCoord), placementState.heading
end

local function ClearArcFriendlyBlips()
    for playerId, blip in pairs(arcFriendlyBlips or {}) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
        arcFriendlyBlips[playerId] = nil
    end
end

local function ClearArcSessionVehicles()
    for vehicleId, vehicleState in pairs(arcSessionVehicles or {}) do
        local blip = vehicleState and vehicleState.blip or nil
        if blip and DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
        arcSessionVehicles[vehicleId] = nil
    end
end

local function GetArcSessionVehicleBlipStyle(kind)
    if kind == 'helicopter' then
        return 64, 3, 0.9
    end

    return 225, 38, 0.85
end

local function CreateArcSessionVehicleBlip(vehicleState, entity)
    local coords = ToVector3(vehicleState and vehicleState.coords)
    local sprite, colour, scale = GetArcSessionVehicleBlipStyle(vehicleState and vehicleState.kind)
    local blip = entity and AddBlipForEntity(entity) or (coords and AddBlipForCoord(coords.x, coords.y, coords.z) or nil)
    if not blip or not DoesBlipExist(blip) then
        return nil
    end

    SetBlipSprite(blip, sprite)
    SetBlipColour(blip, colour)
    SetBlipScale(blip, scale)
    SetBlipAsShortRange(blip, false)
    ShowHeadingIndicatorOnBlip(blip, entity ~= nil)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(vehicleState.label or (vehicleState.kind == 'helicopter' and 'ARC Helikopteri' or 'ARC Araç'))
    EndTextCommandSetBlipName(blip)

    if not entity and coords then
        SetBlipCoords(blip, coords.x, coords.y, coords.z)
        SetBlipRotation(blip, math.floor((tonumber(vehicleState.heading or 0.0) or 0.0) + 0.5))
    end

    return blip
end

local function ApplyArcSessionVehicles(vehicleStates)
    local activeIds = {}

    for _, vehicleData in ipairs(vehicleStates or {}) do
        local vehicleId = tostring(vehicleData and vehicleData.id or '')
        if vehicleId ~= '' then
            activeIds[vehicleId] = true
            local trackedVehicle = arcSessionVehicles[vehicleId] or {}
            local nextNetId = tonumber(vehicleData.netId) or trackedVehicle.netId
            if trackedVehicle.netId ~= nextNetId then
                trackedVehicle.clientPrepared = nil
            end
            trackedVehicle.netId = nextNetId
            trackedVehicle.kind = vehicleData.kind or trackedVehicle.kind or 'car'
            trackedVehicle.label = vehicleData.label or trackedVehicle.label or 'ARC Araç'
            trackedVehicle.model = vehicleData.model or trackedVehicle.model
            trackedVehicle.coords = ToVector3(vehicleData.coords) or trackedVehicle.coords
            trackedVehicle.heading = tonumber(vehicleData.heading or trackedVehicle.heading or 0.0) or 0.0
            arcSessionVehicles[vehicleId] = trackedVehicle
        end
    end

    for vehicleId, vehicleState in pairs(arcSessionVehicles or {}) do
        if not activeIds[vehicleId] then
            if vehicleState.blip and DoesBlipExist(vehicleState.blip) then
                RemoveBlip(vehicleState.blip)
            end
            arcSessionVehicles[vehicleId] = nil
        end
    end
end

local function RefreshArcSessionVehicleBlips()
    if currentModeId ~= 'arc_pvp' then
        ClearArcSessionVehicles()
        return
    end

    for vehicleId, vehicleState in pairs(arcSessionVehicles or {}) do
        local entity = 0
        local netId = vehicleState and tonumber(vehicleState.netId) or nil
        if netId and NetworkDoesNetworkIdExist(netId) then
            entity = NetToVeh(netId)
        end

        local hasEntity = entity ~= 0 and DoesEntityExist(entity)
        local targetMode = hasEntity and 'entity' or 'coord'
        local coords = hasEntity and GetEntityCoords(entity) or ToVector3(vehicleState.coords)
        local heading = hasEntity and tonumber(GetEntityHeading(entity) or vehicleState.heading or 0.0) or tonumber(vehicleState.heading or 0.0) or 0.0

        if hasEntity and vehicleState.clientPrepared ~= true then
            if netId then
                if type(SetNetworkIdCanMigrate) == 'function' then
                    SetNetworkIdCanMigrate(netId, true)
                end
                if type(SetNetworkIdExistsOnAllMachines) == 'function' then
                    SetNetworkIdExistsOnAllMachines(netId, true)
                end
            end
            SetVehicleEngineOn(entity, true, true, false)
            SetVehicleDoorsLocked(entity, 1)
            vehicleState.clientPrepared = true
        end

        vehicleState.coords = coords or vehicleState.coords
        vehicleState.heading = heading

        if not coords then
            if vehicleState.blip and DoesBlipExist(vehicleState.blip) then
                RemoveBlip(vehicleState.blip)
            end
            vehicleState.blip = nil
            vehicleState.blipMode = nil
        else
            if (not vehicleState.blip or not DoesBlipExist(vehicleState.blip)) or vehicleState.blipMode ~= targetMode then
                if vehicleState.blip and DoesBlipExist(vehicleState.blip) then
                    RemoveBlip(vehicleState.blip)
                end
                vehicleState.blip = CreateArcSessionVehicleBlip(vehicleState, hasEntity and entity or nil)
                vehicleState.blipMode = vehicleState.blip and targetMode or nil
            end

            if vehicleState.blip and DoesBlipExist(vehicleState.blip) and targetMode == 'coord' then
                SetBlipCoords(vehicleState.blip, coords.x, coords.y, coords.z)
                SetBlipRotation(vehicleState.blip, math.floor(heading + 0.5))
            end
        end

        arcSessionVehicles[vehicleId] = vehicleState
    end
end

local function ClearArcZoneBlips()
    if DoesBlipExist(arcZoneRadiusBlip) then
        RemoveBlip(arcZoneRadiusBlip)
    end
    if DoesBlipExist(arcZoneCenterBlip) then
        RemoveBlip(arcZoneCenterBlip)
    end

    arcZoneRadiusBlip = nil
    arcZoneCenterBlip = nil
end

local function ClearArcExtractionScene()
    if arcExtractionPilot and DoesEntityExist(arcExtractionPilot) then
        DeleteEntity(arcExtractionPilot)
    end
    if arcExtractionHeli and DoesEntityExist(arcExtractionHeli) then
        DeleteEntity(arcExtractionHeli)
    end
    arcExtractionPilot = nil
    arcExtractionHeli = nil
    arcExtractionHeliTaskKey = nil
end

local function ClearArcExtractionBlips()
    if DoesBlipExist(arcExtractionZoneRadiusBlip) then
        RemoveBlip(arcExtractionZoneRadiusBlip)
    end
    if DoesBlipExist(arcExtractionZoneCenterBlip) then
        RemoveBlip(arcExtractionZoneCenterBlip)
    end

    arcExtractionZoneRadiusBlip = nil
    arcExtractionZoneCenterBlip = nil
end

local function ClearArcExtractionState()
    arcExtractionState = nil
    arcExtractionLocalDeadline = 0
    arcExtractionAvailableAt = 0
    arcExtractionMenuState = nil
    arcExtractionLastPhase = nil
    ClearArcSessionVehicles()
    ClearArcExtractionBlips()
    ClearArcExtractionScene()
end

local function IsArcDeploymentZoneBlip(blip)
    return blip and (arcDeploymentZoneBlipLookup[blip] == true) or false
end

local function HideNonArcBlips()
    hiddenMapBlips = hiddenMapBlips or {}

    for sprite = 1, MAX_BLIP_SPRITE_ID do
        local blip = GetFirstBlipInfoId(sprite)
        while DoesBlipExist(blip) do
            if not hiddenMapBlips[blip] and not IsArcDeploymentZoneBlip(blip) then
                hiddenMapBlips[blip] = {
                    alpha = GetBlipAlpha(blip)
                }
                SetBlipAlpha(blip, 0)
            end

            blip = GetNextBlipInfoId(sprite)
        end
    end
end

local function RestoreHiddenBlips()
    for blip, state in pairs(hiddenMapBlips or {}) do
        if DoesBlipExist(blip) then
            SetBlipAlpha(blip, tonumber(state and state.alpha or 255) or 255)
        end
        hiddenMapBlips[blip] = nil
    end
end

local function RefreshArcFriendlyBlips()
    if currentModeId ~= 'arc_pvp' then
        ClearArcFriendlyBlips()
        return
    end

    local localServerId = GetPlayerServerId(PlayerId())
    local activeIds = {}

    for _, playerId in ipairs(activeSurvivalPlayers or {}) do
        local serverId = tonumber(playerId)
        if serverId and serverId ~= tonumber(localServerId) then
            local playerIndex = GetPlayerFromServerId(serverId)
            local targetPed = playerIndex ~= -1 and GetPlayerPed(playerIndex) or 0
            if playerIndex ~= -1 and NetworkIsPlayerActive(playerIndex) and DoesEntityExist(targetPed) and not IsPedFatallyInjured(targetPed) then
                activeIds[serverId] = true

                if not DoesBlipExist(arcFriendlyBlips[serverId]) then
                    local blip = AddBlipForEntity(targetPed)
                    SetBlipSprite(blip, 1)
                    SetBlipColour(blip, 2)
                    SetBlipScale(blip, 0.8)
                    SetBlipAsShortRange(blip, false)
                    ShowHeadingIndicatorOnBlip(blip, true)
                    BeginTextCommandSetBlipName("STRING")
                    AddTextComponentString(GetPlayerName(playerIndex) or "Takım Arkadaşı")
                    EndTextCommandSetBlipName(blip)
                    arcFriendlyBlips[serverId] = blip
                end
            end
        end
    end

    for playerId, blip in pairs(arcFriendlyBlips or {}) do
        if not activeIds[tonumber(playerId)] then
            if DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
            arcFriendlyBlips[playerId] = nil
        end
    end
end

local function SpawnArcContainer(containerId, coords, model, label, rollCount, openEventName, containerPrefix, isDeathCrate)
    if not containerId or not coords or not model then return end

    local resolvedOpenEvent = openEventName or 'gs-survival:server:openArcLootContainer'
    local resolvedPrefix = containerPrefix or 'arc_container'
    local progressLabel = isDeathCrate and 'Ölüm kutusu açılıyor...' or 'Loot açılıyor...'
    local actionTitle = isDeathCrate and 'ARC Ölüm Kutusu' or 'ARC Loot'

    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end

    local object = CreateObjectNoOffset(model, coords.x, coords.y, coords.z - 1.0, false, false, false)
    SetEntityAsMissionEntity(object, true, true)
    FreezeEntityPosition(object, true)
    PlaceObjectOnGroundProperly(object)

    local targetName = resolvedPrefix .. '_' .. containerId
    arcContainers[containerId] = {
        entity = object,
        targetName = targetName
    }

    if currentModeId == 'arc_pvp' then
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, 587)
        SetBlipColour(blip, 5)
        SetBlipScale(blip, 0.8)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(label or 'Arc Loot')
        EndTextCommandSetBlipName(blip)
        arcContainerBlips[containerId] = blip
    end

    exports.ox_target:addLocalEntity(object, {
        {
            name = targetName,
            icon = 'fas fa-box-open',
            label = label or 'Arc Loot',
            distance = 2.0,
            onSelect = function()
                RunUiProgress({
                    title = actionTitle,
                    label = progressLabel,
                    duration = 2500,
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
                    TriggerServerEvent(resolvedOpenEvent, containerId, rollCount or 1)
                end, function()
                    NotifyForMode("Loot alma işlemi iptal edildi.", "error", 3500, actionTitle)
                end)
            end
        }
    })
end

local function ShufflePoints(points)
    local shuffled = {}
    for i, point in ipairs(points or {}) do
        shuffled[i] = point
    end

    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    return shuffled
end

local function GetModeStages(modeId)
    if modeId == 'arc_pvp' then
        return (Config.ArcPvP and Config.ArcPvP.Arenas) or {}
    end

    return Config.Stages or {}
end

local function GetModeStageData(modeId, stageId)
    local stages = GetModeStages(modeId)
    return stages[tonumber(stageId or 1)]
end

local function GetSurvivalMetadata()
    return (Config.Survival and Config.Survival.Metadata) or {}
end

local function ToVector3(coords)
    if not coords then return nil end
    if type(coords) == 'vector3' then return coords end
    if coords.x and coords.y and coords.z then
        return vector3(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)
    end
    return nil
end

local function GetArcBarricadeConfig()
    return (Config.ArcPvP and Config.ArcPvP.BarricadeKit) or {}
end

local function GetArcExtractionCountdownSeconds()
    if arcExtractionLocalDeadline <= 0 then
        return 0
    end

    return math.max(0, math.ceil((arcExtractionLocalDeadline - GetGameTimer()) / 1000))
end

local function GetArcExtractionAvailableSeconds()
    if arcExtractionAvailableAt <= 0 then
        return 0
    end

    return math.max(0, math.ceil((arcExtractionAvailableAt - GetGameTimer()) / 1000))
end

local function GetArcExtractionPhaseLabel(phase)
    local labels = {
        idle = "Kilitli",
        available = "Tahliye Hazır",
        called = "Tahliye Çağrıldı",
        inbound = "Airlift Yolda",
        ready = "Kalkışa Hazır",
        extracted = "Tahliye Başarılı",
        failed = "Tahliye Kesildi",
        cleaned = "Sahne Temizleniyor"
    }

    return labels[tostring(phase or 'idle')] or "Extraction"
end

local function PlaySignalFlare(coords)
    local flareCoords = ToVector3(coords)
    local ownerPed = PlayerPedId()
    local flareWeaponHash = `weapon_flare`
    if not flareCoords or ownerPed == 0 then
        return
    end

    RequestWeaponAsset(flareWeaponHash, 31, 0)
    local timeoutAt = GetGameTimer() + 2000
    while not HasWeaponAssetLoaded(flareWeaponHash) and GetGameTimer() < timeoutAt do
        Wait(0)
    end

    if not HasWeaponAssetLoaded(flareWeaponHash) then
        return
    end

    ShootSingleBulletBetweenCoords(
        flareCoords.x,
        flareCoords.y,
        flareCoords.z + 1.0,
        flareCoords.x,
        flareCoords.y,
        flareCoords.z + 85.0,
        0,
        true,
        flareWeaponHash,
        ownerPed,
        true,
        false,
        2200.0
    )
    RemoveWeaponAsset(flareWeaponHash)
end

BuildArcExtractionHudState = function()
    local extraction = arcExtractionMenuState or arcExtractionState
    if not extraction or extraction.enabled ~= true then
        return nil
    end

    local countdown = GetArcExtractionCountdownSeconds()
    local availableIn = GetArcExtractionAvailableSeconds()
    local objective = extraction.objective or "Extraction verisi bekleniyor."

    if extraction.phase == 'idle' and availableIn > 0 then
        objective = ("Extraction hattı %s sn sonra açılacak."):format(availableIn)
    elseif (extraction.phase == 'inbound' or extraction.phase == 'ready' or extraction.phase == 'called') and countdown > 0 then
        objective = objective .. (" • %s sn"):format(countdown)
    end

    return {
        phase = extraction.phase,
        phaseLabel = extraction.phaseLabel or GetArcExtractionPhaseLabel(extraction.phase),
        objective = objective,
        countdown = countdown,
        availableIn = availableIn
    }
end

local function GetArcExtractionDisplayZones()
    if not arcExtractionState or arcExtractionState.enabled ~= true then
        return {}
    end

    if arcExtractionState.phase == 'available' or arcExtractionState.phase == 'idle' then
        if type(arcExtractionState.zones) == 'table' and #arcExtractionState.zones > 0 then
            return arcExtractionState.zones
        end
    end

    if arcExtractionState.zone then
        return { arcExtractionState.zone }
    end

    return {}
end

local function CreateArcExtractionBlips()
    ClearArcExtractionBlips()
    if not arcExtractionState or arcExtractionState.enabled ~= true or not arcExtractionState.zone then
        return
    end

    local zoneCoords = ToVector3(arcExtractionState.zone.coords)
    if not zoneCoords then
        return
    end

    arcExtractionZoneCenterBlip = AddBlipForCoord(zoneCoords.x, zoneCoords.y, zoneCoords.z)
    if DoesBlipExist(arcExtractionZoneCenterBlip) then
        SetBlipSprite(arcExtractionZoneCenterBlip, 64)
        SetBlipDisplay(arcExtractionZoneCenterBlip, 4)
        SetBlipScale(arcExtractionZoneCenterBlip, 0.95)
        SetBlipColour(arcExtractionZoneCenterBlip, 47)
        SetBlipAsShortRange(arcExtractionZoneCenterBlip, false)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(arcExtractionState.zone.label or "Extraction")
        EndTextCommandSetBlipName(arcExtractionZoneCenterBlip)
    end
end

local function EnsureArcExtractionScene()
    if not arcExtractionState or arcExtractionState.enabled ~= true or arcExtractionState.spawnHelicopter ~= true or arcExtractionState.useHelicopterScene == false then
        ClearArcExtractionScene()
        return
    end

    if arcExtractionState.phase ~= 'called' and arcExtractionState.phase ~= 'inbound' and arcExtractionState.phase ~= 'ready' then
        ClearArcExtractionScene()
        return
    end

    local zoneCoords = ToVector3(arcExtractionState.zone and arcExtractionState.zone.coords)
    if not zoneCoords then
        ClearArcExtractionScene()
        return
    end

    local model = joaat(arcExtractionState.helicopterModel or 'frogger')
    if not IsModelInCdimage(model) then
        return
    end

    local hoverHeight = tonumber(arcExtractionState.helicopterHeight or 80.0) or 80.0
    local hoverCoords = vector3(zoneCoords.x, zoneCoords.y, zoneCoords.z + hoverHeight)
    local startCoords = vector3(
        zoneCoords.x + ARC_EXTRACTION_HELI_SPAWN_OFFSET.x,
        zoneCoords.y + ARC_EXTRACTION_HELI_SPAWN_OFFSET.y,
        zoneCoords.z + hoverHeight + ARC_EXTRACTION_HELI_SPAWN_OFFSET.z
    )
    local heading = tonumber(arcExtractionState.zone.heading or 0.0) or 0.0
    local shouldApproach = arcExtractionState.phase == 'called' or arcExtractionState.phase == 'inbound'
    local spawnCoords = shouldApproach and startCoords or hoverCoords

    if not arcExtractionHeli or not DoesEntityExist(arcExtractionHeli) then
        RequestModel(model)
        while not HasModelLoaded(model) do Wait(10) end
        arcExtractionHeli = CreateVehicle(model, spawnCoords.x, spawnCoords.y, spawnCoords.z, heading, false, false)
        SetEntityAsMissionEntity(arcExtractionHeli, true, true)
        SetEntityInvincible(arcExtractionHeli, true)
        SetVehicleEngineOn(arcExtractionHeli, true, true, false)
        SetHeliBladesFullSpeed(arcExtractionHeli)
        SetVehicleSearchlight(arcExtractionHeli, true, false)
        SetModelAsNoLongerNeeded(model)
    end

    if (not arcExtractionPilot or not DoesEntityExist(arcExtractionPilot)) and arcExtractionHeli and DoesEntityExist(arcExtractionHeli) then
        local pilotModel = joaat('s_m_m_pilot_01')
        if IsModelInCdimage(pilotModel) then
            RequestModel(pilotModel)
            while not HasModelLoaded(pilotModel) do Wait(10) end
            arcExtractionPilot = CreatePedInsideVehicle(arcExtractionHeli, 4, pilotModel, -1, false, false)
            SetModelAsNoLongerNeeded(pilotModel)

            if arcExtractionPilot and DoesEntityExist(arcExtractionPilot) then
                SetEntityAsMissionEntity(arcExtractionPilot, true, true)
                SetEntityInvincible(arcExtractionPilot, true)
                SetBlockingOfNonTemporaryEvents(arcExtractionPilot, true)
                SetPedKeepTask(arcExtractionPilot, true)
            end
        end
    end

    if not arcExtractionPilot or not DoesEntityExist(arcExtractionPilot) then
        return
    end

    local targetTaskKey = ("%s:%s:%s:%s"):format(
        tostring(arcExtractionState.phase or 'idle'),
        math.floor(hoverCoords.x * 10.0 + 0.5),
        math.floor(hoverCoords.y * 10.0 + 0.5),
        math.floor(hoverCoords.z * 10.0 + 0.5)
    )

    if arcExtractionHeliTaskKey ~= targetTaskKey then
        local inboundSeconds = math.max(1.0, tonumber(arcExtractionState.callDelay or 45) or 45.0)
        local approachDistance = #(hoverCoords - startCoords)
        local flightSpeed = shouldApproach
            and math.max(ARC_EXTRACTION_HELI_MIN_SPEED, math.min(ARC_EXTRACTION_HELI_MAX_SPEED, approachDistance / inboundSeconds))
            or ARC_EXTRACTION_HELI_HOVER_SPEED

        ClearPedTasks(arcExtractionPilot)
        TaskHeliMission(
            arcExtractionPilot,
            arcExtractionHeli,
            0,
            0,
            hoverCoords.x,
            hoverCoords.y,
            hoverCoords.z,
            ARC_EXTRACTION_HELI_MISSION_TYPE,
            flightSpeed,
            ARC_EXTRACTION_HELI_RADIUS,
            heading,
            hoverHeight,
            math.max(18.0, hoverHeight * 0.5),
            ARC_EXTRACTION_HELI_SLOW_DIST,
            ARC_EXTRACTION_HELI_MISSION_FLAGS
        )
        SetPedKeepTask(arcExtractionPilot, true)
        arcExtractionHeliTaskKey = targetTaskKey
    end

    SetVehicleEngineOn(arcExtractionHeli, true, true, false)
    SetHeliBladesFullSpeed(arcExtractionHeli)
end

local function ApplyArcExtractionState(state, notifyPayload)
    if not state or state.enabled ~= true then
        ClearArcExtractionState()
        return
    end

    arcExtractionState = state
    arcExtractionMenuState = state
    arcExtractionLocalDeadline = GetGameTimer() + (tonumber(state.remainingMs or 0) or 0)
    arcExtractionAvailableAt = GetGameTimer() + (tonumber(state.availableInMs or 0) or 0)
    CreateArcExtractionBlips()
    EnsureArcExtractionScene()

    local phase = tostring(state.phase or 'idle')
    if notifyPayload and notifyPayload.message then
        NotifyForMode(notifyPayload.message, notifyPayload.type or 'primary', 4500, "ARC Tahliye")
    elseif arcExtractionLastPhase and arcExtractionLastPhase ~= phase then
        NotifyForMode(GetArcExtractionPhaseLabel(phase), phase == 'failed' and 'error' or 'primary', 4000, "ARC Tahliye")
    end

    arcExtractionLastPhase = phase
    RefreshArcOverlayInfo(nil, true)
end

GetActiveArcStageData = function()
    if currentModeId == 'arc_pvp' and activeArcDeployment and activeArcDeployment.center then
        return activeArcDeployment
    end

    return GetModeStageData(currentModeId, activeStageId)
end

local function CalculateStageBoundaryRadius(stageData)
    local baseDistance = tonumber(Config.Combat and Config.Combat.BoundaryDistance or 90.0) or 90.0
    if not stageData or not stageData.center then
        return baseDistance
    end

    if stageData.boundaryRadius then
        return tonumber(stageData.boundaryRadius) or baseDistance
    end

    local furthestPoint = 0.0
    local centerCoords = ToVector3(stageData.center)
    local boundaryPoints = stageData.lootNodes or stageData.spawnPoints or {}
    for _, point in ipairs(boundaryPoints) do
        local pointCoords = ToVector3(point.coords or point)
        if pointCoords and centerCoords then
            local pointDistance = #(pointCoords - centerCoords)
            if pointDistance > furthestPoint then
                furthestPoint = pointDistance
            end
        end
    end

    local arcPadding = tonumber(Config.ArcPvP and Config.ArcPvP.BoundaryPadding or 35.0) or 35.0
    return math.max(baseDistance, furthestPoint + arcPadding)
end

local function GetModeBoundaryRadius(modeId, stageData)
    return CalculateStageBoundaryRadius(stageData)
end

local function GetArcMapZoneStyle(regionId)
    local regionKey = regionId and tostring(regionId):lower() or nil

    if regionKey == 'green' then
        return 2, 100
    elseif regionKey == 'red' then
        return 1, 110
    elseif regionKey == 'yellow' then
        return 5, 110
    end

    return 3, 100
end

local function ClearArcDeploymentZoneBlips()
    for zoneId, zoneBlips in pairs(arcDeploymentZoneBlips or {}) do
        if zoneBlips then
            if DoesBlipExist(zoneBlips.center) then
                RemoveBlip(zoneBlips.center)
            end
            if zoneBlips.center then
                arcDeploymentZoneBlipLookup[zoneBlips.center] = nil
            end

            if DoesBlipExist(zoneBlips.extraction) then
                RemoveBlip(zoneBlips.extraction)
            end
            if zoneBlips.extraction then
                arcDeploymentZoneBlipLookup[zoneBlips.extraction] = nil
            end
        end

        arcDeploymentZoneBlips[zoneId] = nil
    end
end

local function CreateArcDeploymentZoneBlips()
    ClearArcDeploymentZoneBlips()

    local deploymentZones = Config.ArcPvP and Config.ArcPvP.DeploymentZones or {}
    local lootRegions = Config.ArcPvP and Config.ArcPvP.LootRegions or {}
    local extractionZones = Config.ArcPvP and Config.ArcPvP.Extraction and Config.ArcPvP.Extraction.Zones or {}

    for zoneId, zoneData in pairs(deploymentZones) do
        local centerCoords = zoneData and ToVector3(zoneData.center)
        if centerCoords then
            local blipColor, blipAlpha = GetArcMapZoneStyle(zoneData.lootRegion)
            local regionData = lootRegions[zoneData.lootRegion or '']
            local zoneLabel = zoneData.label or ("Bölge " .. tostring(zoneId))
            local regionLabel = regionData and regionData.label or "ARC Bölgesi"
            local zoneBlips = {}

            zoneBlips.center = AddBlipForCoord(centerCoords.x, centerCoords.y, centerCoords.z)
            if DoesBlipExist(zoneBlips.center) then
                SetBlipSprite(zoneBlips.center, 161)
                SetBlipDisplay(zoneBlips.center, 4)
                SetBlipScale(zoneBlips.center, 0.85)
                SetBlipColour(zoneBlips.center, blipColor)
                SetBlipAsShortRange(zoneBlips.center, false)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(("%s - %s"):format(zoneLabel, regionLabel))
                EndTextCommandSetBlipName(zoneBlips.center)
                arcDeploymentZoneBlipLookup[zoneBlips.center] = true
            end

            arcDeploymentZoneBlips[zoneId] = zoneBlips
        end
    end

    for zoneIndex, zoneData in ipairs(extractionZones) do
        local extractionCoords = ToVector3(zoneData and zoneData.coords)
        if extractionCoords then
            local zoneBlips = {}
            local zoneLabel = zoneData.label or ("Airlift " .. tostring(zoneIndex))

            zoneBlips.extraction = AddBlipForCoord(extractionCoords.x, extractionCoords.y, extractionCoords.z)
            if DoesBlipExist(zoneBlips.extraction) then
                SetBlipSprite(zoneBlips.extraction, 64)
                SetBlipDisplay(zoneBlips.extraction, 4)
                SetBlipScale(zoneBlips.extraction, 0.8)
                SetBlipColour(zoneBlips.extraction, 47)
                SetBlipAlpha(zoneBlips.extraction, 90)
                SetBlipAsShortRange(zoneBlips.extraction, false)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(("Airlift - %s"):format(zoneLabel))
                EndTextCommandSetBlipName(zoneBlips.extraction)
                arcDeploymentZoneBlipLookup[zoneBlips.extraction] = true
            end

            arcDeploymentZoneBlips[("__arc_extraction_%s"):format(zoneIndex)] = zoneBlips
        end
    end
end

local function CreateArcZoneBlips(stageData)
    ClearArcZoneBlips()

    local centerCoords = stageData and ToVector3(stageData.center)
    if not centerCoords then
        return
    end

    local blipColor, _ = GetArcMapZoneStyle(stageData.lootRegion)
    local blipLabel = stageData.zoneLabel or stageData.label or "ARC Baskın Bölgesi"

    arcZoneCenterBlip = AddBlipForCoord(centerCoords.x, centerCoords.y, centerCoords.z)
    if DoesBlipExist(arcZoneCenterBlip) then
        SetBlipSprite(arcZoneCenterBlip, 161)
        SetBlipDisplay(arcZoneCenterBlip, 4)
        SetBlipScale(arcZoneCenterBlip, 1.0)
        SetBlipColour(arcZoneCenterBlip, blipColor)
        SetBlipAsShortRange(arcZoneCenterBlip, false)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(blipLabel)
        EndTextCommandSetBlipName(arcZoneCenterBlip)
    end
end

local function GetModeBoundaryTexts(modeId)
    if modeId == 'arc_pvp' then
        return "Güvenli sektörün dışına çıktın!", "UYARI: Güvenli sektörün dışına yaklaşıyorsun!"
    end

    return "Savaş alanından çok uzaklaştın!", "UYARI: Sınırdan çıkıyorsun!"
end

local function GetModeSpawnGraceMs(modeId)
    if modeId == 'arc_pvp' then
        return tonumber(Config.ArcPvP and Config.ArcPvP.SpawnProtectionMs or 8000) or 8000
    end

    return tonumber(Config.Combat and Config.Combat.SpawnProtectionMs or 5000) or 5000
end

local function CanUseModeInventory(modeId)
    return modeId == 'arc_pvp' and Config.ArcPvP and Config.ArcPvP.AllowPersonalInventory ~= false
end

local function ShouldBlockInventoryAccess()
    return isSurvivalActive
        and LocalPlayer.state.invOpen
        and not Entity(PlayerPedId()).state.isLooting
        and not CanUseModeInventory(currentModeId)
end

local function CloseInventorySafely()
    pcall(function()
        exports.ox_inventory:closeInventory()
    end)
end

GetModeLabel = function(modeId)
    local gameModes = Config.GameModes or {}
    local modeData = gameModes[modeId] or gameModes.classic
    return (modeData and modeData.label) or "Klasik Hayatta Kalma"
end

local function SpawnArcLootWorld(bucket, deploymentData)
    if not deploymentData then return end

    ClearArcContainers()

    for _, node in ipairs(deploymentData.lootNodes or {}) do
        local nodeCoords = ToVector3(node.coords)
        local nodeType = node.type or 'chest'
        local usesDropModel = nodeType == 'drop' or nodeType == 'death_drop'
        if nodeCoords then
            SpawnArcContainer(
                node.id or ('arc_%s_%s'):format(bucket, math.random(1000, 9999)),
                nodeCoords,
                usesDropModel and (Config.ArcPvP and Config.ArcPvP.DropModel) or (Config.ArcPvP and Config.ArcPvP.ChestModel),
                node.label or (usesDropModel and 'Sinyal Sandığı' or 'Saha Sandığı'),
                tonumber(node.rollCount or (nodeType == 'drop' and 2 or 1)) or 1,
                node.openEvent,
                nodeType == 'death_drop' and 'arc_death_container' or 'arc_container',
                nodeType == 'death_drop'
            )
        end
    end
end

local function IsLobbyLeader()
    return ownsLobby == true
end

local function HasLobby()
    return ownsLobby == true or LocalPlayer.state.inLobby == true
end

GetCharacterName = function(PlayerData)
    local charinfo = PlayerData and PlayerData.charinfo or {}
    local firstName = charinfo.firstname or "Bilinmeyen"
    local lastName = charinfo.lastname or "Operatör"
    return (firstName .. " " .. lastName):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
end

local function GetUpgradeLabel(PlayerData)
    if currentModeId == 'arc_pvp' then
        return "ARC Deposu"
    end

    local survivalMetadata = GetSurvivalMetadata()
    local metadata = PlayerData and PlayerData.metadata or {}
    local ownedUpgrades = {}
    local ownedWeapon = metadata[survivalMetadata.weapon or "survival_weapon"]
    local ownedArmor = tonumber(metadata[survivalMetadata.armor or "survival_armor"] or 0) or 0

    if ownedArmor > 0 then
        table.insert(ownedUpgrades, "Çelik Yelek")
    end

    if ownedWeapon and ownedWeapon ~= "" and ownedWeapon ~= (Config.Combat.DefaultWeapon or "WEAPON_PISTOL") then
        for _, upgradeData in pairs(Config.Upgrades or {}) do
            if upgradeData.metadataName == (survivalMetadata.weapon or "survival_weapon") and tostring(upgradeData.value) == tostring(ownedWeapon) then
                table.insert(ownedUpgrades, upgradeData.label or ownedWeapon)
                break
            end
        end
    end

    if #ownedUpgrades == 0 then
        return "Standart Paket"
    end

    return table.concat(ownedUpgrades, " + ")
end

local function BuildMenuState(userLevel, PlayerData, arcPrepState, arcSummary)
    local gameMode = Config.GameModes and Config.GameModes[currentModeId] or (Config.GameModes and Config.GameModes.classic)
    local lobbyStatus = "Tek Başına"
    arcSummary = arcSummary or {}
    if HasLobby() then
        local visibilityText = currentLobbyPublic == true and "Herkese Açık" or "Özel"
        lobbyStatus = visibilityText .. (IsLobbyLeader() and " Lider" or " Üye")
    end

        return {
        userLevel = userLevel,
        isLeader  = IsLobbyLeader(),
        isMember  = LocalPlayer.state.inLobby == true,
        hasLobby  = HasLobby(),
        isReady   = memberReadyState,
        playerName = GetCharacterName(PlayerData),
        currentStage = userLevel,
        upgradeLabel = GetUpgradeLabel(PlayerData),
        lobbyStatus = lobbyStatus,
        currentModeId = currentModeId,
         currentModeLabel = gameMode and gameMode.label or "Klasik Hayatta Kalma",
         arcMainStacks = arcPrepState and arcPrepState.mainStacks or 0,
         arcMainItems = arcPrepState and arcPrepState.mainItems or 0,
         arcLoadoutStacks = arcPrepState and arcPrepState.loadoutStacks or 0,
         arcLoadoutItems = arcPrepState and arcPrepState.loadoutItems or 0,
         arcLoadoutReady = arcPrepState and arcPrepState.loadoutReady == true or false,
         arcLoadoutState = arcPrepState and arcPrepState.loadoutState or {},
         arcSummary = arcSummary,
         arcExtraction = BuildArcExtractionHudState(),
          allowPersonalInventory = arcSummary.allowPersonalInventory ~= false,
          disconnectPolicy = arcSummary.disconnectPolicy,
          disconnectPolicyLabel = arcSummary.disconnectPolicyLabel,
          disconnectPolicyDescription = arcSummary.disconnectPolicyDescription
    }
end


local function BuildMenuStateCacheKey(menuState)
    if type(menuState) ~= 'table' then
        return ''
    end

    local success, encoded = pcall(json.encode, menuState)
    if success then
        return encoded or ''
    end

    return tostring(menuState.userLevel or '') .. ':' .. tostring(menuState.currentModeId or '') .. ':' .. tostring(menuState.lobbyStatus or '')
end

local function DispatchMenuState(openMenu)
    QBCore.Functions.GetPlayerData(function(PlayerData)
        local survivalMetadata = GetSurvivalMetadata()
        local userLevel = PlayerData.metadata[survivalMetadata.level or "survival_level"] or 1
        QBCore.Functions.TriggerCallback('gs-survival:server:getArcMenuState', function(arcState)
            local arcPrepState = arcState and arcState.prep or {}
            local arcSummary = arcState and arcState.summary or {}
            local menuState = BuildMenuState(userLevel, PlayerData, arcPrepState, arcSummary)
            local nextCacheKey = BuildMenuStateCacheKey(menuState)
            local payload = {
                type = openMenu and 'openMenu' or 'updateMenuState',
                data = menuState
            }

            if openMenu then
                menuStateCacheKey = nextCacheKey
                OpenNUI(payload)
            elseif isMenuOpen and nextCacheKey ~= menuStateCacheKey then
                menuStateCacheKey = nextCacheKey
                SendNUIMessage(payload)
            end
        end)
    end)
end

local function RefreshMainMenu()
    DispatchMenuState(true)
end

local function BuildArcCraftSourceContext(sourceKey)
    if type(sourceKey) ~= 'string' or not Config.ArcPvP then
        return nil
    end

    local PlayerData = QBCore.Functions.GetPlayerData()
    local citizenId = PlayerData and PlayerData.citizenid
    if not citizenId then
        return nil
    end

    if sourceKey == 'arc_loadout' then
        return {
            sourceKey = sourceKey,
            stashId = (Config.ArcPvP.LoadoutStashPrefix or 'arc_loadout_') .. citizenId,
            sourceLabel = Config.ArcPvP.LoadoutStashLabel or "ARC Baskın Çantası",
            helperText = "Baskın çantandaki malzemeleri kullanır ve üretilen eşyayı aynı çantaya koyar."
        }
    elseif sourceKey == 'arc_main' then
        return {
            sourceKey = sourceKey,
            stashId = (Config.ArcPvP.MainStashPrefix or 'arc_main_') .. citizenId,
            sourceLabel = Config.ArcPvP.MainStashLabel or "ARC Ana Depo",
            helperText = "Kalıcı depodaki lootları kullanır ve üretilen eşyayı doğrudan aynı depoya koyar."
        }
    end

    return nil
end

local function OpenArcLockerManager(focusSide)
    QBCore.Functions.TriggerCallback('gs-survival:server:getArcLockerState', function(lockerState)
        if not lockerState then
            NotifyForMode("ARC stash bilgisi alınamadı.", "error", 4000, "ARC Depo")
            return
        end

        OpenNUI({
            type = 'openArcLockers',
            data = lockerState
        })
    end, focusSide == 'loadout' and 'loadout' or 'main')
end

local function HandleReconnectResult(result)
    if not result then
        return
    end

    if result.promptRejoin then
        OpenNUI({
            type = 'openReconnectPrompt',
            data = result
        })
        return
    end

    if result.restored then
        local ped = PlayerPedId()
        CloseNUI()
        FreezeEntityPosition(ped, true)
        isSurvivalActive = false
        DoScreenFadeOut(500)
        Wait(1000)
        SetEntityCoords(ped, Config.Npc.Coords.x, Config.Npc.Coords.y, Config.Npc.Coords.z)
        Wait(3000)
        DoScreenFadeIn(1000)
        FreezeEntityPosition(ped, false)
        local notifyText = result.message or "Eşyaların güvenli bölgede teslim edildi."
        if result.modeId == 'arc_pvp' and result.disconnectPolicyLabel then
            notifyText = ("ARC disconnect policy: %s. %s"):format(result.disconnectPolicyLabel, notifyText)
            if result.extraction and result.extraction.phaseLabel then
                notifyText = notifyText .. (" Son tahliye fazı: %s."):format(result.extraction.phaseLabel)
            end
        end
        if result.modeId == 'arc_pvp' then
            SendArcNotify(notifyText, "success", 10000, "ARC Bağlantı")
        else
            NotifyForMode(notifyText, "success", 10000, "Bağlantı")
        end
        return
    end

    if result.message and result.rejoined ~= true then
        if result.modeId == 'arc_pvp' then
            SendArcNotify(result.message, "primary", 9000, "ARC Bağlantı")
        else
            NotifyForMode(result.message, "primary", 9000, "Bağlantı")
        end
    end
end

-- [NUI CALLBACK]
RegisterNUICallback('nuiAction', function(data, cb)
    local action = data.action

    if action == 'closeMenu' then
        CloseNUI()

    elseif action == 'goBack' then
        RefreshMainMenu()

    elseif action == 'openMarket' then
        TriggerEvent('gs-survival:client:openMarket')

    elseif action == 'openCraft' then
        local requestedSource = data.data and data.data.source
        if requestedSource then
            local craftContext = BuildArcCraftSourceContext(requestedSource)
            if not craftContext then
                NotifyForMode("ARC atölye deposu hazırlanamadı.", "error", 4000, "ARC Atölye")
            else
                TriggerEvent('gs-survival:client:openCraftMenu', craftContext)
            end
        else
            TriggerEvent('gs-survival:client:openCraftMenu')
        end

    elseif action == 'openStages' then
        QBCore.Functions.GetPlayerData(function(PlayerData)
            local survivalMetadata = GetSurvivalMetadata()
            local userLevel = PlayerData.metadata[survivalMetadata.level or "survival_level"] or 1
            TriggerEvent('gs-survival:client:stageMenu', {
                level = userLevel,
                modeId = data.data and data.data.modeId or currentModeId
            })
        end)

    elseif action == 'openArcMainStash' then
        OpenArcLockerManager('main')

    elseif action == 'openArcLoadoutStash' then
        OpenArcLockerManager('loadout')

    elseif action == 'refreshArcLockers' then
        OpenArcLockerManager(data.data and data.data.focusSide)

    elseif action == 'swapArcLockerFocus' then
        OpenArcLockerManager(data.data and data.data.focusSide)

    elseif action == 'moveArcLockerItem' then
        TriggerServerEvent(
            'gs-survival:server:moveArcLockerItem',
            data.data and data.data.fromSide,
            data.data and data.data.slot,
            data.data and data.data.focusSide,
            data.data and data.data.toSide,
            data.data and data.data.targetSlot,
            data.data and data.data.requestedAmount
        )

    elseif action == 'startArcPvP' then
        CloseNUI()
        TriggerEvent('gs-survival:client:startFinal', { modeId = 'arc_pvp' })

    elseif action == 'openInvite' then
        TriggerEvent('gs-survival:client:inviteMenu')

    elseif action == 'createLobby' then
        TriggerEvent('gs-survival:client:createLobby', data.data or {})

    elseif action == 'openActiveLobbies' then
        TriggerEvent('gs-survival:client:viewActiveLobbies')

    elseif action == 'joinPublicLobby' then
        TriggerServerEvent('gs-survival:server:joinPublicLobby', data.data and data.data.leaderId)

    elseif action == 'openMembers' then
        TriggerEvent('gs-survival:client:viewLobbyMembers')

    elseif action == 'toggleReady' then
        TriggerServerEvent('gs-survival:server:toggleReady')

    elseif action == 'craftItem' then
        CloseNUI()
        TriggerEvent('gs-survival:client:craftItem', data.data)

    elseif action == 'buyUpgrade' then
        CloseNUI()
        TriggerServerEvent('gs-survival:server:buyUpgrade', data.data)

    elseif action == 'selectStage' then
        CloseNUI()
        TriggerEvent('gs-survival:client:startFinal', { stageId = data.data.stageId, modeId = data.data.modeId })

    elseif action == 'invitePlayer' then
        TriggerServerEvent('gs-survival:server:sendInvite', data.data.playerId)
        RefreshMainMenu()

    elseif action == 'disbandLobby' then
        CloseNUI()
        TriggerEvent('gs-survival:client:disbandLobby')

    elseif action == 'leaveLobby' then
        CloseNUI()
        TriggerEvent('gs-survival:client:leaveLobby')

    elseif action == 'acceptInvite' then
        CloseNUI()
        TriggerEvent('gs-survival:client:acceptInvite', { leaderId = data.data.leaderId })

    elseif action == 'denyInvite' then
        CloseNUI()
        TriggerEvent('gs-survival:client:denyInvite')

    elseif action == 'arcReconnectDecision' then
        local accepted = data.data and data.data.accepted == true
        QBCore.Functions.TriggerCallback('gs-survival:server:checkReconnectBackup', function(result)
            HandleReconnectResult(result)
        end, accepted and 'rejoin' or 'decline')
    end

    cb({})
end)

RegisterNetEvent('gs-survival:client:openArcLockerManager', function(focusSide)
    OpenArcLockerManager(focusSide)
end)

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

Citizen.CreateThread(function()
    Wait(ARC_DEPLOYMENT_BLIP_INIT_DELAY_MS)
    CreateArcDeploymentZoneBlips()
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
    activeArcSquadPlayers = {}
    LocalPlayer.state:set('inLobby', false, true)
    exports['qb-core']:HideText()
    ClearArcOverlay()
    ApplyMinimapLayout(DEFAULT_MINIMAP_LAYOUT)
    StopSpectating()
    ClearArcZoneBlips()
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

Citizen.CreateThread(function()
    while true do
        if isSurvivalActive and currentModeId == 'classic' then
            -- Yoğunluk baskılamasını sadece klasik dalga modunda tut.
            -- ARC zaten bucket odaklı çalıştığı için burada her frame dünya yoğunluğu bastırmak gereksiz yük oluşturur.
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetPedDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
            SetParkedVehicleDensityMultiplierThisFrame(0.0)
            SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
            Citizen.Wait(0)
        else
            Citizen.Wait(1250)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        if isSurvivalActive and currentModeId == 'classic' and currentWave > 0 and not waitingForWave then
            -- Sadece aktif klasik dalga sırasında dar yarıçaplı araç temizliği uygula.
            -- Ped temizliğini kaldırıyoruz; bu hem pahalı hem de başka senaryolara yan etki üretebiliyor.
            local ped = PlayerPedId()
            if DoesEntityExist(ped) then
                local coords = GetEntityCoords(ped)
                ClearAreaOfVehicles(coords.x, coords.y, coords.z, 80.0, false, false, false, false, false)
            end
        end
        Citizen.Wait(15000) 
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
            local boundaryDistance = activeBoundaryRadius or GetModeBoundaryRadius(currentModeId, stageData)
            local boundaryErrorText, boundaryWarnText = GetModeBoundaryTexts(currentModeId)
            local warningBufferPct = tonumber(Config.Combat and Config.Combat.BoundaryWarningBufferPct or 0.2) or 0.2
            local minWarningBuffer = tonumber(Config.Combat and Config.Combat.MinBoundaryWarningBuffer or 20.0) or 20.0

            local stageCenter = stageData and ToVector3(stageData.center)
            if stageCenter then
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
                    if GetGameTimer() - lastWarningTime > 3000 then
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
                        exports.ox_lib:notify({
                            title = 'Sektör Temizlendi',
                            description = 'Yeni dalga için hazırlan!',
                            type = 'success',
                            position = 'top'
                        })
                        StartWaveCountdown()
                    else
                        isEnding = true
                        exports.ox_lib:notify({
                            title = 'Operasyon Başarılı',
                            description = 'Tüm dalgalar temizlendi! Ganimetleri topla.',
                            type = 'info',
                            position = 'top',
                            duration = 5000
                        })

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
                RefreshArcOverlayInfo('')
            end

            EnsureArcExtractionScene()
        else
            if currentModeId == 'arc_pvp' then
                RefreshArcOverlayInfo('')
            end
            if currentModeId ~= 'arc_pvp' then
                ClearArcExtractionScene()
            end
        end

        Wait(sleep)
    end
end)

-- Menüyü Açan Event
RegisterNetEvent('gs-survival:client:openCraftMenu', function(craftContext)
    local context = type(craftContext) == 'table' and craftContext or {}
    QBCore.Functions.TriggerCallback('gs-survival:server:getCraftMenuData', function(recipes)
        local preparedRecipes = {}

        for _, recipe in ipairs(type(recipes) == 'table' and recipes or {}) do
            preparedRecipes[#preparedRecipes + 1] = {
                header = recipe.header,
                txt = recipe.txt,
                item = recipe.item,
                amount = recipe.amount,
                label = recipe.label,
                requirements = recipe.requirements,
                stashId = context.stashId,
                sourceLabel = context.sourceLabel,
                category = recipe.category,
                ready = recipe.ready,
                maxCraftable = recipe.maxCraftable
            }
        end

        SendNUIMessage({
            type = 'openCraft',
            data = {
                recipes = preparedRecipes,
                sourceKey = context.sourceKey,
                sourceLabel = context.sourceLabel,
                helperText = context.helperText
            }
        })
    end, context.stashId)
end)

RegisterNetEvent('gs-survival:client:refreshCraftMenuCounts', function(craftSide)
    if type(craftSide) ~= 'string' then
        return
    end

    local sourceKeyMap = {
        loadout = 'arc_loadout',
        main = 'arc_main'
    }
    local sourceKey = sourceKeyMap[craftSide]
    if not sourceKey then
        return
    end

    local context = BuildArcCraftSourceContext(sourceKey)
    if context then
        TriggerEvent('gs-survival:client:openCraftMenu', context)
    end
end)
RegisterCommand('survivalcraft', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    
    -- Başlangıç NPC'sinin koordinatlarını baz alıyoruz
    local dist = #(coords - vector3(Config.Npc.Coords.x, Config.Npc.Coords.y, Config.Npc.Coords.z))

    -- Eğer oyuncu NPC'ye 5 metreden yakınsa menü açılır
    if dist < 5.0 then
        TriggerEvent('gs-survival:client:openCraftMenu')
    else
        NotifyForMode("Üretim tezgahını kullanmak için ana kampa gitmelisin!", "error", 4000, "Atölye")
    end
end, false) -- false: Herkes kullanabilir. Sadece admin istiyorsan true yapabilirsin.

-- Alternatif: Sadece test amaçlı, mesafe sınırı olmayan gizli komut
RegisterCommand('scraft_test', function()
    TriggerEvent('gs-survival:client:openCraftMenu')
end, true) -- true: Sadece adminler (ace permissions) kullanabilir

-- Üretim Süreci
RegisterNetEvent('gs-survival:client:craftItem', function(data)
    data = data or {}
    data.multiplier = math.max(math.floor(tonumber(data.multiplier) or 1), 1)
    local notEnoughMessage = data.stashId and "Seçili ARC deposunda yeterli malzeme yok!" or "Yeterli malzemen yok!"
    local progressLabel = data.label .. (data.multiplier > 1 and (" x" .. data.multiplier) or "") .. " Üretiliyor..."

    -- Önce sunucudan malzeme kontrolü yapıyoruz
    QBCore.Functions.TriggerCallback('gs-survival:server:hasCraftMaterials', function(hasMaterials)
        if hasMaterials then
            RunUiProgress({
                title = "Atölye",
                label = progressLabel,
                duration = 5000,
                canCancel = true,
                disable = {
                    disableMovement = true,
                    disableCarMovement = true,
                    disableMouse = false,
                    disableCombat = true,
                },
                anim = {
                    dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@",
                    anim = "machinic_loop_mechandplayer",
                    flags = 16,
                }
            }, function() -- Başarılı
                TriggerServerEvent('gs-survival:server:finishCrafting', data)
            end, function() -- İptal
                NotifyForMode("Üretim iptal edildi.", "error", 3500, "Atölye")
            end)
        else
            NotifyForMode(notEnoughMessage, "error", 4000, "Atölye")
        end
    end, data.item, data.amount, data.multiplier, data.stashId)
end)

local function StartArcBarricadePlacement(data)
    if currentModeId ~= 'arc_pvp' or not isSurvivalActive then
        NotifyForMode("Barricade kit sadece ARC Baskını sırasında kullanılabilir.", "error", 4000, "ARC Barricade")
        return
    end

    if arcBarricadePreview then
        NotifyForMode("Zaten aktif bir barricade yerleştirme işlemi var.", "error", 3500, "ARC Barricade")
        return
    end

    local config = GetArcBarricadeConfig()
    local model = config.Model
    if not model then
        NotifyForMode("Barricade modeli ayarlı değil.", "error", 4000, "ARC Barricade")
        return
    end

    local ped = PlayerPedId()
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end

    local previewCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, tonumber(config.PlaceDistance) or 2.2, 0.0)
    local previewEntity = CreateObjectNoOffset(model, previewCoords.x, previewCoords.y, previewCoords.z, false, false, false)
    SetEntityAsMissionEntity(previewEntity, true, true)
    SetEntityCollision(previewEntity, false, false)
    SetEntityAlpha(previewEntity, math.max(60, math.min(tonumber(config.PreviewAlpha) or 160, 255)), false)
    SetEntityHeading(previewEntity, GetEntityHeading(ped))
    SetModelAsNoLongerNeeded(model)

    arcBarricadePreview = {
        entity = previewEntity,
        slot = data and data.slot or nil,
        heading = GetEntityHeading(ped)
    }

    NotifyForMode("E ile yerleştir, ←/→ ile döndür, BACKSPACE ile iptal et.", "primary", 5000, "ARC Barricade")

    CreateThread(function()
        while arcBarricadePreview and arcBarricadePreview.entity and DoesEntityExist(arcBarricadePreview.entity) do
            Wait(0)

            ped = PlayerPedId()
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)

            if IsDisabledControlJustPressed(0, 174) then
                arcBarricadePreview.heading = arcBarricadePreview.heading + (tonumber(config.RotationStep) or 3.0)
            elseif IsDisabledControlJustPressed(0, 175) then
                arcBarricadePreview.heading = arcBarricadePreview.heading - (tonumber(config.RotationStep) or 3.0)
            end

            local placementCoords, placementHeading = GetArcBarricadePreviewPosition(ped, arcBarricadePreview)
            SetEntityCoordsNoOffset(arcBarricadePreview.entity, placementCoords.x, placementCoords.y, placementCoords.z, false, false, false)
            SetEntityHeading(arcBarricadePreview.entity, placementHeading)
            PlaceObjectOnGroundProperly(arcBarricadePreview.entity)

            if IsDisabledControlJustPressed(0, 177) then
                DeleteEntity(arcBarricadePreview.entity)
                arcBarricadePreview = nil
                NotifyForMode("Barricade yerleştirme iptal edildi.", "error", 3500, "ARC Barricade")
                return
            end

            if IsDisabledControlJustPressed(0, 38) then
                local finalizedCoords = GetEntityCoords(arcBarricadePreview.entity)
                local finalizedHeading = GetEntityHeading(arcBarricadePreview.entity)
                local itemSlot = arcBarricadePreview.slot
                DeleteEntity(arcBarricadePreview.entity)
                arcBarricadePreview = nil

                RunUiProgress({
                    title = "ARC Barricade",
                    label = (config.Label or "ARC Barricade Kit") .. " yerleştiriliyor...",
                    duration = tonumber(config.PlacementDurationMs) or 2500,
                    canCancel = true,
                    disable = {
                        disableMovement = true,
                        disableCarMovement = true,
                        disableMouse = false,
                        disableCombat = true,
                    },
                    anim = {
                        dict = "mini@repair",
                        anim = "fixing_a_ped",
                        flags = 16,
                    }
                }, function()
                    TriggerServerEvent('gs-survival:server:placeArcBarricade', {
                        coords = {
                            x = finalizedCoords.x,
                            y = finalizedCoords.y,
                            z = finalizedCoords.z
                        },
                        heading = finalizedHeading,
                        slot = itemSlot
                    })
                end, function()
                    NotifyForMode("Barricade yerleştirme iptal edildi.", "error", 3500, "ARC Barricade")
                end)
                return
            end
        end
    end)
end

RegisterNetEvent('gs-survival:client:useArcBarricadeKit', function(data)
    StartArcBarricadePlacement(data or {})
end)

RegisterNetEvent('gs-survival:client:spawnArcBarricade', function(data)
    SpawnLocalArcBarricade(data)
end)

RegisterNetEvent('gs-survival:client:syncArcBarricades', function(barricades)
    ClearArcBarricades()

    for _, barricade in ipairs(type(barricades) == 'table' and barricades or {}) do
        SpawnLocalArcBarricade(barricade)
    end
end)

exports('arc_barricade_kit', function(data, slot)
    StartArcBarricadePlacement({
        slot = slot or (type(data) == 'table' and data.slot or nil)
    })
end)

RegisterNetEvent('gs-survival:client:deleteNPC', function(netId)

    local entity = NetToPed(netId)

   

    -- Eğer bu NPC'ye bağlı bir blip varsa önce onu sil

    if DoesEntityExist(entity) then

        local blip = GetBlipFromEntity(entity)

        if DoesBlipExist(blip) then

            RemoveBlip(blip)

        end

       

        -- NPC'yi sil

        DeleteEntity(entity)

    end

end)


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
    CloseNUI()
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
    CloseNUI()
    currentModeId = 'arc_pvp'
    ClearArcBarricades()
    ApplyMinimapLayout(DEFAULT_MINIMAP_LAYOUT)
    arcOverlayInfoVisible = false
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
    RefreshArcOverlayInfo('', true)
    ShowScreenTransition(SCREEN_TRANSITION_ENTER_TITLE)
    Wait(100)
    DoScreenFadeOut(SCREEN_TRANSITION_FADE_DURATION_MS)
    Wait(SCREEN_TRANSITION_FADE_DURATION_MS + 100)

    if DoesEntityExist(startPed) then
        SetEntityVisible(startPed, false, false)
        SetEntityCoords(startPed, Config.Npc.Coords.x, Config.Npc.Coords.y, Config.Npc.Coords.z - 100.0)
    end

    SetEntityCoords(PlayerPedId(), spawnPoint.x, spawnPoint.y, spawnPoint.z)

    ClearArcZoneBlips()
    HideNonArcBlips()
    CreateArcZoneBlips(activeArcDeployment)
    SpawnArcLootWorld(bucket, activeArcDeployment)
    RefreshArcSessionVehicleBlips()
    RefreshArcFriendlyBlips()
    RefreshArcOverlayTeam()
    RefreshArcOverlayInfo('', true)
    TriggerServerEvent('gs-survival:server:requestArcBarricadeSync')
    Wait(tonumber(Config.ArcPvP and Config.ArcPvP.DeploymentNotifyDelay or 1200) or 1200)
    Wait(math.max(0, SCREEN_TRANSITION_BLACK_HOLD_MS - (tonumber(Config.ArcPvP and Config.ArcPvP.DeploymentNotifyDelay or 1200) or 1200)))
    DoScreenFadeIn(SCREEN_TRANSITION_FADE_DURATION_MS)
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

CreateThread(function()
    while resourceRunning do
        if currentModeId == 'arc_pvp' and isSurvivalActive then
            DisableControlAction(0, 37, true)
            if IsDisabledControlJustPressed(0, 37) then
                arcOverlayInfoVisible = not arcOverlayInfoVisible
                PushArcOverlayState({
                    enabled = true,
                    showInfo = arcOverlayInfoVisible == true
                }, true)
            end
            Wait(0)
        else
            Wait(250)
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

-- [MENÜLER VE DAVET SİSTEMİ]
RegisterNetEvent('gs-survival:client:openMenu', function()
    DispatchMenuState(true)
end)

RegisterNetEvent('gs-survival:client:refreshMenuState', function()
    DispatchMenuState(false)
end)

-- Üyenin lideri tanıması için davet kabul eventini güncelle


-- Lobi Üyelerini Gösterme (Senkronize)


-- [LOBİ ÜYELERİ LİSTESİ]
RegisterNetEvent('gs-survival:client:viewLobbyMembers', function()
    local leaderId = IsLobbyLeader() and GetPlayerServerId(PlayerId()) or lobbyLeaderId

    QBCore.Functions.TriggerCallback('gs-survival:server:getLobbyMembers', function(members)
        SendNUIMessage({ type = 'openMembers', data = { members = members or {}, leaderId = leaderId } })
    end, leaderId)
end)

RegisterNetEvent('gs-survival:client:viewActiveLobbies', function()
    QBCore.Functions.TriggerCallback('gs-survival:server:getActiveLobbies', function(lobbies)
        SendNUIMessage({ type = 'openActiveLobbies', data = { lobbies = lobbies or {} } })
    end)
end)

RegisterNetEvent('gs-survival:client:createLobby', function(data)
    if HasLobby() then
        NotifyForMode("Zaten aktif bir lobi bağlantın var.", "error", 3500, "Lobi")
        return
    end

    TriggerServerEvent('gs-survival:server:createLobby', data and data.isPublic == true)
end)

RegisterNetEvent('gs-survival:client:lobbyCreated', function(data)
    ownsLobby = true
    pendingInviteLeaderId = nil
    memberReadyState = false
    currentLobbyPublic = data and data.isPublic == true
    NotifyForMode((currentLobbyPublic and "Herkese açık" or "Özel") .. " lobi kuruldu! Artık oyuncu davet edebilirsin.", "success", 4500, "Lobi")
    RefreshMainMenu()
end)



-- Lobiden Ayrılma Butonu Eventi
RegisterNetEvent('gs-survival:client:leaveLobby', function()
    TriggerServerEvent('gs-survival:server:leaveLobby', lobbyLeaderId)
    LocalPlayer.state:set('inLobby', false, true)
    lobbyLeaderId = nil
    pendingInviteLeaderId = nil
    memberReadyState = false
    currentLobbyPublic = nil
    NotifyForMode("Lobiden ayrıldın.", "error", 3500, "Lobi")
end)

-- Lider tarafından lobiyi dağıttığında üyelere gönderilen event
RegisterNetEvent('gs-survival:client:forceLeaveLobby', function()
    LocalPlayer.state:set('inLobby', false, true)
    lobbyLeaderId = nil
    pendingInviteLeaderId = nil
    memberReadyState = false
    currentLobbyPublic = nil
    NotifyForMode("Lider lobiyi dağıttı.", "error", 4000, "Lobi")
end)

-- Lobi Dağıtma Butonu Eventi
RegisterNetEvent('gs-survival:client:disbandLobby', function()
    TriggerServerEvent('gs-survival:server:disbandLobby')
    ownsLobby = false
    invitedPlayers = {}
    pendingInviteLeaderId = nil
    currentLobbyPublic = nil
    NotifyForMode("Lobi dağıtıldı.", "error", 3500, "Lobi")
end)

-- [STAGE MENÜLERİ]
RegisterNetEvent('gs-survival:client:stageMenu', function(data)
    local userLevel = data.level
    currentModeId = data.modeId or currentModeId or 'classic'
    local gameMode = Config.GameModes and Config.GameModes[currentModeId] or Config.GameModes.classic
    local stages = {}
    if currentModeId == 'arc_pvp' then
        stages[1] = {
            id = 1,
            label = gameMode and gameMode.label or "ARC Baskını",
            multiplier = 1.0,
            locked = false
        }
    else
        for stageId, stageData in ipairs(GetModeStages(currentModeId)) do
            table.insert(stages, {
                id         = stageId,
                label      = stageData.label or ("Bölüm " .. stageId),
                multiplier = stageData.multiplier or 1.0,
                locked     = stageId > userLevel
            })
        end
    end
    SendNUIMessage({
        type = 'openStages',
        data = {
            stages = stages,
            userLevel = userLevel,
            modeId = currentModeId,
            modeLabel = gameMode and gameMode.label or "Klasik Hayatta Kalma"
        }
    })
end)

-- [DAVET MENÜSÜ]
RegisterNetEvent('gs-survival:client:inviteMenu', function()
    if not IsLobbyLeader() then
        NotifyForMode("Önce bir lobi kurmalısın.", "error", 3500, "Lobi")
        return
    end

    if #invitedPlayers >= MAX_LOBBY_MEMBERS then 
        NotifyForMode("Lobi zaten dolu! (Maksimum " .. MAX_LOBBY_SIZE .. " kişi)", "error", 3500, "Lobi")
        return 
    end

    QBCore.Functions.TriggerCallback('gs-survival:server:getNearbyPlayers', function(nearbyPlayers)
        local list = {}
        if nearbyPlayers then
            for _, v in pairs(nearbyPlayers) do
                if v.id ~= GetPlayerServerId(PlayerId()) then
                    table.insert(list, { id = v.id, name = v.name })
                end
            end
        end
        SendNUIMessage({ type = 'openInvite', data = { players = list } })
    end)
end)

RegisterNetEvent('gs-survival:client:receiveInvite', function(leaderId)
    pendingInviteLeaderId = tonumber(leaderId)
    OpenNUI({ type = 'receiveInvite', data = { leaderId = leaderId } })
end)

RegisterNetEvent('gs-survival:client:acceptInvite', function(data)
    pendingInviteLeaderId = nil
    TriggerServerEvent('gs-survival:server:confirmInvite', data.leaderId)
end)

RegisterNetEvent('gs-survival:client:joinedLobby', function(data)
    lobbyLeaderId = data.leaderId
    pendingInviteLeaderId = nil
    memberReadyState = false
    currentLobbyPublic = data.isPublic == true
    LocalPlayer.state:set('inLobby', true, true)
    NotifyForMode("Lobiye katıldın!", "success", 3500, "Lobi")
    RefreshMainMenu()
end)

RegisterNetEvent('gs-survival:client:setReadyState', function(isReady)
    memberReadyState = isReady == true
    DispatchMenuState(false)
end)

RegisterNetEvent('gs-survival:client:syncLobbyMembers', function(leaderId, members)
    SendNUIMessage({
        type = 'syncLobbyMembers',
        data = {
            leaderId = leaderId,
            members = members or {}
        }
    })
end)

RegisterNetEvent('gs-survival:client:denyInvite', function()
    if pendingInviteLeaderId then
        TriggerServerEvent('gs-survival:server:denyInvite', pendingInviteLeaderId)
    end
    pendingInviteLeaderId = nil
    NotifyForMode("Daveti reddettin.", "error", 3000, "Lobi")
end)

RegisterNetEvent('gs-survival:client:addInvited', function(playerId)
    local alreadyIn = false
    for _, id in pairs(invitedPlayers) do
        if id == playerId then alreadyIn = true break end
    end

    if not alreadyIn then
        table.insert(invitedPlayers, playerId)
        NotifyForMode("Yeni bir savaşçı lobiye katıldı!", "success", 3500, "Lobi")
    else
        NotifyForMode("Zaten bir lobide!", "error", 3500, "Lobi")
    end
end)

-- [SURVIVAL BAŞLATMA]
RegisterNetEvent('gs-survival:client:startFinal', function(data)
    if LocalPlayer.state.inLobby == true and not IsLobbyLeader() then
        NotifyForMode("Operasyonu yalnızca lobi lideri başlatabilir.", "error", 3500, "Lobi")
        return
    end

    local selectedMode = data and data.modeId or currentModeId or 'classic'
    local selectedStage = data and data.stageId
    if not selectedStage and selectedMode ~= 'arc_pvp' then
        selectedStage = 1
    end

    activeStageId = selectedStage or activeStageId or 1
    currentModeId = selectedMode
    local lobbyMembers = ownsLobby == true and invitedPlayers or nil
    if selectedMode == 'arc_pvp' then
        TriggerServerEvent('gs-survival:server:startArcPvP', lobbyMembers)
    else
        TriggerServerEvent('gs-survival:server:startSurvival', lobbyMembers, selectedStage, selectedMode)
    end
end)
