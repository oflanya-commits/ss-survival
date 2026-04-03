local QBCore = exports['qb-core']:GetCoreObject()
local MAX_LOBBY_SIZE = 4
local MAX_LOBBY_MEMBERS = MAX_LOBBY_SIZE - 1
local ARC_EXTRACTION_HELI = {
    SPAWN_OFFSET = vector3(110.0, -70.0, 18.0),
    MIN_SPEED = 4.0,
    MAX_SPEED = 25.0,
    HOVER_SPEED = 6.0,
    RADIUS = 8.0,
    SLOW_DIST = 20.0,
    MISSION_TYPE = 4,
    MISSION_FLAGS = 0
}
local SCREEN_TRANSITION = {
    FADE_DURATION_MS = 600,
    BLACK_HOLD_MS = 3400,
    LABEL = 'OTURUM GEÇİŞİ',
    ENTER_TITLE = "SESSION'A GİRİLİYOR",
    RETURN_TITLE = 'LOBİYE DÖNÜLÜYOR'
}
SCREEN_TRANSITION.TOTAL_DURATION_MS = (SCREEN_TRANSITION.FADE_DURATION_MS * 2) + SCREEN_TRANSITION.BLACK_HOLD_MS
local UI_PROGRESS = {
    CANCEL_CONTROLS = { 177, 200, 202 },
    MIN_DURATION_MS = 250,
    MAX_DURATION_MS = 60000,
    DEFAULT_TITLE = 'İşlem Sürüyor',
    DEFAULT_LABEL = 'İşlem sürüyor...'
}
local ARC_OVERLAY = {
    EMPTY_PROMPT = ''
}
local nextUiProgressId = 0
local activeUiProgress = nil
local currentWave, isSurvivalActive, myBucket = 0, false, 0
local activeStageId = 1
local currentModeId = 'classic'
local spawnedPeds, invitedPlayers = {}, {}
local waitingForWave, countdown = false, 0
local notifiedDeath = false
local isEnding = false
local activeSurvivalPlayers = {}
local activeArcRaidPlayers = {}
local activeArcAlivePlayers = {}
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
local arcOverlaySessionVisible = false
local menuStateCacheKey = nil
local isMenuOpen = false
local menuPreviewCam = nil
local menuPreviewState = nil
local menuPreviewPeds = {}
local menuPreviewStarting = false
local MENU_PREVIEW_SETTINGS = type(Config.MenuPreview) == 'table' and Config.MenuPreview or {}
local DEFAULT_MENU_PREVIEW_COORDS = vector4(2386.85, 3063.76, 48.15, 270.0)
local DEFAULT_MENU_PREVIEW_CAM_OFFSET = { forward = 4.15, right = 0.0, up = 1.05 }
local DEFAULT_MENU_PREVIEW_LOOK_AT_OFFSET = { forward = 0.0, right = 0.0, up = 0.78 }
local DEFAULT_MENU_PREVIEW_FOV = 28.0
local MENU_PREVIEW_NAME_LABEL = {
    MIN_WIDTH = 0.055,
    MAX_WIDTH = 0.16,
    WIDTH_PER_CHAR = 0.0032,
    BASE_WIDTH = 0.016,
    DRAW_INTERVAL_MS = 0,
    HEAD_BONE = 0x796E,
    LOCAL_OFFSET_Z = 0.35,
    MEMBER_OFFSET_Z = 0.3,
    BG_COLOR = { 6, 8, 12, 150 },
    TEXT_SCALE_HIGHLIGHT = 0.34,
    TEXT_SCALE_NORMAL = 0.31,
    COLOR_HIGHLIGHT = { 255, 232, 164, 255 },
    COLOR_NORMAL = { 255, 255, 255, 235 }
}
local DEFAULT_MENU_PREVIEW_MEMBER_OFFSETS = {
    { forward = 0.0, right = -1.35, up = 0.0 },
    { forward = 0.0, right = 1.35, up = 0.0 },
    { forward = 0.0, right = 2.7, up = 0.0 }
}

local function NormalizeMenuPreviewOffset(offset, fallback)
    local safeFallback = fallback or {}
    if type(offset) ~= 'table' then
        return {
            forward = tonumber(safeFallback.forward) or 0.0,
            right = tonumber(safeFallback.right) or 0.0,
            up = tonumber(safeFallback.up) or 0.0
        }
    end

    return {
        forward = tonumber(offset.forward) or tonumber(safeFallback.forward) or 0.0,
        right = tonumber(offset.right) or tonumber(safeFallback.right) or 0.0,
        up = tonumber(offset.up) or tonumber(safeFallback.up) or 0.0
    }
end

local function NormalizeMenuPreviewOffsets(offsets, fallback)
    local normalized = {}

    if type(offsets) == 'table' then
        for index, offset in ipairs(offsets) do
            normalized[#normalized + 1] = NormalizeMenuPreviewOffset(offset, fallback[index])
        end
    end

    if #normalized == 0 then
        for index, offset in ipairs(fallback) do
            normalized[#normalized + 1] = NormalizeMenuPreviewOffset(offset, offset)
        end
    end

    return normalized
end

local function NormalizeMenuPreviewPoint(coords)
    if type(coords) ~= 'table' or coords.x == nil or coords.y == nil or coords.z == nil then
        return nil
    end

    return vector3(
        tonumber(coords.x) or 0.0,
        tonumber(coords.y) or 0.0,
        tonumber(coords.z) or 0.0
    )
end

local MENU_PREVIEW_COORDS = MENU_PREVIEW_SETTINGS.Coords or DEFAULT_MENU_PREVIEW_COORDS
local MENU_PREVIEW_CAM_COORDS = NormalizeMenuPreviewPoint(MENU_PREVIEW_SETTINGS.CameraCoords)
local MENU_PREVIEW_CAM_OFFSET = NormalizeMenuPreviewOffset(MENU_PREVIEW_SETTINGS.CameraOffset, DEFAULT_MENU_PREVIEW_CAM_OFFSET)
local MENU_PREVIEW_LOOK_AT_COORDS = NormalizeMenuPreviewPoint(MENU_PREVIEW_SETTINGS.LookAtCoords)
local MENU_PREVIEW_LOOK_AT_OFFSET = NormalizeMenuPreviewOffset(MENU_PREVIEW_SETTINGS.LookAtOffset, DEFAULT_MENU_PREVIEW_LOOK_AT_OFFSET)
local MENU_PREVIEW_FOV = tonumber(MENU_PREVIEW_SETTINGS.Fov) or DEFAULT_MENU_PREVIEW_FOV
local MENU_PREVIEW_MEMBER_OFFSETS = NormalizeMenuPreviewOffsets(MENU_PREVIEW_SETTINGS.MemberOffsets, DEFAULT_MENU_PREVIEW_MEMBER_OFFSETS)
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
local ToVector3
local StartMenuPreview
local StopMenuPreview
local CanStartMenuPreview

-- [NUI YARDIMCI FONKSİYONLAR]
local function OpenNUI(data, options)
    local wasOpen = isMenuOpen == true
    local keepScene = type(options) == 'table' and options.keepScene == true
    isMenuOpen = true

    if keepScene and wasOpen then
        SendNUIMessage(data)
        SetNuiFocus(true, true)
        return
    end

    StartMenuPreview(data, function()
        SendNUIMessage(data)
        SetNuiFocus(true, true)
    end)
end

local function CloseNUI()
    isMenuOpen = false
    SendNUIMessage({ type = 'closeMenu' })
    SetNuiFocus(false, false)
    StopMenuPreview()
end

local function OffsetCoordsFromHeading(baseCoords, heading, forward, right, up)
    -- Heading tabanlı world offset üretir:
    -- forward pedin baktığı yön boyunca, right pedin sağına doğru, up ise Z ekseninde uygulanır.
    local radians = math.rad(heading or 0.0)
    local sinValue = math.sin(radians)
    local cosValue = math.cos(radians)

    return vector3(
        baseCoords.x + (forward * sinValue) + (right * cosValue),
        baseCoords.y + (forward * cosValue) - (right * sinValue),
        baseCoords.z + (up or 0.0)
    )
end

local function ClearMenuPreviewPeds()
    for _, previewEntry in ipairs(menuPreviewPeds) do
        local ped = type(previewEntry) == 'table' and previewEntry.ped or previewEntry
        if ped and DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end
    menuPreviewPeds = {}
end

local function CaptureMenuPreviewAppearance(serverId)
    local targetServerId = tonumber(serverId)
    if not targetServerId then
        return nil
    end

    local playerIndex = GetPlayerFromServerId(targetServerId)
    if playerIndex < 0 then
        return nil
    end

    local sourcePed = GetPlayerPed(playerIndex)

    if not sourcePed or sourcePed == 0 or not DoesEntityExist(sourcePed) then
        return nil
    end

    local appearance = {
        model = GetEntityModel(sourcePed),
        components = {},
        props = {}
    }

    for componentId = 0, 11 do
        appearance.components[#appearance.components + 1] = {
            componentId = componentId,
            drawable = GetPedDrawableVariation(sourcePed, componentId),
            texture = GetPedTextureVariation(sourcePed, componentId),
            palette = GetPedPaletteVariation(sourcePed, componentId)
        }
    end

    for propId = 0, 7 do
        appearance.props[#appearance.props + 1] = {
            propId = propId,
            index = GetPedPropIndex(sourcePed, propId),
            texture = GetPedPropTextureIndex(sourcePed, propId)
        }
    end

    return appearance
end

local function ApplyMenuPreviewAppearance(targetPed, appearance)
    if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) or type(appearance) ~= 'table' then
        return
    end

    for _, component in ipairs(appearance.components or {}) do
        SetPedComponentVariation(
            targetPed,
            component.componentId or 0,
            component.drawable or 0,
            component.texture or 0,
            component.palette or 0
        )
    end

    for _, prop in ipairs(appearance.props or {}) do
        if (prop.index or -1) >= 0 then
            SetPedPropIndex(targetPed, prop.propId or 0, prop.index or 0, prop.texture or 0, true)
        else
            ClearPedProp(targetPed, prop.propId or 0)
        end
    end
end

local function BuildMenuPreviewLineup(lobbyMembers)
    local myServerId = GetPlayerServerId(PlayerId())
    local lineup = {}

    for _, member in ipairs(type(lobbyMembers) == 'table' and lobbyMembers or {}) do
        if tonumber(member.id) ~= tonumber(myServerId) then
            if #lineup >= #MENU_PREVIEW_MEMBER_OFFSETS then
                break
            end

            local appearance = CaptureMenuPreviewAppearance(member.id)
            if appearance then
                lineup[#lineup + 1] = {
                    appearance = appearance,
                    name = member.name or string.format("Oyuncu #%s", member.id or '?')
                }
            end
        end
    end

    return lineup
end

local function SpawnMenuPreviewPeds(baseCoords, heading, lineup)
    ClearMenuPreviewPeds()

    for index, previewEntry in ipairs(lineup or {}) do
        local appearance = type(previewEntry) == 'table' and previewEntry.appearance or previewEntry
        local offset = MENU_PREVIEW_MEMBER_OFFSETS[index]
        if offset and appearance and appearance.model then
            RequestModel(appearance.model)
            while not HasModelLoaded(appearance.model) do
                Wait(0)
            end

            local pedCoords = OffsetCoordsFromHeading(baseCoords, heading, offset.forward or 0.0, offset.right or 0.0, offset.up or 0.0)
            local previewPed = CreatePed(4, appearance.model, pedCoords.x, pedCoords.y, pedCoords.z, heading, false, true)
            SetEntityAsMissionEntity(previewPed, true, true)
            SetEntityInvincible(previewPed, true)
            FreezeEntityPosition(previewPed, true)
            SetBlockingOfNonTemporaryEvents(previewPed, true)
            ClearPedTasksImmediately(previewPed)
            TaskStandStill(previewPed, -1)
            ApplyMenuPreviewAppearance(previewPed, appearance)
            menuPreviewPeds[#menuPreviewPeds + 1] = {
                ped = previewPed,
                name = type(previewEntry) == 'table' and previewEntry.name or nil
            }
            SetModelAsNoLongerNeeded(appearance.model)
        end
    end
end

local function DrawMenuPreviewNameLabel(coords, label, highlight)
    if not coords or not label or label == '' then
        return
    end

    local text = tostring(label)
    local width = math.min(
        MENU_PREVIEW_NAME_LABEL.MAX_WIDTH,
        math.max(MENU_PREVIEW_NAME_LABEL.MIN_WIDTH, (#text * MENU_PREVIEW_NAME_LABEL.WIDTH_PER_CHAR) + MENU_PREVIEW_NAME_LABEL.BASE_WIDTH)
    )
    local textY = -0.004
    local rectY = 0.014

    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    DrawRect(0.0, rectY, width, 0.03, table.unpack(MENU_PREVIEW_NAME_LABEL.BG_COLOR))
    SetTextScale(0.0, highlight and MENU_PREVIEW_NAME_LABEL.TEXT_SCALE_HIGHLIGHT or MENU_PREVIEW_NAME_LABEL.TEXT_SCALE_NORMAL)
    SetTextFont(0)
    SetTextProportional(true)
    SetTextCentre(true)
    SetTextDropshadow(1, 0, 0, 0, 180)
    SetTextOutline()
    if highlight then
        SetTextColour(table.unpack(MENU_PREVIEW_NAME_LABEL.COLOR_HIGHLIGHT))
    else
        SetTextColour(table.unpack(MENU_PREVIEW_NAME_LABEL.COLOR_NORMAL))
    end
    BeginTextCommandDisplayText('STRING')
    AddTextComponentString(text)
    EndTextCommandDisplayText(0.0, textY)
    ClearDrawOrigin()
end

CreateThread(function()
    while true do
        if isMenuOpen and menuPreviewState then
            local localPed = PlayerPedId()
            if localPed and DoesEntityExist(localPed) and not IsPedFatallyInjured(localPed) then
                DrawMenuPreviewNameLabel(
                    GetPedBoneCoords(localPed, MENU_PREVIEW_NAME_LABEL.HEAD_BONE, 0.0, 0.0, MENU_PREVIEW_NAME_LABEL.LOCAL_OFFSET_Z),
                    menuPreviewState.playerName,
                    true
                )
            end

            for _, previewEntry in ipairs(menuPreviewPeds) do
                local ped = type(previewEntry) == 'table' and previewEntry.ped or previewEntry
                local label = type(previewEntry) == 'table' and previewEntry.name or nil
                if ped and label and DoesEntityExist(ped) and not IsPedFatallyInjured(ped) then
                    local labelCoords = GetPedBoneCoords(ped, MENU_PREVIEW_NAME_LABEL.HEAD_BONE, 0.0, 0.0, MENU_PREVIEW_NAME_LABEL.MEMBER_OFFSET_Z)
                    DrawMenuPreviewNameLabel(labelCoords, label, false)
                end
            end

            Wait(MENU_PREVIEW_NAME_LABEL.DRAW_INTERVAL_MS)
        else
            Wait(500)
        end
    end
end)

StartMenuPreview = function(menuPayload, onReady)
    if not CanStartMenuPreview() then
        if onReady then
            onReady()
        end
        return
    end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        if onReady then
            onReady()
        end
        return
    end

    menuPreviewStarting = true
    local previewCoords = vector3(MENU_PREVIEW_COORDS.x, MENU_PREVIEW_COORDS.y, MENU_PREVIEW_COORDS.z)
    local previewHeading = tonumber(MENU_PREVIEW_COORDS.w) or 0.0
    local camCoords = MENU_PREVIEW_CAM_COORDS
        or OffsetCoordsFromHeading(
            previewCoords,
            previewHeading,
            MENU_PREVIEW_CAM_OFFSET.forward or 0.0,
            MENU_PREVIEW_CAM_OFFSET.right or 0.0,
            MENU_PREVIEW_CAM_OFFSET.up or 0.0
        )
    local lookAtCoords = MENU_PREVIEW_LOOK_AT_COORDS
        or OffsetCoordsFromHeading(
            previewCoords,
            previewHeading,
            MENU_PREVIEW_LOOK_AT_OFFSET.forward or 0.0,
            MENU_PREVIEW_LOOK_AT_OFFSET.right or 0.0,
            MENU_PREVIEW_LOOK_AT_OFFSET.up or 0.0
        )
    local menuPayloadData = type(menuPayload) == 'table' and type(menuPayload.data) == 'table' and menuPayload.data or nil
    local lineup = BuildMenuPreviewLineup(menuPayloadData and menuPayloadData.lobbyMembers)
    menuPreviewState = {
        coords = GetEntityCoords(ped),
        heading = GetEntityHeading(ped),
        wasFrozen = IsEntityPositionFrozen(ped),
        playerName = menuPayloadData and tostring(menuPayloadData.playerName or '') or nil
    }

    QBCore.Functions.TriggerCallback('gs-survival:server:enterMenuPreview', function(result)
        menuPreviewStarting = false
        if not menuPreviewState then
            if onReady then
                onReady()
            end
            return
        end

        menuPreviewState.originalBucket = result and result.originalBucket or 0
        menuPreviewState.previewBucket = result and result.bucketId or 0

        DoScreenFadeOut(250)
        while not IsScreenFadedOut() do
            Wait(0)
        end

        RequestCollisionAtCoord(previewCoords.x, previewCoords.y, previewCoords.z)
        SetFocusPosAndVel(previewCoords.x, previewCoords.y, previewCoords.z, 0.0, 0.0, 0.0)
        SetEntityCoords(ped, previewCoords.x, previewCoords.y, previewCoords.z, false, false, false, false)
        SetEntityHeading(ped, previewHeading)
        ClearPedTasksImmediately(ped)
        TaskStandStill(ped, -1)
        FreezeEntityPosition(ped, true)

        SpawnMenuPreviewPeds(previewCoords, previewHeading, lineup)

        if not menuPreviewCam then
            menuPreviewCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        end

        SetCamCoord(menuPreviewCam, camCoords.x, camCoords.y, camCoords.z)
        PointCamAtCoord(menuPreviewCam, lookAtCoords.x, lookAtCoords.y, lookAtCoords.z)
        SetCamFov(menuPreviewCam, MENU_PREVIEW_FOV)
        RenderScriptCams(true, false, 0, true, true)
        DoScreenFadeIn(250)

        if onReady then
            onReady()
        end
    end)
end

StopMenuPreview = function()
    ClearMenuPreviewPeds()

    if menuPreviewCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(menuPreviewCam, true)
        menuPreviewCam = nil
    end

    if not menuPreviewState then
        return
    end

    local previewState = menuPreviewState
    local ped = PlayerPedId()
    menuPreviewState = nil

    if ped and ped ~= 0 and DoesEntityExist(ped) then
        DoScreenFadeOut(250)
        while not IsScreenFadedOut() do
            Wait(0)
        end
    end

    QBCore.Functions.TriggerCallback('gs-survival:server:exitMenuPreview', function()
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            ClearPedTasksImmediately(ped)
            ClearFocus()
            SetEntityCoords(ped, previewState.coords.x, previewState.coords.y, previewState.coords.z, false, false, false, false)
            SetEntityHeading(ped, previewState.heading)
            FreezeEntityPosition(ped, previewState.wasFrozen == true)
        end

        DoScreenFadeIn(250)
    end, previewState.originalBucket or 0)
end

CanStartMenuPreview = function()
    return menuPreviewState == nil
        and menuPreviewStarting ~= true
        and isSurvivalActive ~= true
        and Config.MenuPreview ~= nil
        and Config.MenuPreview.Coords ~= nil
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
            duration = duration or 7000
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
            label = label or SCREEN_TRANSITION.LABEL,
            duration = duration or SCREEN_TRANSITION.TOTAL_DURATION_MS,
            transition = options.transition == true
        }
    })
end

local function ShowScreenTransition(title)
    ShowArcResultBanner(title, SCREEN_TRANSITION.LABEL, SCREEN_TRANSITION.TOTAL_DURATION_MS, {
        transition = true
    })
end

local function NotifyForMode(message, notifyType, duration, title)
    SendArcNotify(message, notifyType, duration, GetNotifyTitle(notifyType, title))
end

RegisterNetEvent('gs-survival:client:notify', function(notifyData)
    if type(notifyData) ~= 'table' then
        return
    end

    local message = notifyData.message
    if not message or message == '' then
        return
    end

    NotifyForMode(message, notifyData.type or 'primary', notifyData.duration, notifyData.title)
end)

local function ShowArcBarricadePlacementUi()
    SendNUIMessage({
        type = 'showArcBarricadePlacement',
        data = {
            title = 'ARC Barricade Kit',
            controls = {
                { key = 'SOL TIK', action = 'Yerleştir' },
                { key = 'Q / E', action = 'Döndür' },
                { key = 'BACKSPACE', action = 'İptal' }
            }
        }
    })
end

local function HideArcBarricadePlacementUi()
    SendNUIMessage({ type = 'hideArcBarricadePlacement' })
end

local function HideUiProgress()
    SendNUIMessage({ type = 'hideArcProgress' })
end

local function FinalizeUiProgress(progressId, wasCancelled)
    local progressState = activeUiProgress
    if not progressState or progressState.id ~= progressId or progressState.finished then
        return false
    end

    progressState.finished = true
    activeUiProgress = nil
    HideUiProgress()

    if progressState.anim.dict and progressState.anim.anim then
        StopAnimTask(progressState.ped, progressState.anim.dict, progressState.anim.anim, 1.0)
    end

    if wasCancelled then
        if progressState.onCancel then
            progressState.onCancel()
        end
    elseif progressState.onComplete then
        progressState.onComplete()
    end

    return true
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
    duration = math.max(UI_PROGRESS.MIN_DURATION_MS, math.min(duration, UI_PROGRESS.MAX_DURATION_MS))

    local ped = PlayerPedId()
    local disable = options.disable or {}
    local anim = options.anim or {}
    local canCancel = options.canCancel ~= false
    local endsAt = GetGameTimer() + duration
    nextUiProgressId = nextUiProgressId + 1
    local progressId = nextUiProgressId

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
            id = progressId,
            title = options.title or UI_PROGRESS.DEFAULT_TITLE,
            label = options.label or UI_PROGRESS.DEFAULT_LABEL,
            duration = duration,
            canCancel = canCancel
        }
    })

    activeUiProgress = {
        id = progressId,
        ped = ped,
        anim = anim,
        onComplete = onComplete,
        onCancel = onCancel,
        finished = false
    }

    CreateThread(function()
        while activeUiProgress and activeUiProgress.id == progressId and activeUiProgress.finished ~= true do
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
                for _, controlId in ipairs(UI_PROGRESS.CANCEL_CONTROLS) do
                    if IsControlJustPressed(0, controlId) then
                        cancelRequested = true
                        break
                    end
                end
            end

            if cancelRequested then
                FinalizeUiProgress(progressId, true)
            elseif GetGameTimer() >= endsAt then
                FinalizeUiProgress(progressId, false)
            end
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
    local aliveLookup = {}

    if currentModeId == 'arc_pvp' then
        for _, playerId in ipairs(activeArcAlivePlayers or {}) do
            aliveLookup[tonumber(playerId)] = true
        end
    end

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
            local playerAlive = currentModeId == 'arc_pvp' and aliveLookup[serverId] or false
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
    arcOverlaySessionVisible = false
    SendNUIMessage({ type = 'clearArcHud' })
end

local function IsArcOverlayVisible()
    return isSurvivalActive == true and arcOverlaySessionVisible == true
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
    local shouldShowOverlay = IsArcOverlayVisible()
    PushArcOverlayState({
        enabled = shouldShowOverlay,
        showInfo = shouldShowOverlay,
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

    local trackedPlayers = activeArcAlivePlayers or {}
    local localServerId = tonumber(GetPlayerServerId(PlayerId()))
    local localTracked = false

    for _, id in ipairs(trackedPlayers) do
        local playerId = tonumber(id)
        if playerId ~= nil then
            local playerIndex = GetPlayerFromServerId(playerId)
            local targetPed = playerIndex ~= -1 and GetPlayerPed(playerIndex) or 0
            local isAlive = true
            if playerIndex ~= -1 and NetworkIsPlayerActive(playerIndex) then
                isAlive = DoesEntityExist(targetPed) and not IsPedFatallyInjured(targetPed)
            end

            if isAlive then
                aliveCount = aliveCount + 1
            end
            if not localTracked and playerId == localServerId then
                localTracked = true
            end
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

    local shouldShowOverlay = IsArcOverlayVisible()
    PushArcOverlayState({
        enabled = shouldShowOverlay,
        showInfo = shouldShowOverlay,
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
    HideArcBarricadePlacementUi()

    for barricadeId, barricade in pairs(arcPlacedBarricades or {}) do
        if barricade and barricade.entity and DoesEntityExist(barricade.entity) and barricade.targetName then
            exports.ox_target:removeLocalEntity(barricade.entity, barricade.targetName)
        end
        if barricade and barricade.entity and DoesEntityExist(barricade.entity) then
            DeleteEntity(barricade.entity)
        end
        arcPlacedBarricades[barricadeId] = nil
    end
end

local function RemoveLocalArcBarricade(barricadeId)
    local barricade = arcPlacedBarricades[barricadeId]
    if not barricade then
        return
    end

    if barricade.entity and DoesEntityExist(barricade.entity) and barricade.targetName then
        exports.ox_target:removeLocalEntity(barricade.entity, barricade.targetName)
    end
    if barricade.entity and DoesEntityExist(barricade.entity) then
        DeleteEntity(barricade.entity)
    end

    arcPlacedBarricades[barricadeId] = nil
end

local function SpawnLocalArcBarricade(barricadeData)
    local barricadeId = barricadeData and barricadeData.id
    local coords = ToVector3(barricadeData and barricadeData.coords)
    local model = barricadeData and barricadeData.model
    if not barricadeId or not coords or not model then
        print(('[gs-survival] Invalid ARC barricade payload: id=%s coords=%s model=%s'):format(tostring(barricadeId), tostring(coords), tostring(model)))
        return
    end

    RemoveLocalArcBarricade(barricadeId)

    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end

    local entity = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, false, false, false)
    SetEntityAsMissionEntity(entity, true, true)
    SetEntityHeading(entity, tonumber(barricadeData.heading or 0.0) or 0.0)
    FreezeEntityPosition(entity, true)
    PlaceObjectOnGroundProperly(entity)
    SetModelAsNoLongerNeeded(model)

    local targetName = ('arc_barricade_%s'):format(barricadeId)

    arcPlacedBarricades[barricadeId] = {
        entity = entity,
        ownerId = tonumber(barricadeData.ownerId) or 0,
        targetName = targetName,
        removing = false
    }

    exports.ox_target:addLocalEntity(entity, {
        {
            name = targetName,
            icon = 'fas fa-screwdriver-wrench',
            label = 'Barricade Sök',
            distance = 2.0,
            canInteract = function()
                local barricadeState = arcPlacedBarricades[barricadeId]
                return barricadeState
                    and barricadeState.removing ~= true
                    and not arcBarricadePreview
            end,
            onSelect = function()
                local barricadeState = arcPlacedBarricades[barricadeId]
                if not barricadeState or barricadeState.removing == true then
                    return
                end

                barricadeState.removing = true
                RunUiProgress({
                    title = "ARC Barricade",
                    label = "Barricade sökülüyor...",
                    duration = 2500,
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
                    local activeState = arcPlacedBarricades[barricadeId]
                    if activeState then
                        activeState.removing = false
                    end
                    TriggerServerEvent('gs-survival:server:removeArcBarricade', barricadeId)
                end, function()
                    local activeState = arcPlacedBarricades[barricadeId]
                    if activeState then
                        activeState.removing = false
                    end
                    NotifyForMode("Barricade sökme iptal edildi.", "error", 3500, "ARC Barricade")
                end)
            end
        }
    })
end

local GetArcBarricadeConfig

local function RotationToDirection(rotation)
    local rotX = math.rad(rotation.x)
    local rotZ = math.rad(rotation.z)
    local cosX = math.abs(math.cos(rotX))

    return vector3(
        -math.sin(rotZ) * cosX,
        math.cos(rotZ) * cosX,
        math.sin(rotX)
    )
end

local function GetArcBarricadeAimPosition(ped, placementState)
    local config = GetArcBarricadeConfig()
    local maxDistance = math.max(
        tonumber(config.InteractDistance) or 4.0,
        tonumber(config.PlaceDistance) or 2.2
    )
    local pedCoords = GetEntityCoords(ped)
    local cameraCoords = GetGameplayCamCoord()
    local direction = RotationToDirection(GetGameplayCamRot(2))
    local rayTarget = cameraCoords + (direction * (maxDistance + 6.0))
    local rayHandle = StartExpensiveSynchronousShapeTestLosProbe(
        cameraCoords.x, cameraCoords.y, cameraCoords.z,
        rayTarget.x, rayTarget.y, rayTarget.z,
        -1,
        placementState and placementState.entity or ped,
        7
    )
    local _, didHit, hitCoords = GetShapeTestResult(rayHandle)
    local targetCoords = didHit == 1 and hitCoords or rayTarget
    local offsetFromPed = targetCoords - pedCoords
    local offsetDistance = #offsetFromPed

    if offsetDistance <= 0.001 then
        targetCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, tonumber(config.PlaceDistance) or 2.2, 0.0)
    elseif offsetDistance > maxDistance then
        targetCoords = pedCoords + (offsetFromPed / offsetDistance) * maxDistance
    end

    local foundGround, groundZ = GetGroundZFor_3dCoord(targetCoords.x, targetCoords.y, targetCoords.z + 5.0, false)
    if not foundGround then
        foundGround, groundZ = GetGroundZFor_3dCoord(targetCoords.x, targetCoords.y, targetCoords.z + 50.0, false)
    end

    if foundGround then
        return vector3(targetCoords.x, targetCoords.y, groundZ)
    end

    return placementState and placementState.lastCoords or vector3(targetCoords.x, targetCoords.y, pedCoords.z)
end

local function GetArcBarricadePreviewPosition(ped, placementState)
    local aimCoords = GetArcBarricadeAimPosition(ped, placementState)
    if placementState then
        placementState.lastCoords = aimCoords
    end

    return aimCoords, (tonumber(placementState.heading) or 0.0) % 360.0
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

ToVector3 = function(coords)
    if not coords then return nil end
    if type(coords) == 'vector3' then return coords end
    if coords.x and coords.y and coords.z then
        return vector3(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)
    end
    return nil
end

GetArcBarricadeConfig = function()
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
        zoneCoords.x + ARC_EXTRACTION_HELI.SPAWN_OFFSET.x,
        zoneCoords.y + ARC_EXTRACTION_HELI.SPAWN_OFFSET.y,
        zoneCoords.z + hoverHeight + ARC_EXTRACTION_HELI.SPAWN_OFFSET.z
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
            and math.max(ARC_EXTRACTION_HELI.MIN_SPEED, math.min(ARC_EXTRACTION_HELI.MAX_SPEED, approachDistance / inboundSeconds))
            or ARC_EXTRACTION_HELI.HOVER_SPEED

        ClearPedTasks(arcExtractionPilot)
        TaskHeliMission(
            arcExtractionPilot,
            arcExtractionHeli,
            0,
            0,
            hoverCoords.x,
            hoverCoords.y,
            hoverCoords.z,
            ARC_EXTRACTION_HELI.MISSION_TYPE,
            flightSpeed,
            ARC_EXTRACTION_HELI.RADIUS,
            heading,
            hoverHeight,
            math.max(18.0, hoverHeight * 0.5),
            ARC_EXTRACTION_HELI.SLOW_DIST,
            ARC_EXTRACTION_HELI.MISSION_FLAGS
        )
        SetPedKeepTask(arcExtractionPilot, true)
        arcExtractionHeliTaskKey = targetTaskKey
    end

    SetVehicleEngineOn(arcExtractionHeli, true, true, false)
    SetHeliBladesFullSpeed(arcExtractionHeli)
end

local function ApplyArcExtractionState(state, notifyPayload)
    if currentModeId ~= 'arc_pvp' or not isSurvivalActive then
        ClearArcExtractionState()
        return
    end

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

local function BuildArcDeploymentMenuOptions()
    local deploymentZones = (Config.ArcPvP and Config.ArcPvP.DeploymentZones) or {}
    local lootRegions = (Config.ArcPvP and Config.ArcPvP.LootRegions) or {}
    local options = {}

    for zoneId, zoneData in pairs(deploymentZones) do
        if type(zoneId) == 'number' and zoneData then
            local regionData = lootRegions[zoneData.lootRegion or ''] or {}
            options[#options + 1] = {
                id = zoneId,
                label = zoneData.label or ("ARC Bölgesi " .. zoneId),
                description = "Baskın bölgesini burada seçer, ardından sol alttan operasyonu başlatırsın.",
                regionLabel = regionData.label or (zoneData.lootRegion and string.upper(zoneData.lootRegion) or "ARC"),
                lootLabel = regionData.tierLabel or "Baskın",
                lootNodeCount = #(zoneData.lootNodes or {}),
                insertionCount = #(zoneData.insertionPoints or {}),
                extractionLabel = zoneData.extractionPoint and "Hazır" or "Yok"
            }
        end
    end

    table.sort(options, function(a, b)
        return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
    end)

    return options
end

local function BuildSurvivalStageMenuOptions(userLevel)
    local options = {}

    for stageId, stageData in ipairs(Config.Stages or {}) do
        local enemyLabel = "Dalga Operasyonu"
        if stageData and stageData.Waves and stageData.Waves[1] and stageData.Waves[1].label then
            enemyLabel = stageData.Waves[1].label
        end

        options[#options + 1] = {
            id = stageId,
            label = stageData.label or ("Bölüm " .. stageId),
            multiplier = stageData.multiplier or 1.0,
            locked = stageId > (tonumber(userLevel) or 1),
            enemyLabel = enemyLabel
        }
    end

    return options
end

local function BuildMenuState(userLevel, PlayerData, arcPrepState, arcSummary, lobbyMembers)
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
          lobbyMembers = type(lobbyMembers) == 'table' and lobbyMembers or {},
           arcDeploymentZones = BuildArcDeploymentMenuOptions(),
           survivalStages = BuildSurvivalStageMenuOptions(userLevel),
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

local function DispatchMenuState(openMenu, forceUpdate)
    QBCore.Functions.GetPlayerData(function(PlayerData)
        local survivalMetadata = GetSurvivalMetadata()
        local userLevel = PlayerData.metadata[survivalMetadata.level or "survival_level"] or 1
        QBCore.Functions.TriggerCallback('gs-survival:server:getArcMenuState', function(arcState)
            local arcPrepState = arcState and arcState.prep or {}
            local arcSummary = arcState and arcState.summary or {}
            local lobbyMembers = arcState and arcState.lobbyMembers or {}
            local menuState = BuildMenuState(userLevel, PlayerData, arcPrepState, arcSummary, lobbyMembers)
            local nextCacheKey = BuildMenuStateCacheKey(menuState)
            local payload = {
                type = openMenu and 'openMenu' or 'updateMenuState',
                data = menuState
            }

            if openMenu then
                menuStateCacheKey = nextCacheKey
                OpenNUI(payload)
            elseif isMenuOpen and (forceUpdate == true or nextCacheKey ~= menuStateCacheKey) then
                menuStateCacheKey = nextCacheKey
                SendNUIMessage(payload)
            end
        end)
    end)
end

local function RefreshMainMenu()
    DispatchMenuState(not isMenuOpen, true)
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

local function OpenArcLockerManager(focusSide, keepScene)
    QBCore.Functions.TriggerCallback('gs-survival:server:getArcLockerState', function(lockerState)
        if not lockerState then
            NotifyForMode("ARC stash bilgisi alınamadı.", "error", 4000, "ARC Depo")
            return
        end

        OpenNUI({
            type = 'openArcLockers',
            data = lockerState
        }, {
            keepScene = keepScene == true
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
