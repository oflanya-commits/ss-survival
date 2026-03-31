local QBCore = exports['qb-core']:GetCoreObject()
local MAX_LOBBY_SIZE = 4
local MAX_LOBBY_MEMBERS = MAX_LOBBY_SIZE - 1
local DEFAULT_ARC_REUSE_MIN_REMAINING_SECONDS = 1080
local ARC_LOBBY_PROXIMITY_RADIUS = 10.0
local groupSizes, groupMembers, playerBackups = {}, {}, {}
local beingLooted = {}
local lobbyStage = {}
local bucketModes = {}
local activeLobbies = {}
local lootItemSet = {}
local finishingPlayers = {}
local openedArcContainers = {}
local arcDeathContainers = {}
local arcPlacedBarricades = {}
local openedNpcLoot = {}
local eliminatedArcPlayers = {}
local arcRaidState = {}
local arcRaidParticipants = {}
local arcSessionAdmission = {}
local arcSessionEliminations = {}
local arcSessionExtractions = {}
local arcSessionDisconnects = {}
local arcRaidSquads = {}
local arcStartLocks = {}
local arcDisconnectStates = {}
local arcFinalizeLocks = {}
local arcRaidPlayerProfiles = {}
local arcPlayerBucketIndex = {}
local arcPendingReconnectCounts = {}
local bucketWaveState = {}
local nextBucketId = 10000
local nextArcBarricadeId = 1
local FinalizeArcMatch
local ResetBucketState
local RestorePlayerInventory
local CleanBucketEntities
local BuildArcDeploymentPayload
local GetArcRaidRemainingMs
local ServerHelpers = {}

function ServerHelpers.BuildLootItemSet()
    lootItemSet = {}
    if Config and Config.LootTable then
        for _, loot in ipairs(Config.LootTable) do
            lootItemSet[loot.item] = true
        end
    end
end

ServerHelpers.BuildLootItemSet()

function ServerHelpers.CountMembers(memberTable)
    local count = 0
    for _ in pairs(memberTable or {}) do
        count = count + 1
    end
    return count
end

function ServerHelpers.NotifyPlayer(target, message, notifyType, title, duration)
    local playerId = tonumber(target)
    if not playerId or playerId <= 0 or not GetPlayerName(playerId) then
        return
    end

    if not message or message == '' then
        return
    end

    TriggerClientEvent('gs-survival:client:notify', playerId, {
        message = message,
        type = notifyType or 'primary',
        title = title,
        duration = duration
    })
end

function ServerHelpers.IsPlayerInList(playerList, playerId)
    for _, listedPlayerId in ipairs(playerList or {}) do
        if tonumber(listedPlayerId) == tonumber(playerId) then
            return true
        end
    end

    return false
end

function ServerHelpers.IsBucketMember(bucketId, playerId)
    if not bucketId or tonumber(bucketId) == 0 then
        return false
    end

    return ServerHelpers.IsPlayerInList(groupMembers[bucketId] or {}, playerId)
end

function ServerHelpers.IsPedEntityDead(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return true
    end

    return GetEntityHealth(entity) <= 0
end

function ServerHelpers.CountAliveBucketNpcs(bucketId)
    if not bucketId or bucketId == 0 then
        return 0
    end

    local aliveCount = 0
    for _, entity in ipairs(GetAllPeds()) do
        if GetEntityRoutingBucket(entity) == bucketId and not IsPedAPlayer(entity) and not ServerHelpers.IsPedEntityDead(entity) then
            aliveCount = aliveCount + 1
        end
    end

    return aliveCount
end

function ServerHelpers.FindLobbyLeaderByMember(memberId)
    for leaderId, data in pairs(activeLobbies) do
        if data.members and data.members[memberId] then
            return leaderId
        end
    end

    return nil
end

function ServerHelpers.GetGameMode(modeId)
    local gameModes = Config and Config.GameModes or {}
    return gameModes[modeId or 'classic'] or gameModes.classic
end

function ServerHelpers.GetGameModeId(modeId)
    local gameMode = ServerHelpers.GetGameMode(modeId)
    return gameMode and gameMode.id or 'classic'
end

function ServerHelpers.GetModeConfig(modeId)
    if ServerHelpers.GetGameModeId(modeId) == 'arc_pvp' then
        return Config.ArcPvP or {}
    end

    return Config.Survival or {}
end

function ServerHelpers.GetArcConfig()
    return Config.ArcPvP or {}
end

function ServerHelpers.GetArcRaidMaxPlayers()
    local configuredLimit = tonumber(ServerHelpers.GetArcConfig().MaxPlayersPerRaid)
    if not configuredLimit or configuredLimit <= 0 then
        return nil
    end

    return math.floor(configuredLimit)
end

function ServerHelpers.GetArcRaidPopulation(bucketId)
    local members = groupMembers[bucketId] or {}
    return #members
end

function ServerHelpers.EnsureArcRaidSquadState(bucketId)
    if not bucketId then
        return nil
    end

    arcRaidSquads[bucketId] = arcRaidSquads[bucketId] or {
        nextId = 1,
        squads = {},
        playerMap = {}
    }

    return arcRaidSquads[bucketId]
end

function ServerHelpers.CreateArcRaidSquad(bucketId, playerIds)
    local squadState = ServerHelpers.EnsureArcRaidSquadState(bucketId)
    if not squadState then
        return nil
    end

    local squadId = squadState.nextId
    squadState.nextId = squadId + 1

    local members = {}
    for _, playerId in ipairs(playerIds or {}) do
        local resolvedPlayerId = tonumber(playerId)
        if resolvedPlayerId and not ServerHelpers.IsPlayerInList(members, resolvedPlayerId) then
            members[#members + 1] = resolvedPlayerId
            squadState.playerMap[resolvedPlayerId] = squadId
        end
    end

    squadState.squads[squadId] = {
        members = members
    }

    return squadId
end

function ServerHelpers.GetArcRaidSquadMembers(bucketId, playerId)
    local squadState = arcRaidSquads[bucketId]
    local resolvedPlayerId = tonumber(playerId)
    local members = {}
    local memberLookup = {}

    if not squadState or not resolvedPlayerId then
        return members
    end

    local squadId = squadState.playerMap[resolvedPlayerId]
    local squad = squadId and squadState.squads[squadId] or nil
    for _, memberId in ipairs(squad and squad.members or {}) do
        local resolvedMemberId = tonumber(memberId)
        if resolvedMemberId and not memberLookup[resolvedMemberId] then
            memberLookup[resolvedMemberId] = true
            members[#members + 1] = resolvedMemberId
        end
    end

    return members
end

function ServerHelpers.RemoveArcRaidSquadPlayer(bucketId, playerId)
    local squadState = arcRaidSquads[bucketId]
    local resolvedPlayerId = tonumber(playerId)
    if not squadState or not resolvedPlayerId then
        return
    end

    local squadId = squadState.playerMap[resolvedPlayerId]
    local squad = squadId and squadState.squads[squadId] or nil
    if squad and squad.members then
        for index, memberId in ipairs(squad.members) do
            if tonumber(memberId) == resolvedPlayerId then
                table.remove(squad.members, index)
                break
            end
        end

        if #squad.members == 0 then
            squadState.squads[squadId] = nil
        end
    end

    squadState.playerMap[resolvedPlayerId] = nil
end

function ServerHelpers.AddArcRaidPlayerToSquad(bucketId, playerId, preferredMembers)
    local squadState = ServerHelpers.EnsureArcRaidSquadState(bucketId)
    local resolvedPlayerId = tonumber(playerId)
    if not squadState or not resolvedPlayerId then
        return nil
    end

    local currentSquadId = squadState.playerMap[resolvedPlayerId]
    if currentSquadId and squadState.squads[currentSquadId] then
        return currentSquadId
    end

    local preferredSquadId = nil
    for _, memberId in ipairs(preferredMembers or {}) do
        local resolvedMemberId = tonumber(memberId)
        local memberSquadId = resolvedMemberId and squadState.playerMap[resolvedMemberId] or nil
        if memberSquadId and squadState.squads[memberSquadId] then
            preferredSquadId = memberSquadId
            break
        end
    end

    if not preferredSquadId then
        return ServerHelpers.CreateArcRaidSquad(bucketId, { resolvedPlayerId })
    end

    local squad = squadState.squads[preferredSquadId]
    if not squad then
        return ServerHelpers.CreateArcRaidSquad(bucketId, { resolvedPlayerId })
    end

    if not ServerHelpers.IsPlayerInList(squad.members, resolvedPlayerId) then
        squad.members[#squad.members + 1] = resolvedPlayerId
    end
    squadState.playerMap[resolvedPlayerId] = preferredSquadId

    return preferredSquadId
end

function ServerHelpers.EnsureArcRaidPlayerProfileState(bucketId)
    if not bucketId then
        return nil
    end

    arcRaidPlayerProfiles[bucketId] = arcRaidPlayerProfiles[bucketId] or {}
    return arcRaidPlayerProfiles[bucketId]
end

function ServerHelpers.BuildArcPlayerDisplayName(Player, fallbackPlayerId)
    local charinfo = Player and Player.PlayerData and Player.PlayerData.charinfo or nil
    local firstname = charinfo and tostring(charinfo.firstname or '') or ''
    local lastname = charinfo and tostring(charinfo.lastname or '') or ''
    local fullName = (firstname .. " " .. lastname):match("^%s*(.-)%s*$") or ''

    if fullName ~= '' then
        return fullName
    end

    return ("ID %s"):format(tostring(fallbackPlayerId))
end

function ServerHelpers.RememberArcRaidPlayerProfile(bucketId, playerId, Player)
    local resolvedPlayerId = tonumber(playerId)
    local profileState = ServerHelpers.EnsureArcRaidPlayerProfileState(bucketId)
    if not resolvedPlayerId or not profileState then
        return nil
    end

    profileState[resolvedPlayerId] = {
        citizenid = Player and Player.PlayerData and Player.PlayerData.citizenid or nil,
        name = ServerHelpers.BuildArcPlayerDisplayName(Player, resolvedPlayerId)
    }

    return profileState[resolvedPlayerId]
end

function ServerHelpers.GetArcRaidPlayerProfile(bucketId, playerId)
    local resolvedPlayerId = tonumber(playerId)
    return resolvedPlayerId and arcRaidPlayerProfiles[bucketId] and arcRaidPlayerProfiles[bucketId][resolvedPlayerId] or nil
end

function ServerHelpers.SetArcPlayerBucketIndex(playerId, bucketId)
    local resolvedPlayerId = tonumber(playerId)
    if not resolvedPlayerId then
        return
    end

    if bucketId and tonumber(bucketId) ~= 0 then
        arcPlayerBucketIndex[resolvedPlayerId] = tonumber(bucketId)
        return
    end

    arcPlayerBucketIndex[resolvedPlayerId] = nil
end

function ServerHelpers.AdjustArcPendingReconnectCount(bucketId, delta)
    local resolvedBucketId = tonumber(bucketId)
    local change = tonumber(delta) or 0
    if not resolvedBucketId or resolvedBucketId == 0 or change == 0 then
        return
    end

    local nextValue = (tonumber(arcPendingReconnectCounts[resolvedBucketId]) or 0) + change
    if nextValue > 0 then
        arcPendingReconnectCounts[resolvedBucketId] = nextValue
    else
        arcPendingReconnectCounts[resolvedBucketId] = nil
    end
end

function ServerHelpers.FindArcBucketByPlayer(playerId)
    local resolvedPlayerId = tonumber(playerId)
    if not resolvedPlayerId then
        return nil
    end

    local indexedBucketId = tonumber(arcPlayerBucketIndex[resolvedPlayerId])
    if indexedBucketId and indexedBucketId ~= 0 then
        if groupMembers[indexedBucketId] and ServerHelpers.IsPlayerInList(groupMembers[indexedBucketId], resolvedPlayerId) then
            return indexedBucketId
        end

        arcPlayerBucketIndex[resolvedPlayerId] = nil
    end

    for bucketId, members in pairs(groupMembers) do
        if ServerHelpers.IsPlayerInList(members, resolvedPlayerId) then
            arcPlayerBucketIndex[resolvedPlayerId] = tonumber(bucketId)
            return bucketId
        end
    end

    return nil
end

local function GetArcExtractionConfig()
    return (ServerHelpers.GetArcConfig() and ServerHelpers.GetArcConfig().Extraction) or {}
end

local function GetArcExtractionSettings()
    local extractionConfig = GetArcExtractionConfig()

    return {
        enabled = extractionConfig.Enabled == true,
        unlockMode = tostring(extractionConfig.UnlockMode or 'manual_call'),
        unlockAfterSeconds = tonumber(extractionConfig.UnlockAfterSeconds or 0) or 0,
        lastPhaseUnlockSeconds = tonumber(extractionConfig.LastPhaseUnlockSeconds or 0) or 0,
        callDelaySeconds = tonumber(extractionConfig.CallDelay or 45) or 45,
        readyWindowSeconds = tonumber(extractionConfig.ReadyWindowSeconds or 90) or 90,
        manualDepartureCountdownSeconds = tonumber(extractionConfig.ManualDepartureCountdownSeconds) or 20,
        zoneRadius = tonumber(extractionConfig.ZoneRadius or 12.0) or 12.0,
        requireFullTeam = extractionConfig.RequireFullTeam == true,
        allowSoloExtract = extractionConfig.AllowSoloExtract ~= false,
        allowPartialTeamExtract = extractionConfig.AllowPartialTeamExtract ~= false,
        cancelIfZoneEmpty = extractionConfig.CancelIfZoneEmpty == true,
        boardingInterruptOnLeave = extractionConfig.BoardingInterruptOnLeave ~= false,
        autoFailIfNoExtract = extractionConfig.AutoFailIfNoExtract == true,
        manualDepartureEnabled = extractionConfig.ManualDepartureEnabled ~= false,
        autoDepartureOnTimeout = extractionConfig.AutoDepartureOnTimeout ~= false,
        notifyAllPlayers = extractionConfig.NotifyAllPlayers ~= false,
        spawnHelicopter = extractionConfig.SpawnHelicopter == true,
        useHelicopterScene = extractionConfig.UseHelicopterScene ~= false,
        helicopterModel = tostring(extractionConfig.HelicopterModel or 'frogger'),
        helicopterHeight = tonumber(extractionConfig.HelicopterHeight or 80.0) or 80.0,
        cleanupDelayMs = tonumber(extractionConfig.CleanupDelay or 10000) or 10000
    }
end

local function IsArcExtractionEnabled()
    return GetArcExtractionConfig().Enabled == true
end

local function NormalizeArcLootRegionId(regionId)
    if regionId == nil then
        return nil
    end

    return tostring(regionId):lower()
end

local function GetArcLootRegion(regionId)
    local normalizedRegionId = NormalizeArcLootRegionId(regionId)
    local lootRegions = ServerHelpers.GetArcConfig().LootRegions or {}
    local regionData = normalizedRegionId and lootRegions[normalizedRegionId] or nil

    if regionData and type(regionData.lootTable) == 'table' and #regionData.lootTable > 0 then
        return normalizedRegionId, regionData
    end

    return nil, nil
end

local function ResolveArcLootTable(regionId)
    local resolvedRegionId, regionData = GetArcLootRegion(regionId)
    if regionData then
        return regionData.lootTable, resolvedRegionId, regionData
    end

    return ServerHelpers.GetArcConfig().LootTable or {}, nil, nil
end

local function GetArcLootNodeState(bucketId, containerId)
    local deployment = bucketId and arcRaidState[bucketId] and arcRaidState[bucketId].deployment or nil
    if not deployment or not containerId then
        return nil
    end

    for _, node in ipairs(deployment.lootNodes or {}) do
        if node and node.id == containerId then
            return node
        end
    end

    return nil
end

local function GetArcDisconnectPolicy()
    local policy = tostring(ServerHelpers.GetArcConfig().DisconnectPolicy or 'rollback'):lower()
    if policy ~= 'rollback' and policy ~= 'death' and policy ~= 'rejoin' then
        policy = 'rollback'
    end
    return policy
end

local function BuildArcDisconnectPolicyInfo(policy)
    policy = tostring(policy or GetArcDisconnectPolicy()):lower()

    if policy == 'death' then
        return {
            key = 'death',
            label = 'Ölüm Sayılır',
            shortLabel = 'Bağlantı koparsa ölüm sayılır',
            description = 'Bağlantın koparsa baskın senin için ölümle sonuçlanmış gibi sayılır.'
        }
    end

    if policy == 'rejoin' then
        return {
            key = 'rejoin',
            label = 'Geri Dönüş',
            shortLabel = 'Bağlantı koparsa geri dön',
            description = 'Bağlantın koparsa aynı baskına geri dönmen hedeflenir.'
        }
    end

    return {
        key = 'rollback',
        label = 'Güvenli Dönüş',
        shortLabel = 'Bağlantı koparsa eşyaların korunur',
        description = 'Bağlantın koparsa eşyaların güvenli şekilde geri teslim edilir.'
    }
end

local function GetArcAdmissionSettings()
    local arcConfig = ServerHelpers.GetArcConfig()
    local lateJoinCutoffSeconds = tonumber(arcConfig.LateJoinCutoffSeconds or 0) or 0
    local configuredBackfillSeconds = arcConfig.MinimumRemainingSecondsForBackfill
    if configuredBackfillSeconds == nil then
        configuredBackfillSeconds = arcConfig.ReuseMinimumRemainingSeconds
    end
    local minimumRemainingSecondsForBackfill = tonumber(configuredBackfillSeconds) or DEFAULT_ARC_REUSE_MIN_REMAINING_SECONDS
    local sessionReuseStrategy = tostring(arcConfig.SessionReuseStrategy or 'most_remaining'):lower()
    local rejoinPolicy = tostring(arcConfig.RejoinPolicy or 'same_session_only'):lower()
    if sessionReuseStrategy ~= 'most_remaining' and sessionReuseStrategy ~= 'least_population' then
        sessionReuseStrategy = 'most_remaining'
    end
    if rejoinPolicy ~= 'same_session_only' and rejoinPolicy ~= 'disabled' then
        rejoinPolicy = 'same_session_only'
    end

    return {
        rejoinPolicy = rejoinPolicy,
        lateJoinCutoffSeconds = math.max(0, lateJoinCutoffSeconds),
        allowJoinAfterExtractionUnlocked = arcConfig.AllowJoinAfterExtractionUnlocked == true,
        denyJoinIfSquadPreviouslyEliminated = arcConfig.DenyJoinIfSquadPreviouslyEliminated ~= false,
        minimumRemainingSecondsForBackfill = math.max(0, minimumRemainingSecondsForBackfill),
        sessionReuseStrategy = sessionReuseStrategy
    }
end

local function GetArcStartLockKey(src)
    return ("leader_%s"):format(tonumber(src) or 0)
end

local function AcquireArcStartLock(src)
    local lockKey = GetArcStartLockKey(src)
    local debounceMs = tonumber(ServerHelpers.GetArcConfig().StartDebounceMs) or 6000
    local now = GetGameTimer()
    local lockState = arcStartLocks[lockKey]

    if lockState then
        if lockState.busy then
            return false, "ARC deploy işlemi zaten hazırlanıyor."
        end

        local remainingMs = (tonumber(lockState.untilMs or 0) or 0) - now
        if remainingMs > 0 then
            return false, ("Deploy isteği çok hızlı tekrarlandı. %0.1f sn bekle."):format(remainingMs / 1000)
        end
    end

    arcStartLocks[lockKey] = {
        busy = true,
        untilMs = now + debounceMs
    }

    return true, lockKey
end

local function ReleaseArcStartLock(lockKey)
    if not lockKey or not arcStartLocks[lockKey] then return end
    arcStartLocks[lockKey].busy = false
end

local function GetModeMetadata(modeId)
    local modeConfig = ServerHelpers.GetModeConfig(modeId)
    return modeConfig.Metadata or {}
end

local function GetModeStages(modeId)
    if ServerHelpers.GetGameModeId(modeId) == 'arc_pvp' then
        return (Config.ArcPvP and Config.ArcPvP.Arenas) or {}
    end

    return Config.Stages or {}
end

local function GetStageData(modeId, stageId)
    local stages = GetModeStages(modeId)
    return stages[tonumber(stageId or 1)]
end

local function GetClassicMaxWaveForStage(stageId)
    local stageData = GetStageData('classic', stageId)
    local waveCount = 0

    for waveId in pairs((stageData and stageData.Waves) or {}) do
        if type(waveId) == 'number' and waveId > waveCount then
            waveCount = waveId
        end
    end

    return waveCount
end

local function GetRandomUnlockedStageId(maxLevel, modeId)
    local unlockedStages = {}
    local highestLevel = tonumber(maxLevel) or 1

    for stageId, _ in pairs(GetModeStages(modeId) or {}) do
        if type(stageId) == 'number' and stageId <= highestLevel then
            unlockedStages[#unlockedStages + 1] = stageId
        end
    end

    if #unlockedStages == 0 then
        return 1
    end

    return unlockedStages[math.random(1, #unlockedStages)]
end

local function GetBackupStashId(modeId, citizenId)
    if ServerHelpers.GetGameModeId(modeId) == 'arc_pvp' then
        return (Config.ArcPvP and Config.ArcPvP.BackupStashPrefix or 'arc_backup_') .. citizenId
    end

    local backupCfg = (Config.Survival and Config.Survival.BackupStash) or {}
    return (backupCfg.Prefix or 'surv_backup_') .. citizenId
end

local function RegisterBackupStash(modeId, stashId)
    if ServerHelpers.GetGameModeId(modeId) == 'arc_pvp' then
        exports.ox_inventory:RegisterStash(
            stashId,
            (Config.ArcPvP and Config.ArcPvP.BackupStashLabel) or "Arc Geçici Stash",
            (Config.ArcPvP and Config.ArcPvP.BackupStashSlots) or 50,
            (Config.ArcPvP and Config.ArcPvP.BackupStashWeight) or 100000
        )
        return
    end

    local backupCfg = (Config.Survival and Config.Survival.BackupStash) or {}
    exports.ox_inventory:RegisterStash(
        stashId,
        backupCfg.Label or "Survival Yedek",
        backupCfg.Slots or 50,
        backupCfg.Weight or 100000
    )
end

local function SetModeActiveState(Player, modeId, isActive)
    if not Player then return end

    local metadata = GetModeMetadata(modeId)
    if metadata.activeFlag and metadata.activeFlag ~= '' then
        Player.Functions.SetMetaData(metadata.activeFlag, isActive == true)
    end

    if metadata.modeKey and metadata.modeKey ~= '' then
        Player.Functions.SetMetaData(metadata.modeKey, isActive and ServerHelpers.GetGameModeId(modeId) or nil)
    end
end

local function ClearAllModeState(Player)
    if not Player then return end

    for _, modeId in pairs({ 'classic', 'arc_pvp' }) do
        SetModeActiveState(Player, modeId, false)
    end
end

local function IsModeActive(Player, modeId)
    if not Player then return false end

    local metadata = GetModeMetadata(modeId)
    if metadata.activeFlag and Player.PlayerData.metadata[metadata.activeFlag] then
        return true
    end

    if metadata.modeKey and Player.PlayerData.metadata[metadata.modeKey] == ServerHelpers.GetGameModeId(modeId) then
        return true
    end

    local legacyModeId = Player.PlayerData.metadata["survival_mode"]
    if legacyModeId == ServerHelpers.GetGameModeId(modeId) then
        return true
    end

    if ServerHelpers.GetGameModeId(modeId) == 'classic' and Player.PlayerData.metadata["in_survival"] then
        return true
    end

    return false
end

local function GetActiveModeId(Player)
    for configuredModeId, _ in pairs((Config and Config.GameModes) or {}) do
        if IsModeActive(Player, configuredModeId) then
            return ServerHelpers.GetGameModeId(configuredModeId)
        end
    end

    return nil
end

local function ResolvePlayerActiveModeState(playerId, Player)
    if not Player then
        return nil
    end

    local activeModeId = GetActiveModeId(Player)
    if not activeModeId or activeModeId == '' then
        return nil
    end

    if GetPlayerRoutingBucket(playerId) ~= 0 then
        return activeModeId
    end

    local cid = Player.PlayerData.citizenid
    local backupStashId = GetBackupStashId(activeModeId, cid)
    local ok, backupItems = pcall(function()
        return exports.ox_inventory:GetInventoryItems(backupStashId)
    end)
    if not ok then
        return activeModeId
    end
    local hasBackupItems = backupItems and next(backupItems)
    local hasCachedBackup = playerBackups[cid] and next(playerBackups[cid]) ~= nil
    local hasArcReconnectState = ServerHelpers.GetGameModeId(activeModeId) == 'arc_pvp' and arcDisconnectStates[cid] ~= nil

    if hasBackupItems or hasCachedBackup or hasArcReconnectState then
        return activeModeId
    end

    -- Bucket 0 with no recoverable backup/reconnect data means only stale mode metadata remains.
    ClearAllModeState(Player)
    Player.Functions.Save()
    return nil
end

local function GetPlayerStarterLoadout(Player, modeId)
    if ServerHelpers.GetGameModeId(modeId) == 'arc_pvp' then
        local arcLoadout = (Config.ArcPvP and Config.ArcPvP.Loadout) or {}
        return {
            items = arcLoadout.Items or {},
            weapon = arcLoadout.Weapon or Config.Combat.DefaultWeapon or "weapon_pistol",
            ammoType = arcLoadout.Ammo or Config.Combat.DefaultAmmo or "ammo-9",
            ammoCount = arcLoadout.AmmoAmount or Config.Combat.DefaultAmmoAmount or 100,
            armor = tonumber(arcLoadout.Armor or 0) or 0
        }
    end

    local metadata = GetModeMetadata(modeId)
    local starterWeapon = Player.PlayerData.metadata[metadata.weapon or 'survival_weapon'] or Config.Combat.DefaultWeapon or "weapon_pistol"
    local ammoType = Config.Combat.DefaultAmmo or "ammo-9"
    local ammoCount = Config.Combat.DefaultAmmoAmount or 100

    for _, upgrade in pairs(Config.Upgrades or {}) do
        if upgrade.value == starterWeapon and upgrade.ammoType then
            ammoType = upgrade.ammoType
            ammoCount = upgrade.ammoAmount or ammoCount
            break
        end
    end

    return {
        items = Config.Combat.DefaultItems or {},
        weapon = starterWeapon,
        ammoType = ammoType,
        ammoCount = ammoCount,
        armor = tonumber(Player.PlayerData.metadata[metadata.armor or 'survival_armor'] or 0) or 0
    }
end

local function GiveModeLoadout(playerId, Player, modeId, preparedLoadout)
    if ServerHelpers.GetGameModeId(modeId) == 'arc_pvp' and preparedLoadout and #preparedLoadout > 0 then
        for _, itemData in ipairs(preparedLoadout) do
            local metadata = itemData.metadata or {}
            metadata.survivalItem = true
            metadata.arcPrepared = true
            exports.ox_inventory:AddItem(playerId, itemData.name, itemData.count, metadata)
        end
        return
    end

    local loadout = GetPlayerStarterLoadout(Player, modeId)

    for _, data in ipairs(loadout.items or {}) do
        exports.ox_inventory:AddItem(playerId, data.item, data.count, { survivalItem = true })
    end

    exports.ox_inventory:AddItem(playerId, loadout.weapon, 1, { survivalItem = true })
    exports.ox_inventory:AddItem(playerId, loadout.ammoType, loadout.ammoCount, { survivalItem = true })

    if loadout.armor > 0 then
        TriggerClientEvent('gs-survival:client:setArmor', playerId, loadout.armor)
    end
end

local function RegisterArcMainStash(Player)
    if not Player or not Config.ArcPvP then return nil end

    local citizenId = Player.PlayerData.citizenid
    if not citizenId then return nil end

    local stashId = (Config.ArcPvP.MainStashPrefix or 'arc_main_') .. citizenId
    exports.ox_inventory:RegisterStash(
        stashId,
        Config.ArcPvP.MainStashLabel or "ARC Ana Depo",
        Config.ArcPvP.MainStashSlots or 80,
        Config.ArcPvP.MainStashWeight or 200000
    )

    return stashId
end

local function RegisterArcLoadoutStash(Player)
    if not Player or not Config.ArcPvP then return nil end

    local citizenId = Player.PlayerData.citizenid
    if not citizenId then return nil end

    local stashId = (Config.ArcPvP.LoadoutStashPrefix or 'arc_loadout_') .. citizenId
    exports.ox_inventory:RegisterStash(
        stashId,
        Config.ArcPvP.LoadoutStashLabel or "ARC Baskın Çantası",
        Config.ArcPvP.LoadoutStashSlots or 24,
        Config.ArcPvP.LoadoutStashWeight or 75000
    )

    return stashId
end

local function CountInventoryItemByName(items, itemName)
    if not itemName or itemName == '' then
        return 0
    end

    local totalCount = 0
    for _, item in pairs(items or {}) do
        if item and item.name == itemName then
            totalCount = totalCount + (tonumber(item.count or item.amount or 0) or 0)
        end
    end

    return totalCount
end

local function GetCraftInventoryItems(Player, craftSource)
    if not Player then
        return {}
    end

    return craftSource and exports.ox_inventory:GetInventoryItems(craftSource.stashId) or Player.PlayerData.items or {}
end

local VALID_CRAFT_RECIPE_CATEGORIES = {
    ammo = true,
    weapon = true,
    health = true,
    material = true
}

local function GetCraftRecipeCategory(recipe)
    local category = type(recipe) == 'table' and recipe.category or nil
    if VALID_CRAFT_RECIPE_CATEGORIES[category] then
        return category
    end

    return 'material'
end

local function GetSharedItemLabel(itemName)
    local sharedItem = QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[itemName]
    return sharedItem and sharedItem.label or itemName
end

local GetCraftMaxCraftable
local FindCraftRecipeArgs
local NormalizeCraftMultiplier
local BuildScaledCraftRequirements

local function BuildCraftRecipesForPlayer(Player, craftSource)
    local recipes = {}
    local inventoryItems = GetCraftInventoryItems(Player, craftSource)

    for _, recipe in ipairs(Config.CraftRecipes or {}) do
        local args = recipe.params and recipe.params.args or {}
        local requirements = {}
        local canCraft = true

        for _, req in ipairs(args.requirements or {}) do
            local neededAmount = tonumber(req.amount) or 0
            local ownedAmount = CountInventoryItemByName(inventoryItems, req.item)
            if ownedAmount < neededAmount then
                canCraft = false
            end

            requirements[#requirements + 1] = {
                item = req.item,
                itemLabel = GetSharedItemLabel(req.item),
                amount = neededAmount,
                ownedAmount = ownedAmount,
                isMet = ownedAmount >= neededAmount
            }
        end

        local category = GetCraftRecipeCategory(recipe)
        recipes[#recipes + 1] = {
            header = recipe.header,
            txt = recipe.txt,
            item = args.item,
            amount = args.amount,
            label = args.label,
            requirements = requirements,
            category = category,
            ready = canCraft,
            maxCraftable = GetCraftMaxCraftable(inventoryItems, args.requirements)
        }
    end

    return recipes
end

local function ResolveArcCraftSource(Player, stashId)
    if not Player or type(stashId) ~= 'string' or stashId == '' then
        return nil
    end

    local mainStashId = RegisterArcMainStash(Player)
    local loadoutStashId = RegisterArcLoadoutStash(Player)

    if stashId == mainStashId then
        return {
            stashId = mainStashId,
            side = 'main',
            label = Config.ArcPvP.MainStashLabel or "ARC Ana Depo"
        }
    end

    if stashId == loadoutStashId then
        return {
            stashId = loadoutStashId,
            side = 'loadout',
            label = Config.ArcPvP.LoadoutStashLabel or "ARC Baskın Çantası"
        }
    end

    return nil
end

local function HasCraftRequirements(Player, requirements, craftSource)
    if not Player then
        return false
    end

    local items = GetCraftInventoryItems(Player, craftSource)
    for _, req in pairs(requirements or {}) do
        if CountInventoryItemByName(items, req.item) < (tonumber(req.amount) or 0) then
            return false
        end
    end

    return true
end

GetCraftMaxCraftable = function(inventoryItems, requirements)
    local maxCraftable = nil

    for _, req in pairs(requirements or {}) do
        local neededAmount = tonumber(req.amount) or 0
        if neededAmount > 0 then
            local ownedAmount = CountInventoryItemByName(inventoryItems, req.item)
            local possibleAmount = math.floor(ownedAmount / neededAmount)
            if maxCraftable == nil or possibleAmount < maxCraftable then
                maxCraftable = possibleAmount
            end
        end
    end

    if maxCraftable == nil then
        return 1
    end

    return math.max(maxCraftable, 0)
end

FindCraftRecipeArgs = function(itemName, itemAmount)
    for _, recipe in ipairs(Config.CraftRecipes or {}) do
        local args = recipe.params and recipe.params.args
        if args and args.item == itemName and args.amount == itemAmount then
            return args
        end
    end

    return nil
end

NormalizeCraftMultiplier = function(value)
    local multiplier = math.floor(tonumber(value) or 1)
    return math.max(multiplier, 1)
end

BuildScaledCraftRequirements = function(requirements, multiplier)
    local scaledRequirements = {}

    for _, req in pairs(requirements or {}) do
        scaledRequirements[#scaledRequirements + 1] = {
            item = req.item,
            amount = (tonumber(req.amount) or 0) * multiplier
        }
    end

    return scaledRequirements
end

local function CountInventoryEntries(items)
    local stackCount, itemCount = 0, 0
    for _, item in pairs(items or {}) do
        if item and item.name and tonumber(item.count or 0) > 0 then
            stackCount = stackCount + 1
            itemCount = itemCount + (tonumber(item.count or 0) or 0)
        end
    end

    return stackCount, itemCount
end

local function BuildArcLoadoutReadinessState(loadoutStacks, loadoutItems)
    local requirePrepared = ServerHelpers.GetArcConfig().RequirePreparedLoadout == true
    local isReady = (tonumber(loadoutStacks) or 0) > 0
    local usesFallback = not isReady and not requirePrepared
    local status = 'prepared'
    local label = 'Baskın çantası hazır'
    local helperText = 'Buraya koyduğun ekipman baskına girerken üstüne verilecek.'

    if not isReady and requirePrepared then
        status = 'missing_required'
        label = 'Baskın çantası boş'
        helperText = 'Bu sunucuda baskına girmek için önceden ekipman hazırlaman gerekiyor.'
    elseif not isReady then
        status = 'fallback'
        label = 'Baskın çantası boş'
        helperText = 'Hazır ekipmanın yoksa sana varsayılan başlangıç paketi verilecek.'
    end

    return {
        stacks = tonumber(loadoutStacks) or 0,
        items = tonumber(loadoutItems) or 0,
        isReady = isReady,
        isEmpty = not isReady,
        usesFallback = usesFallback,
        requiresPrepared = requirePrepared,
        status = status,
        label = label,
        helperText = helperText
    }
end

local function NormalizeInventoryItems(items)
    local normalized = {}
    for _, item in pairs(items or {}) do
        local count = tonumber(item and item.count or 0) or 0
        if item and item.name and count > 0 then
            normalized[#normalized + 1] = {
                name = item.name,
                count = count,
                metadata = item.metadata
            }
        end
    end

    return normalized
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

local function BuildArcBarricadeClientState(barricadeId, barricadeState)
    local coords = ToVector3(barricadeState and barricadeState.coords)
    local model = barricadeState and barricadeState.model
    if not barricadeId or not coords or not model then
        return nil
    end

    return {
        id = barricadeId,
        coords = {
            x = coords.x,
            y = coords.y,
            z = coords.z
        },
        heading = tonumber(barricadeState.heading or 0.0) or 0.0,
        model = model,
        ownerId = tonumber(barricadeState.ownerId) or 0
    }
end

local function BuildArcLockerEntries(items)
    local entries = {}
    local oxItems = exports.ox_inventory:Items() or {}

    for _, item in pairs(items or {}) do
        local count = tonumber(item and item.count or 0) or 0
        if item and item.name and count > 0 then
            local oxItem = oxItems[item.name] or {}
            local metadata = item.metadata or {}
            entries[#entries + 1] = {
                slot = tonumber(item.slot) or 0,
                name = item.name,
                label = metadata.label or item.label or oxItem.label or item.name,
                count = count,
                image = metadata.image or metadata.imageurl or oxItem.image or item.name,
                description = metadata.description or oxItem.description,
                metadata = metadata,
                isWeapon = oxItem.weapon == true,
                stackable = oxItem.weapon ~= true
            }
        end
    end

    table.sort(entries, function(a, b)
        return (a.slot or 0) < (b.slot or 0)
    end)

    return entries
end

local function Vector3ToTable(coords)
    if not coords then return nil end
    return {
        x = tonumber(coords.x) or 0.0,
        y = tonumber(coords.y) or 0.0,
        z = tonumber(coords.z) or 0.0
    }
end

local function GetArcExtractionState(bucketId)
    local raidState = bucketId and arcRaidState[bucketId] or nil
    return raidState and raidState.extraction or nil
end

local function GetArcExtractionZones(bucketId)
    local extractionState = GetArcExtractionState(bucketId)
    local zones = extractionState and extractionState.zones or nil
    if type(zones) == 'table' and #zones > 0 then
        return zones
    end

    if extractionState and extractionState.zone then
        return { extractionState.zone }
    end

    return {}
end

local function GetArcExtractionZoneCoords(bucketId)
    local extractionState = GetArcExtractionState(bucketId)
    return extractionState and ToVector3(extractionState.zone and extractionState.zone.coords) or nil
end

local function FindArcExtractionZone(bucketId, searchCoords, allowanceRadius, preferredZoneId)
    local extractionState = GetArcExtractionState(bucketId)
    local zoneRadius = tonumber(extractionState and extractionState.zoneRadius or 0.0) or 0.0
    local maxDistance = zoneRadius + (tonumber(allowanceRadius or 0.0) or 0.0)
    local matchedZone = nil
    local matchedDistance = nil

    if preferredZoneId ~= nil then
        local preferredZoneIdText = tostring(preferredZoneId)
        for _, zone in ipairs(GetArcExtractionZones(bucketId)) do
            if zone and tostring(zone.id) == preferredZoneIdText then
                local zoneCoords = ToVector3(zone.coords)
                if zoneCoords then
                    local distance = searchCoords and #(searchCoords - zoneCoords) or nil
                    if not distance or maxDistance <= 0.0 or distance <= maxDistance then
                        return zone, distance
                    end
                end
            end
        end
    end

    for _, zone in ipairs(GetArcExtractionZones(bucketId)) do
        local zoneCoords = ToVector3(zone and zone.coords)
        if zoneCoords then
            local distance = searchCoords and #(searchCoords - zoneCoords) or nil
            if not distance or maxDistance <= 0.0 or distance <= maxDistance then
                if not matchedDistance or distance < matchedDistance then
                    matchedZone = zone
                    matchedDistance = distance
                end
            end
        end
    end

    return matchedZone, matchedDistance
end

local function GetArcExtractionPhaseLabel(phase)
    local labels = {
        idle = 'Kilitli',
        available = 'Hazır',
        called = 'Çağrı Gönderildi',
        inbound = 'Airlift Yolda',
        ready = 'Kalkışa Hazır',
        extracted = 'Tahliye Tamamlandı',
        failed = 'Tahliye Başarısız',
        cleaned = 'Temizlendi'
    }

    return labels[tostring(phase or 'idle')] or 'Bilinmiyor'
end

local function BuildArcExtractionObjectiveText(extractionState)
    if not extractionState then
        return "Tahliye verisi hazırlanıyor."
    end

    local phase = tostring(extractionState.phase or 'idle')
    local availableZones = extractionState.zones or {}
    local zoneLabel = extractionState.zone and extractionState.zone.label or "Tahliye Noktası"

    if phase == 'idle' then
        if #availableZones > 1 then
            return "Tahliye noktaları şu an kilitli. Baskın ilerledikçe erişim açılacak."
        end
        return ("%s şu an kilitli. Baskın ilerledikçe erişim açılacak."):format(zoneLabel)
    elseif phase == 'available' then
        if #availableZones > 1 then
            return "Herhangi bir tahliye noktasında hava tahliyesi çağrısı yap."
        end
        return ("%s üzerinde hava tahliyesi çağrısı yap."):format(zoneLabel)
    elseif phase == 'called' then
        return "Çağrı onaylandı. Hava hattı açılıyor."
    elseif phase == 'inbound' then
        return "Airlift hatta. Bölgeye yaklaş ve alanı emniyette tut."
    elseif phase == 'ready' then
        if extractionState.departurePending == true then
            return "Kalkış sayacı başladı. Sayaç bitince tahliye alanındaki yaşayan operatifler tahliye olacak."
        elseif extractionState.manualDepartureEnabled ~= false then
            local countdownSeconds = math.max(0, math.floor((tonumber(extractionState.manualDepartureCountdownMs or 0) or 0) / 1000))
            local autoDepartureCountdownSeconds = math.max(0, math.floor((tonumber(extractionState.readyWindowMs or 0) or 0) / 1000))
            return ("Helikopter hazır bekliyor. Tahliye alanında bir operatif kalkışı başlatırsa içeridekiler %s saniye sonra tahliye olacak; kimse başlatmazsa %s saniye sonunda otomatik tahliye edilecek."):format(tostring(countdownSeconds), tostring(autoDepartureCountdownSeconds))
        end
        return "Helikopter hazır bekliyor. Süre dolduğunda tahliye alanındaki yaşayan operatifler otomatik tahliye olacak."
    elseif phase == 'extracted' then
        return "Tahliye tamamlandı. Son kalan operatifler sahadan çıkıyor."
    elseif phase == 'failed' then
        return "Tahliye penceresi kapandı. Sahadan çıkılamadı."
    end

    return "Tahliye sahnesi temizleniyor."
end

local function BuildArcPrepState(Player)
    if not Player then
        return {
            mainStacks = 0,
            mainItems = 0,
            loadoutStacks = 0,
            loadoutItems = 0,
            loadoutReady = false,
            loadoutState = BuildArcLoadoutReadinessState(0, 0)
        }
    end

    local mainStashId = RegisterArcMainStash(Player)
    local loadoutStashId = RegisterArcLoadoutStash(Player)
    local mainItems = exports.ox_inventory:GetInventoryItems(mainStashId)
    local loadoutItems = exports.ox_inventory:GetInventoryItems(loadoutStashId)
    local mainStacks, mainItemCount = CountInventoryEntries(mainItems)
    local loadoutStacks, loadoutItemCount = CountInventoryEntries(loadoutItems)
    local loadoutState = BuildArcLoadoutReadinessState(loadoutStacks, loadoutItemCount)

    return {
        mainStacks = mainStacks,
        mainItems = mainItemCount,
        loadoutStacks = loadoutStacks,
        loadoutItems = loadoutItemCount,
        loadoutReady = loadoutState.isReady,
        loadoutState = loadoutState
    }
end

local function GetLobbyContext(source)
    if activeLobbies[source] then
        return source, activeLobbies[source], true
    end

    local leaderId = ServerHelpers.FindLobbyLeaderByMember(source)
    return leaderId, leaderId and activeLobbies[leaderId] or nil, false
end

local function BuildArcUiSummaryState(source, prepState)
    prepState = prepState or {}

    local leaderId, lobby, isLeader = GetLobbyContext(source)
    local isMember = leaderId ~= nil and not isLeader
    local localPed = GetPlayerPed(source)
    local strictValidation = ServerHelpers.GetArcConfig().StrictDeploymentValidation == true
    local allowInventory = ServerHelpers.GetArcConfig().AllowPersonalInventory ~= false
    local disconnectInfo = BuildArcDisconnectPolicyInfo()
    local extractionSettings = GetArcExtractionSettings()
    local missingReadyNames = {}
    local distantNames = {}
    local blockers = {}
    local checks = {}
    local loadoutState = prepState.loadoutState or BuildArcLoadoutReadinessState(prepState.loadoutStacks, prepState.loadoutItems)

    if lobby then
        for memberId, info in pairs(lobby.members or {}) do
            local memberName = type(info) == 'table' and info.name or tostring(info or memberId)
            local memberReady = type(info) == 'table' and info.isReady == true or false
            if not memberReady then
                missingReadyNames[#missingReadyNames + 1] = memberName
            end

            if strictValidation and localPed ~= 0 then
                local targetPed = GetPlayerPed(memberId)
                if targetPed == 0 or #(GetEntityCoords(localPed) - GetEntityCoords(targetPed)) >= 10.0 then
                    distantNames[#distantNames + 1] = memberName
                end
            end
        end
    end

    if isMember then
        blockers[#blockers + 1] = 'Baskını yalnızca lobi lideri başlatabilir.'
    end
    if #missingReadyNames > 0 then
        blockers[#blockers + 1] = 'Hazır olmayan oyuncular: ' .. table.concat(missingReadyNames, ', ')
    end
    if #distantNames > 0 then
        blockers[#blockers + 1] = 'Baskına girmek için çok uzakta kalan oyuncular: ' .. table.concat(distantNames, ', ')
    end
    if loadoutState.requiresPrepared and not loadoutState.isReady then
        blockers[#blockers + 1] = 'Baskın çantası boş. Bu sunucuda baskına girmeden önce ekipman hazırlaman gerekiyor.'
    end

    checks[#checks + 1] = {
        key = 'leader',
        title = 'Lider yetkisi',
        status = isMember and 'error' or 'ok',
        detail = isMember and 'Baskını başlatmak için liderin onayı gerekiyor.' or (lobby and 'Baskını başlatma yetkisi sende.' or 'İstersen tek başına başlayabilirsin.')
    }
    checks[#checks + 1] = {
        key = 'ready',
        title = 'Takım hazır mı?',
        status = #missingReadyNames > 0 and 'error' or 'ok',
        detail = #missingReadyNames > 0 and ('Eksik: ' .. table.concat(missingReadyNames, ', ')) or 'Hazır bekleyen oyuncu eksik değil.'
    }
    checks[#checks + 1] = {
        key = 'distance',
        title = 'Takım konumu',
        status = #distantNames > 0 and 'error' or 'ok',
        detail = #distantNames > 0 and ('Uzakta kalanlar: ' .. table.concat(distantNames, ', ')) or (strictValidation and 'Takım baskına birlikte girecek kadar yakın.' or 'Yakınlık kontrolü bu baskında esnek tutuluyor.')
    }
    checks[#checks + 1] = {
        key = 'loadout',
        title = 'Baskın çantası',
        status = loadoutState.isReady and 'ok' or (loadoutState.usesFallback and 'warn' or 'error'),
        detail = loadoutState.helperText
    }
    checks[#checks + 1] = {
        key = 'inventory',
        title = 'Kişisel envanter',
        status = allowInventory and 'ok' or 'warn',
        detail = allowInventory and 'ARC baskınında TAB ile kişisel envanter açılabilir.' or 'ARC baskınında kişisel envanter kapalı.'
    }
    checks[#checks + 1] = {
        key = 'extraction',
        title = 'Tahliye penceresi',
        status = extractionSettings.enabled == true and 'ok' or 'warn',
        detail = extractionSettings.enabled == true
            and (("Mod: %s • Çağrı: %ss • Ready: %ss"):format(
                extractionSettings.unlockMode,
                extractionSettings.callDelaySeconds,
                extractionSettings.readyWindowSeconds
            ))
            or 'ARC extraction devre dışı; baskın süresi dolduğunda mevcut finalize akışı kullanılır.'
    }
    checks[#checks + 1] = {
        key = 'disconnect',
        title = 'Bağlantı koparsa',
        status = disconnectInfo.key == 'rollback' and 'warn' or 'ok',
        detail = disconnectInfo.description
    }

    return {
        canDeploy = #blockers == 0,
        blockers = blockers,
        missingReadyNames = missingReadyNames,
        distantNames = distantNames,
        checks = checks,
        disconnectPolicy = disconnectInfo.key,
        disconnectPolicyLabel = disconnectInfo.label,
        disconnectPolicyDescription = disconnectInfo.description,
        allowPersonalInventory = allowInventory,
        requirePreparedLoadout = loadoutState.requiresPrepared,
        loadoutStatus = loadoutState.status,
        extraction = {
            enabled = extractionSettings.enabled,
            unlockMode = extractionSettings.unlockMode,
            unlockAfterSeconds = extractionSettings.unlockAfterSeconds,
            lastPhaseUnlockSeconds = extractionSettings.lastPhaseUnlockSeconds,
            callDelay = extractionSettings.callDelaySeconds,
            readyWindow = extractionSettings.readyWindowSeconds,
            zoneRadius = extractionSettings.zoneRadius,
            requireFullTeam = extractionSettings.requireFullTeam,
            allowSoloExtract = extractionSettings.allowSoloExtract,
            allowPartialTeamExtract = extractionSettings.allowPartialTeamExtract,
            manualDepartureEnabled = extractionSettings.manualDepartureEnabled,
            autoDepartureOnTimeout = extractionSettings.autoDepartureOnTimeout,
            autoFailIfNoExtract = extractionSettings.autoFailIfNoExtract
        }
    }
end

local function BuildArcLockerState(Player, focusSide)
    if not Player then return nil end

    local mainStashId = RegisterArcMainStash(Player)
    local loadoutStashId = RegisterArcLoadoutStash(Player)
    if not mainStashId or not loadoutStashId then return nil end

    local normalizedFocus = focusSide == 'loadout' and 'loadout' or 'main'
    local sections = {
        main = {
            side = 'main',
            stashId = mainStashId,
            label = Config.ArcPvP.MainStashLabel or "ARC Kalıcı Depo",
            title = 'Kalıcı Depo',
            helperText = 'Burası kalıcı depon. İçindekiler baskın dışında da sende kalır.',
            slots = tonumber(Config.ArcPvP.MainStashSlots) or 0,
            items = BuildArcLockerEntries(exports.ox_inventory:GetInventoryItems(mainStashId))
        },
        loadout = {
            side = 'loadout',
            stashId = loadoutStashId,
            label = Config.ArcPvP.LoadoutStashLabel or "ARC Baskın Çantası",
            title = 'Baskın Çantası',
            helperText = 'Baskına girerken üstüne verilecek ekipmanı burada hazırlarsın.',
            slots = tonumber(Config.ArcPvP.LoadoutStashSlots) or 0,
            items = BuildArcLockerEntries(exports.ox_inventory:GetInventoryItems(loadoutStashId))
        }
    }

    return {
        focusSide = normalizedFocus,
        focused = sections[normalizedFocus],
        paired = sections[normalizedFocus == 'main' and 'loadout' or 'main'],
        main = sections.main,
        loadout = sections.loadout,
        transferSupport = {
            mode = 'full_stack',
            splitStackReady = true,
            splitStackEnabled = true,
            helperText = 'Sol tık sürükle-bırak ile aynı itemleri birleştirebilir, sağ tık ile yığından parça ayırabilirsin. Silahlar hiçbir durumda stacklenmez.'
        }
    }
end

local function GetArcAlivePlayers(bucketId)
    local alivePlayers = {}
    for _, playerId in ipairs(groupMembers[bucketId] or {}) do
        if not (eliminatedArcPlayers[bucketId] and eliminatedArcPlayers[bucketId][playerId]) then
            alivePlayers[#alivePlayers + 1] = playerId
        end
    end

    return alivePlayers
end

local function BuildArcExtractionClientState(bucketId)
    local extractionState = GetArcExtractionState(bucketId)
    if not extractionState then
        return nil
    end

    local resolvedBucketId = tonumber(bucketId)
    if not resolvedBucketId then
        return nil
    end

    local now = GetGameTimer()
    local availableInMs = 0
    local remainingMs = 0
    if extractionState.availableAt and extractionState.availableAt > now then
        availableInMs = extractionState.availableAt - now
    end
    if extractionState.phaseEndsAt and extractionState.phaseEndsAt > now then
        remainingMs = extractionState.phaseEndsAt - now
    end

    return {
        enabled = true,
        bucketId = resolvedBucketId,
        phase = extractionState.phase or 'idle',
        phaseLabel = GetArcExtractionPhaseLabel(extractionState.phase),
        zone = extractionState.zone,
        zones = extractionState.zones or {},
        objective = BuildArcExtractionObjectiveText(extractionState),
        availableInMs = availableInMs,
        remainingMs = remainingMs,
        calledBy = extractionState.callerName,
        allowSoloExtract = extractionState.allowSoloExtract ~= false,
        allowPartialTeamExtract = extractionState.allowPartialTeamExtract ~= false,
        requireFullTeam = extractionState.requireFullTeam == true,
        zoneRadius = tonumber(extractionState.zoneRadius or 0.0) or 0.0,
        callDelay = math.floor((tonumber(extractionState.callDelayMs or 0) or 0) / 1000),
        readyWindow = math.floor((tonumber(extractionState.readyWindowMs or 0) or 0) / 1000),
        manualDepartureCountdown = math.floor((tonumber(extractionState.manualDepartureCountdownMs or 0) or 0) / 1000),
        boardingInterruptOnLeave = extractionState.boardingInterruptOnLeave ~= false,
        cancelIfZoneEmpty = extractionState.cancelIfZoneEmpty == true,
        manualDepartureEnabled = extractionState.manualDepartureEnabled ~= false,
        autoDepartureOnTimeout = extractionState.autoDepartureOnTimeout ~= false,
        spawnHelicopter = extractionState.spawnHelicopter == true,
        useHelicopterScene = extractionState.useHelicopterScene ~= false,
        helicopterModel = extractionState.helicopterModel,
        helicopterHeight = tonumber(extractionState.helicopterHeight or 80.0) or 80.0,
        departurePending = extractionState.departurePending == true,
        results = extractionState.results or {}
    }
end

local function SyncArcExtractionState(bucketId, notifyPayload)
    local clientState = BuildArcExtractionClientState(bucketId)
    if not clientState then
        return
    end

    for _, playerId in ipairs(groupMembers[bucketId] or {}) do
        TriggerClientEvent('gs-survival:client:updateArcExtractionState', playerId, clientState, notifyPayload)
    end
end

local function SetArcExtractionPhase(bucketId, phase, durationMs, overrides)
    local extractionState = GetArcExtractionState(bucketId)
    if not extractionState then
        return nil
    end

    local now = GetGameTimer()
    extractionState.phase = phase
    extractionState.phaseChangedAt = now
    extractionState.phaseEndsAt = durationMs and durationMs > 0 and (now + durationMs) or 0

    if overrides then
        for key, value in pairs(overrides) do
            extractionState[key] = value
        end
    end

    if phase == 'available' then
        extractionState.calledBy = nil
        extractionState.callerName = nil
        extractionState.departurePending = false
        extractionState.departureTriggeredBy = nil
        extractionState.departureTriggeredName = nil
        extractionState.boardingPlayers = {}
        extractionState.phaseEndsAt = 0
    elseif phase == 'ready' then
        extractionState.boardingPlayers = {}
        if extractionState.departurePending ~= true then
            extractionState.departureTriggeredBy = nil
            extractionState.departureTriggeredName = nil
        end
    elseif phase == 'cleaned' then
        extractionState.calledBy = nil
        extractionState.callerName = nil
        extractionState.departurePending = false
        extractionState.departureTriggeredBy = nil
        extractionState.departureTriggeredName = nil
        extractionState.boardingPlayers = {}
    end

    return extractionState
end

local function BuildArcExtractionZones()
    local zones = {}
    local zoneLookup = {}
    local deploymentZones = (Config.ArcPvP and Config.ArcPvP.DeploymentZones) or {}
    local extractionConfig = GetArcExtractionConfig()
    local configuredZones = extractionConfig.Zones or {}

    local function addZone(zoneId, label, coords, heading)
        local zoneCoords = ToVector3(coords)
        if not zoneCoords then
            return
        end

        local zoneKey = tostring(zoneId)
        if zoneLookup[zoneKey] then
            return
        end

        zoneLookup[zoneKey] = true
        zones[#zones + 1] = {
            id = zoneKey,
            label = label or "Tahliye",
            coords = Vector3ToTable(zoneCoords),
            heading = tonumber(heading or 0.0) or 0.0
        }
    end

    local deploymentZoneIds = {}
    for zoneId in pairs(deploymentZones) do
        if type(zoneId) == 'number' then
            deploymentZoneIds[#deploymentZoneIds + 1] = zoneId
        end
    end
    table.sort(deploymentZoneIds)

    for _, zoneId in ipairs(deploymentZoneIds) do
        local zone = deploymentZones[zoneId]
        addZone(("deployment_%s"):format(zoneId), zone and zone.label or ("Tahliye " .. tostring(zoneId)), zone and zone.extractionPoint, 0.0)
    end

    for index, zone in ipairs(configuredZones) do
        local coords = ToVector3(zone and zone.coords)
        if coords then
            addZone(zone and zone.id or ("config_%s"):format(index), zone and zone.label or ("Tahliye " .. tostring(index)), coords, zone and zone.heading)
        end
    end

    if #zones == 0 then
        return nil
    end

    return zones
end

local function IsArcActivePlayer(bucketId, playerId)
    for _, memberId in ipairs(groupMembers[bucketId] or {}) do
        if tonumber(memberId) == tonumber(playerId) then
            return not (eliminatedArcPlayers[bucketId] and eliminatedArcPlayers[bucketId][playerId])
        end
    end

    return false
end

local function CountArcBarricades(bucketId, ownerId)
    local totalCount = 0
    local ownerCount = 0

    for _, barricadeState in pairs(arcPlacedBarricades[bucketId] or {}) do
        totalCount = totalCount + 1
        if ownerId and tonumber(barricadeState.ownerId) == tonumber(ownerId) then
            ownerCount = ownerCount + 1
        end
    end

    return totalCount, ownerCount
end

local function SyncArcBarricadesToPlayer(playerId, bucketId)
    local barricades = {}

    for barricadeId, barricadeState in pairs(arcPlacedBarricades[bucketId] or {}) do
        local clientState = BuildArcBarricadeClientState(barricadeId, barricadeState)
        if clientState then
            barricades[#barricades + 1] = clientState
        end
    end

    TriggerClientEvent('gs-survival:client:syncArcBarricades', playerId, barricades)
end

local function BroadcastArcBarricade(bucketId, barricadeId)
    local clientState = BuildArcBarricadeClientState(barricadeId, arcPlacedBarricades[bucketId] and arcPlacedBarricades[bucketId][barricadeId])
    if not clientState then
        return
    end

    for _, playerId in ipairs(groupMembers[bucketId] or {}) do
        TriggerClientEvent('gs-survival:client:spawnArcBarricade', playerId, clientState)
    end
end

local function BroadcastArcBarricadeRemoval(bucketId, barricadeId)
    for _, playerId in ipairs(groupMembers[bucketId] or {}) do
        TriggerClientEvent('gs-survival:client:removeArcBarricade', playerId, barricadeId)
    end
end

local function GetArcPlayersInsideExtractionZone(bucketId)
    local extractionState = GetArcExtractionState(bucketId)
    local zoneRadius = tonumber(extractionState and extractionState.zoneRadius or 0.0) or 0.0
    local insidePlayers = {}

    if zoneRadius <= 0.0 then
        return insidePlayers
    end

    for _, playerId in ipairs(GetArcAlivePlayers(bucketId)) do
        local ped = GetPlayerPed(playerId)
        if ped ~= 0 then
            local playerCoords = GetEntityCoords(ped)
            local matchedZone = FindArcExtractionZone(bucketId, playerCoords, 0.0, extractionState and extractionState.zone and extractionState.zone.id or nil)
            if matchedZone then
                insidePlayers[#insidePlayers + 1] = playerId
            end
        end
    end

    return insidePlayers
end

local function GetArcSpawnValidationPlayers(bucketId)
    local scopedPlayers = {}
    local scopedLookup = {}

    if not bucketId or ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
        return scopedPlayers
    end

    for _, playerId in ipairs(groupMembers[bucketId] or {}) do
        local scopedId = tonumber(playerId)
        if scopedId and not scopedLookup[scopedId] then
            scopedLookup[scopedId] = true
            scopedPlayers[#scopedPlayers + 1] = scopedId
        end
    end

    return scopedPlayers
end

local function SelectArcInsertionPoint(zoneData, bucketId)
    local insertionPoints = zoneData and zoneData.insertionPoints or {}
    if #insertionPoints == 0 then
        return nil, "ARC insertion noktası bulunamadı."
    end

    local spawnClearRadius = tonumber((Config.ArcPvP and Config.ArcPvP.SpawnClearRadius) or 125.0)
    local minInsertionLootDistance = math.max(0.0, tonumber((Config.ArcPvP and Config.ArcPvP.MinInsertionLootDistance) or 18.0))
    local bestPreferredInsertionPoint = nil
    local bestPreferredInsertionDistance = -1.0
    local bestFallbackInsertionPoint = nil
    local bestFallbackInsertionDistance = -1.0
    local bestRelaxedPreferredInsertionPoint = nil
    local bestRelaxedPreferredInsertionDistance = -1.0
    local bestRelaxedFallbackInsertionPoint = nil
    local bestRelaxedFallbackInsertionDistance = -1.0
    local scopedPlayers = GetArcSpawnValidationPlayers(bucketId)

    for _, point in ipairs(insertionPoints) do
        if point then
            local isClear = true

            for _, playerId in ipairs(scopedPlayers) do
                local ped = GetPlayerPed(playerId)
                if ped ~= 0 then
                    local playerCoords = GetEntityCoords(ped)
                    if #(playerCoords - point) < spawnClearRadius then
                        isClear = false
                        break
                    end
                end
            end

            local closestLootDistance = math.huge
            local hasLootNodes = false
            for _, lootNode in ipairs(zoneData.lootNodes or {}) do
                local lootCoords = lootNode and ToVector3(lootNode.coords)
                if lootCoords then
                    hasLootNodes = true
                    closestLootDistance = math.min(closestLootDistance, #(lootCoords - point))
                end
            end
            local isLootDistanceSufficient = (not hasLootNodes) or closestLootDistance >= minInsertionLootDistance

            if closestLootDistance > bestRelaxedFallbackInsertionDistance then
                bestRelaxedFallbackInsertionDistance = closestLootDistance
                bestRelaxedFallbackInsertionPoint = point
            end

            if isClear and closestLootDistance > bestRelaxedPreferredInsertionDistance then
                bestRelaxedPreferredInsertionDistance = closestLootDistance
                bestRelaxedPreferredInsertionPoint = point
            end

            if isLootDistanceSufficient and closestLootDistance > bestFallbackInsertionDistance then
                bestFallbackInsertionDistance = closestLootDistance
                bestFallbackInsertionPoint = point
            end

            if isClear and isLootDistanceSufficient and closestLootDistance > bestPreferredInsertionDistance then
                bestPreferredInsertionDistance = closestLootDistance
                bestPreferredInsertionPoint = point
            end
        end
    end

    local insertionPoint = bestPreferredInsertionPoint
        or bestFallbackInsertionPoint
        or bestRelaxedPreferredInsertionPoint
        or bestRelaxedFallbackInsertionPoint

    if not insertionPoint then
        return nil, "ARC insertion noktası bulunamadı."
    end

    return insertionPoint
end

local function GetArcRaidParticipantKey(playerId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    local citizenId = Player and Player.PlayerData and Player.PlayerData.citizenid or nil
    if citizenId and citizenId ~= '' then
        return tostring(citizenId)
    end

    local resolvedPlayerId = tonumber(playerId)
    if resolvedPlayerId then
        return ('src:%s'):format(resolvedPlayerId)
    end

    return playerId and tostring(playerId) or nil
end

local function HasArcRaidParticipant(bucketId, playerId)
    local participantKey = GetArcRaidParticipantKey(playerId)
    return (participantKey ~= nil and arcRaidParticipants[bucketId] and arcRaidParticipants[bucketId][participantKey] == true) or false
end

local function TrackArcRaidParticipants(bucketId, playerIds)
    if not bucketId then
        return
    end

    arcRaidParticipants[bucketId] = arcRaidParticipants[bucketId] or {}

    for _, playerId in ipairs(playerIds or {}) do
        local participantKey = GetArcRaidParticipantKey(playerId)
        if participantKey then
            arcRaidParticipants[bucketId][participantKey] = true
        end
    end
end

local function GetArcSessionPlayerKey(playerId, citizenId)
    if citizenId ~= nil and citizenId ~= '' then
        return tostring(citizenId)
    end

    return GetArcRaidParticipantKey(playerId)
end

local function EnsureArcSessionAdmissionState(bucketId)
    if not bucketId then
        return nil
    end

    arcSessionAdmission[bucketId] = arcSessionAdmission[bucketId] or {
        acceptingNewSquads = true,
        backfillEligible = true,
        phase = 'active',
        reason = nil
    }
    arcSessionEliminations[bucketId] = arcSessionEliminations[bucketId] or {}
    arcSessionExtractions[bucketId] = arcSessionExtractions[bucketId] or {}
    arcSessionDisconnects[bucketId] = arcSessionDisconnects[bucketId] or {}

    return arcSessionAdmission[bucketId]
end

local function MarkArcSessionPlayerHistory(bucketTable, bucketId, playerId, citizenId, state)
    if not bucketId then
        return
    end

    local playerKey = GetArcSessionPlayerKey(playerId, citizenId)
    if not playerKey then
        return
    end

    bucketTable[bucketId] = bucketTable[bucketId] or {}
    bucketTable[bucketId][playerKey] = state or {
        at = os.time()
    }
end

local function ClearArcSessionPlayerHistory(bucketTable, bucketId, playerId, citizenId)
    local playerKey = GetArcSessionPlayerKey(playerId, citizenId)
    if playerKey and bucketTable[bucketId] then
        bucketTable[bucketId][playerKey] = nil
    end
end

local function GetArcSessionPlayerHistory(bucketTable, bucketId, playerId, citizenId)
    local playerKey = GetArcSessionPlayerKey(playerId, citizenId)
    return playerKey and bucketTable[bucketId] and bucketTable[bucketId][playerKey] or nil
end

local function HasPlayerBeenEliminatedInArcSession(bucketId, playerId, citizenId)
    return GetArcSessionPlayerHistory(arcSessionEliminations, bucketId, playerId, citizenId) ~= nil
end

local function HasPlayerExtractedFromArcSession(bucketId, playerId, citizenId)
    return GetArcSessionPlayerHistory(arcSessionExtractions, bucketId, playerId, citizenId) ~= nil
end

local function HasPlayerDisconnectedFromArcSession(bucketId, playerId, citizenId)
    return GetArcSessionPlayerHistory(arcSessionDisconnects, bucketId, playerId, citizenId) ~= nil
end

local function GetArcPendingReconnectCount(bucketId)
    local resolvedBucketId = tonumber(bucketId)
    if not resolvedBucketId or resolvedBucketId == 0 then
        return 0
    end

    local cachedCount = tonumber(arcPendingReconnectCounts[resolvedBucketId])
    if cachedCount then
        return math.max(0, cachedCount)
    end

    local pendingCount = 0
    for _, disconnectState in pairs(arcDisconnectStates) do
        if disconnectState
            and tonumber(disconnectState.bucketId) == resolvedBucketId
            and disconnectState.allowRejoin == true
            and disconnectState.resolved ~= true then
            pendingCount = pendingCount + 1
        end
    end

    if pendingCount > 0 then
        arcPendingReconnectCounts[resolvedBucketId] = pendingCount
    end

    return pendingCount
end

local function RefreshArcSessionAdmissionState(bucketId)
    local raidState = arcRaidState[bucketId]
    local admissionState = EnsureArcSessionAdmissionState(bucketId)
    if not raidState or not admissionState then
        return nil
    end

    local now = GetGameTimer()
    local settings = GetArcAdmissionSettings()
    local remainingSeconds = math.floor(GetArcRaidRemainingMs(bucketId) / 1000)
    local elapsedSeconds = math.max(0, math.floor((now - (tonumber(raidState.startedAt) or now)) / 1000))
    local extractionState = GetArcExtractionState(bucketId)
    local extractionUnlocked = extractionState and now >= tonumber(extractionState.availableAt or 0) or false
    local phase = extractionState and tostring(extractionState.phase or 'active') or 'active'
    local reason = nil
    local acceptingNewSquads = true

    if arcFinalizeLocks[bucketId] then
        acceptingNewSquads = false
        reason = 'finalizing'
    elseif not groupMembers[bucketId] then
        acceptingNewSquads = false
        reason = 'missing_members'
    elseif #GetArcAlivePlayers(bucketId) == 0 then
        acceptingNewSquads = false
        reason = 'no_alive_players'
    elseif settings.minimumRemainingSecondsForBackfill > 0 and remainingSeconds < settings.minimumRemainingSecondsForBackfill then
        acceptingNewSquads = false
        reason = 'remaining_time'
    elseif settings.lateJoinCutoffSeconds > 0 and elapsedSeconds >= settings.lateJoinCutoffSeconds then
        acceptingNewSquads = false
        reason = 'late_phase'
    elseif extractionUnlocked and not settings.allowJoinAfterExtractionUnlocked then
        acceptingNewSquads = false
        reason = 'extraction_unlocked'
    end

    admissionState.acceptingNewSquads = acceptingNewSquads
    admissionState.backfillEligible = acceptingNewSquads
    admissionState.phase = phase
    admissionState.reason = reason
    admissionState.remainingSeconds = remainingSeconds
    admissionState.extractionUnlocked = extractionUnlocked

    return admissionState
end

local function IsArcSessionJoinable(bucketId, incomingPlayerIds, options)
    options = options or {}

    if ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
        return false, 'invalid_mode'
    end

    local members = groupMembers[bucketId]
    local raidState = arcRaidState[bucketId]
    if not members or not raidState or not raidState.deployment then
        return false, 'inactive_session'
    end

    local admissionState = RefreshArcSessionAdmissionState(bucketId)
    if not admissionState or admissionState.acceptingNewSquads ~= true then
        return false, admissionState and admissionState.reason or 'inactive_session'
    end

    local maxRaidPlayers = ServerHelpers.GetArcRaidMaxPlayers()
    local incomingCount = #(incomingPlayerIds or {})
    if maxRaidPlayers and (ServerHelpers.GetArcRaidPopulation(bucketId) + incomingCount) > maxRaidPlayers then
        return false, 'session_full'
    end

    local settings = GetArcAdmissionSettings()
    for _, playerId in ipairs(incomingPlayerIds or {}) do
        if HasPlayerExtractedFromArcSession(bucketId, playerId) then
            return false, 'already_extracted'
        end

        if settings.denyJoinIfSquadPreviouslyEliminated and HasPlayerBeenEliminatedInArcSession(bucketId, playerId) then
            return false, 'already_eliminated'
        end

        if HasArcRaidParticipant(bucketId, playerId) or ServerHelpers.IsPlayerInList(members, playerId) then
            return false, 'already_participant'
        end
    end

    return true
end

local function FindBestArcSessionForLobby(incomingPlayerIds, playerLevel)
    local settings = GetArcAdmissionSettings()
    local candidates = {}

    for bucketId, modeId in pairs(bucketModes) do
        if ServerHelpers.GetGameModeId(modeId) == 'arc_pvp' then
            local joinable, denyReason = IsArcSessionJoinable(bucketId, incomingPlayerIds, {
                playerLevel = playerLevel
            })
            if joinable then
                candidates[#candidates + 1] = {
                    bucketId = bucketId,
                    remainingMs = GetArcRaidRemainingMs(bucketId),
                    population = ServerHelpers.GetArcRaidPopulation(bucketId)
                }
            elseif denyReason then
                RefreshArcSessionAdmissionState(bucketId)
            end
        end
    end

    table.sort(candidates, function(a, b)
        if settings.sessionReuseStrategy == 'least_population' and a.population ~= b.population then
            return a.population < b.population
        end

        if a.remainingMs ~= b.remainingMs then
            return a.remainingMs > b.remainingMs
        end

        if a.population ~= b.population then
            return a.population < b.population
        end

        return tonumber(a.bucketId) < tonumber(b.bucketId)
    end)

    return candidates[1] and candidates[1].bucketId or nil
end

local function CanLobbyJoinArcSession(incomingPlayerIds, playerLevel)
    local playerLookup = {}

    for _, playerId in ipairs(incomingPlayerIds or {}) do
        local resolvedPlayerId = tonumber(playerId)
        if not resolvedPlayerId then
            return false, "ARC katılım doğrulaması başarısız: geçersiz oyuncu."
        end

        if playerLookup[resolvedPlayerId] then
            return false, "ARC katılım doğrulaması başarısız: aynı oyuncu birden fazla kez gönderildi."
        end

        playerLookup[resolvedPlayerId] = true
    end

    local reusableBucketId = FindBestArcSessionForLobby(incomingPlayerIds, playerLevel)
    return true, {
        bucketId = reusableBucketId,
        joinExisting = reusableBucketId ~= nil,
        shouldCreateNew = reusableBucketId == nil
    }
end

local function CanPlayerRejoinArcSession(bucketId, playerId, citizenId)
    local disconnectState = citizenId and arcDisconnectStates[citizenId] or nil
    if not disconnectState or disconnectState.allowRejoin ~= true then
        return false, "Bu oyuncu için aktif ARC yeniden bağlanma kaydı yok."
    end

    if tonumber(disconnectState.bucketId) ~= tonumber(bucketId) then
        return false, "ARC yeniden bağlanma kaydı başka bir oturuma ait."
    end

    if ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' or not arcRaidState[bucketId] then
        return false, "Eski ARC oturumu artık aktif değil."
    end

    if arcFinalizeLocks[bucketId] or GetArcRaidRemainingMs(bucketId) <= 0 then
        return false, "ARC oturumu kapanış aşamasına girdiği için geri dönüş reddedildi."
    end

    if HasPlayerBeenEliminatedInArcSession(bucketId, playerId, citizenId) then
        return false, "Bu ARC oturumunda daha önce elendiğin için geri dönemezsin."
    end

    if HasPlayerExtractedFromArcSession(bucketId, playerId, citizenId) then
        return false, "Bu ARC oturumundan zaten tahliye oldun."
    end

    if not HasPlayerDisconnectedFromArcSession(bucketId, playerId, citizenId) then
        return false, "Bu ARC oturumu için aktif bir bağlantı kopma kaydı bulunamadı."
    end

    if not HasArcRaidParticipant(bucketId, playerId) then
        return false, "Bu ARC oturumu için katılımcı kaydı bulunamadı."
    end

    if ServerHelpers.IsPlayerInList(groupMembers[bucketId] or {}, playerId) then
        return false, "Bu ARC oturumuna zaten bağlısın."
    end

    local maxRaidPlayers = ServerHelpers.GetArcRaidMaxPlayers()
    if maxRaidPlayers and (ServerHelpers.GetArcRaidPopulation(bucketId) + 1) > maxRaidPlayers then
        return false, "ARC oturumu dolduğu için geri dönüş reddedildi."
    end

    return true
end

local function CleanupArcSessionIfAbandoned(bucketId)
    if not bucketId or ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' or not arcRaidState[bucketId] then
        return false
    end

    if GetArcPendingReconnectCount(bucketId) > 0 then
        return false
    end

    if groupMembers[bucketId] and #groupMembers[bucketId] > 0 then
        if #GetArcAlivePlayers(bucketId) == 0 then
            FinalizeArcMatch(bucketId, {}, 'disconnect')
            return true
        end

        return false
    end

    CleanupArcExtraction(bucketId)
    CleanBucketEntities(bucketId)
    ResetBucketState(bucketId)
    return true
end

local function BuildArcDeploymentState(stageData, stageId, bucketId)
    local deploymentZones = (Config.ArcPvP and Config.ArcPvP.DeploymentZones) or {}
    local availableZones = {}

    local availableZoneIds = {}
    for zoneId, zone in pairs(deploymentZones) do
        if type(zoneId) == 'number' and zone and zone.center and zone.insertionPoints and zone.lootNodes then
            availableZoneIds[#availableZoneIds + 1] = zoneId
        end
    end
    table.sort(availableZoneIds)

    for _, zoneId in ipairs(availableZoneIds) do
        availableZones[#availableZones + 1] = zoneId
    end

    if #availableZones == 0 then
        return nil, "ARC deployment bölgeleri ayarlanmamış."
    end

    local selectedZoneId = availableZones[math.random(1, #availableZones)]
    local zoneData = deploymentZones[selectedZoneId]
    local insertionPoint, insertionError = SelectArcInsertionPoint(zoneData, bucketId)
    if not insertionPoint then
        return nil, insertionError or "ARC insertion noktası bulunamadı."
    end
    local lootNodes = {}
    local deploymentCenter = zoneData.center
    local selectedZoneLootRegion = NormalizeArcLootRegionId(zoneData.lootRegion)
    local allLootNodes = {}

    for _, mappedZoneId in ipairs(availableZoneIds) do
        local mappedZoneData = deploymentZones[mappedZoneId]
        local mappedZoneLootRegion = NormalizeArcLootRegionId(mappedZoneData and mappedZoneData.lootRegion)
        for nodeIndex, node in ipairs((mappedZoneData and mappedZoneData.lootNodes) or {}) do
            if node and node.coords then
                allLootNodes[#allLootNodes + 1] = {
                    zoneId = mappedZoneId,
                    nodeIndex = nodeIndex,
                    node = node,
                    lootRegion = mappedZoneLootRegion or selectedZoneLootRegion
                }
            end
        end
    end

    for _, nodeEntry in ipairs(allLootNodes) do
        local node = nodeEntry and nodeEntry.node
        if node and node.coords then
            local containerType = node.type or 'chest'
            lootNodes[#lootNodes + 1] = {
                id = ("zone_%s_node_%s"):format(nodeEntry.zoneId, nodeEntry.nodeIndex),
                coords = Vector3ToTable(node.coords),
                label = node.label or (containerType == 'drop' and "Sinyal Dropu" or "Alan Kutusu"),
                rollCount = tonumber(node.rollCount or (containerType == 'drop' and 2 or 1)) or 1,
                type = containerType,
                lootRegion = nodeEntry.lootRegion or selectedZoneLootRegion
            }
        end
    end

    return {
        stageId = 1,
        stageLabel = "ARC Baskını",
        zoneId = selectedZoneId,
        zoneLabel = zoneData.label or "Baskın Bölgesi",
        lootRegion = selectedZoneLootRegion,
        center = Vector3ToTable(deploymentCenter),
        insertion = Vector3ToTable(insertionPoint),
        extractionPoint = Vector3ToTable(zoneData.extractionPoint),
        lootNodes = lootNodes,
        raidDurationMs = (tonumber(Config.ArcPvP and Config.ArcPvP.RaidDurationSeconds or 1800) or 1800) * 1000
    }
end

local function BuildArcJoinDeploymentPayload(bucketId)
    local deploymentState = BuildArcDeploymentPayload(bucketId)
    if not deploymentState then
        return nil
    end

    local deploymentZones = (Config.ArcPvP and Config.ArcPvP.DeploymentZones) or {}
    local zoneData = deploymentZones[tonumber(deploymentState.zoneId) or deploymentState.zoneId]
    local insertionPoint = zoneData and SelectArcInsertionPoint(zoneData, bucketId) or nil
    if insertionPoint then
        deploymentState.insertion = Vector3ToTable(insertionPoint)
    end

    return deploymentState
end

GetArcRaidRemainingMs = function(bucketId)
    local raidState = arcRaidState[bucketId]
    if not raidState then
        return 0
    end

    return math.max(0, (tonumber(raidState.endsAt or 0) or 0) - GetGameTimer())
end

local function GetArcRaidStageId(bucketId)
    local raidState = arcRaidState[bucketId]
    return tonumber((raidState and raidState.deployment and raidState.deployment.stageId) or lobbyStage[bucketId] or 1) or 1
end

local function FinalizeArcExtractionResult(source, resultType, bucketId)
    local raidState = bucketId and arcRaidState[bucketId] or nil
    if not raidState then
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    local citizenId = Player and Player.PlayerData and Player.PlayerData.citizenid or nil

    raidState.resultLedger = raidState.resultLedger or {}
    raidState.resultLedger[tonumber(source) or source] = {
        type = tostring(resultType or 'unknown'),
        at = os.time()
    }

    local extractionState = raidState.extraction
    if extractionState then
        extractionState.results = extractionState.results or {}
        extractionState.results[tonumber(source) or source] = tostring(resultType or 'unknown')
    end

    local resolvedResultType = tostring(resultType or 'unknown')
    EnsureArcSessionAdmissionState(bucketId)
    if resolvedResultType == 'died' then
        MarkArcSessionPlayerHistory(arcSessionEliminations, bucketId, source, citizenId)
        ClearArcSessionPlayerHistory(arcSessionDisconnects, bucketId, source, citizenId)
    elseif resolvedResultType == 'extracted' then
        MarkArcSessionPlayerHistory(arcSessionExtractions, bucketId, source, citizenId)
        ClearArcSessionPlayerHistory(arcSessionDisconnects, bucketId, source, citizenId)
    elseif resolvedResultType == 'disconnected' then
        MarkArcSessionPlayerHistory(arcSessionDisconnects, bucketId, source, citizenId)
    end
end

local function BuildArcExtractionDisconnectState(bucketId)
    local extractionState = BuildArcExtractionClientState(bucketId)
    if not extractionState then
        return nil
    end

    return {
        phase = extractionState.phase,
        phaseLabel = extractionState.phaseLabel,
        objective = extractionState.objective,
        zone = extractionState.zone
    }
end

local function InitializeArcExtractionState(bucketId)
    if not IsArcExtractionEnabled() or not arcRaidState[bucketId] then
        return
    end

    local raidState = arcRaidState[bucketId]
    local extractionSettings = GetArcExtractionSettings()
    local now = raidState.startedAt or GetGameTimer()
    local zones = BuildArcExtractionZones()
    if not zones or #zones == 0 then
        return
    end

    local unlockMode = extractionSettings.unlockMode
    local unlockAt = now
    if unlockMode == 'always_available' then
        unlockAt = now
    elseif unlockMode == 'last_phase' then
        local fallbackLastPhaseSeconds = extractionSettings.lastPhaseUnlockSeconds
        if fallbackLastPhaseSeconds == nil then
            fallbackLastPhaseSeconds = extractionSettings.unlockAfterSeconds
        end
        local lastPhaseSeconds = tonumber(fallbackLastPhaseSeconds or 240) or 240
        unlockAt = math.max(now, (tonumber(raidState.endsAt or now) or now) - (lastPhaseSeconds * 1000))
    else
        local unlockAfterSeconds = extractionSettings.unlockAfterSeconds
        unlockAt = now + (unlockAfterSeconds * 1000)
    end

    local callDelayMs = extractionSettings.callDelaySeconds * 1000
    local callAckDelayMs = math.min(1500, math.max(0, callDelayMs))
    local inboundDelayMs = math.max(0, callDelayMs - callAckDelayMs)

    raidState.extraction = {
        enabled = true,
        phase = unlockMode == 'always_available' and 'available' or 'idle',
        zone = zones[1],
        zones = zones,
        unlockMode = unlockMode,
        availableAt = unlockAt,
        phaseChangedAt = now,
        phaseEndsAt = 0,
        zoneRadius = extractionSettings.zoneRadius,
        callDelayMs = callDelayMs,
        callAckDelayMs = callAckDelayMs,
        inboundDelayMs = inboundDelayMs,
        readyWindowMs = extractionSettings.readyWindowSeconds * 1000,
        manualDepartureCountdownMs = extractionSettings.manualDepartureCountdownSeconds * 1000,
        cleanupDelayMs = extractionSettings.cleanupDelayMs,
        requireFullTeam = extractionSettings.requireFullTeam,
        allowSoloExtract = extractionSettings.allowSoloExtract,
        allowPartialTeamExtract = extractionSettings.allowPartialTeamExtract,
        cancelIfZoneEmpty = extractionSettings.cancelIfZoneEmpty,
        boardingInterruptOnLeave = extractionSettings.boardingInterruptOnLeave,
        autoFailIfNoExtract = extractionSettings.autoFailIfNoExtract,
        manualDepartureEnabled = extractionSettings.manualDepartureEnabled,
        autoDepartureOnTimeout = extractionSettings.autoDepartureOnTimeout,
        notifyAllPlayers = extractionSettings.notifyAllPlayers,
        spawnHelicopter = extractionSettings.spawnHelicopter,
        useHelicopterScene = extractionSettings.useHelicopterScene,
        helicopterModel = extractionSettings.helicopterModel,
        helicopterHeight = extractionSettings.helicopterHeight,
        departurePending = false,
        departureTriggeredBy = nil,
        departureTriggeredName = nil,
        boardingPlayers = {},
        results = {}
    }
end

local function BuildArcRuntimeLootNodes(bucketId)
    local raidState = arcRaidState[bucketId]
    local deployment = raidState and raidState.deployment or nil
    local openedContainers = openedArcContainers[bucketId] or {}
    local deathContainers = arcDeathContainers[bucketId] or {}
    local runtimeNodes = {}
    local knownNodeIds = {}

    for _, node in ipairs((deployment and deployment.lootNodes) or {}) do
        local containerState = node.id and openedContainers[node.id]
        if not (containerState and containerState.consumed) then
            runtimeNodes[#runtimeNodes + 1] = {
                id = node.id,
                coords = node.coords,
                label = node.label,
                rollCount = tonumber(node.rollCount or 1) or 1,
                type = node.type or 'chest',
                lootRegion = node.lootRegion
            }
        end

        if node.id then
            knownNodeIds[node.id] = true
        end
    end

    for containerId, containerState in pairs(openedContainers) do
        if not knownNodeIds[containerId] and containerState and containerState.consumed ~= true and containerState.coords then
            runtimeNodes[#runtimeNodes + 1] = {
                id = containerId,
                coords = containerState.coords,
                label = containerState.label or 'Arc Loot',
                rollCount = tonumber(containerState.rollCount or 1) or 1,
                type = containerState.type or 'drop'
            }
        end
    end

    for containerId, containerState in pairs(deathContainers) do
        if containerState and containerState.consumed ~= true and containerState.coords then
            runtimeNodes[#runtimeNodes + 1] = {
                id = containerId,
                coords = containerState.coords,
                label = containerState.label or 'Arc Ölüm Kutusu',
                rollCount = tonumber(containerState.rollCount or 1) or 1,
                type = containerState.type or 'death_drop',
                openEvent = 'gs-survival:server:openArcDeathContainer'
            }
        end
    end

    table.sort(runtimeNodes, function(a, b)
        return tostring(a.id or '') < tostring(b.id or '')
    end)

    return runtimeNodes
end

BuildArcDeploymentPayload = function(bucketId)
    local raidState = arcRaidState[bucketId]
    local deployment = raidState and raidState.deployment or nil
    if not deployment then
        return nil
    end

    return {
        stageId = deployment.stageId,
        stageLabel = deployment.stageLabel,
        zoneId = deployment.zoneId,
        zoneLabel = deployment.zoneLabel,
        lootRegion = deployment.lootRegion,
        center = deployment.center,
        insertion = deployment.insertion,
        extractionPoint = deployment.extractionPoint,
        lootNodes = BuildArcRuntimeLootNodes(bucketId),
        raidDurationMs = GetArcRaidRemainingMs(bucketId),
        extraction = BuildArcExtractionClientState(bucketId)
    }
end

local function CleanupArcExtraction(bucketId, notifyPayload)
    local extractionState = GetArcExtractionState(bucketId)
    if not extractionState then
        return
    end

    SetArcExtractionPhase(bucketId, 'cleaned', extractionState.cleanupDelayMs, {
        boardingPlayers = {},
        callerName = nil,
        calledBy = nil
    })
    SyncArcExtractionState(bucketId, notifyPayload or {
        message = "Tahliye sahnesi kapatıldı. Saha durumu yeniden ayarlanıyor.",
        type = "primary"
    })
end

local function RemoveArcRaidPlayer(bucketId, playerId)
    local members = groupMembers[bucketId] or {}
    for index, memberId in ipairs(members) do
        if tonumber(memberId) == tonumber(playerId) then
            table.remove(members, index)
            break
        end
    end

    ServerHelpers.RemoveArcRaidSquadPlayer(bucketId, playerId)
    if arcRaidPlayerProfiles[bucketId] then
        arcRaidPlayerProfiles[bucketId][tonumber(playerId)] = nil
    end
    groupSizes[bucketId] = #members
    ServerHelpers.SetArcPlayerBucketIndex(playerId, nil)
end

local GetArcPlayerName
local TryCompletePlayerExtraction

local function StartArcExtractionCall(bucketId, callerSource, requestedZoneId)
    local extractionState = GetArcExtractionState(bucketId)
    if not extractionState or extractionState.phase ~= 'available' then
        return false, "Tahliye hattı henüz çağrılabilir değil."
    end

    if not IsArcActivePlayer(bucketId, callerSource) then
        return false, "Yalnızca hayatta kalan baskıncılar tahliye çağrısı yapabilir."
    end

    local playerPed = GetPlayerPed(callerSource)
    if playerPed == 0 then
        return false, "Tahliye alanı bulunamadı."
    end

    local playerCoords = GetEntityCoords(playerPed)
    local selectedZone = FindArcExtractionZone(bucketId, playerCoords, 3.0, requestedZoneId)
    if not selectedZone then
        return false, "Tahliye çağrısı için extraction alanına gir."
    end

    local callerName = GetArcPlayerName(callerSource)
    local resolvedBucketId = tonumber(bucketId)
    if not resolvedBucketId then
        return false, "Tahliye oturumu çözümlenemedi."
    end
    SetArcExtractionPhase(bucketId, 'called', extractionState.callAckDelayMs, {
        zone = selectedZone,
        calledBy = callerSource,
        callerName = callerName
    })
    for _, playerId in ipairs(groupMembers[bucketId] or {}) do
        if GetPlayerRoutingBucket(playerId) == resolvedBucketId then
            TriggerClientEvent('gs-survival:client:playSignalFlare', playerId, {
                bucketId = resolvedBucketId,
                coords = Vector3ToTable(ToVector3(selectedZone.coords))
            })
        end
    end
    SyncArcExtractionState(bucketId, {
        message = ("%s %s noktasından tahliye hattını açtı. Hava aracı rotaya alındı."):format(callerName, selectedZone.label or "tahliye noktası"),
        type = "primary"
    })

    return true
end

local function TryResolveArcExtractionDeparture(bucketId, departSource, isManualDeparture)
    local extractionState = GetArcExtractionState(bucketId)
    if not extractionState or extractionState.phase ~= 'ready' then
        return false, "Helikopter henüz kalkışa hazır değil."
    end
    local departurePending = extractionState.departurePending == true

    if isManualDeparture then
        if extractionState.manualDepartureEnabled == false then
            return false, "Manuel kalkış bu baskında kapalı."
        end
        if not IsArcActivePlayer(bucketId, departSource) then
            return false, "Yalnızca hayatta kalan baskıncılar kalkış başlatabilir."
        end

        local playerPed = GetPlayerPed(departSource)
        if playerPed == 0 then
            return false, "Kalkış için extraction alanında olman gerekiyor."
        end

        local playerCoords = GetEntityCoords(playerPed)
        local insideReadyZone = FindArcExtractionZone(bucketId, playerCoords, 0.0, extractionState.zone and extractionState.zone.id or nil)
        if not insideReadyZone then
            return false, "Manuel kalkış için extraction alanında durmalısın."
        end

        if extractionState.departurePending == true then
            return false, "Kalkış geri sayımı zaten başladı."
        end

        local departureCountdownMs = math.max(0, tonumber(extractionState.manualDepartureCountdownMs or 0) or 0)
        if departureCountdownMs > 0 then
            local starterName = GetArcPlayerName(departSource)
            SetArcExtractionPhase(bucketId, 'ready', departureCountdownMs, {
                departurePending = true,
                departureTriggeredBy = departSource,
                departureTriggeredName = starterName
            })
            SyncArcExtractionState(bucketId, {
                message = ("%s kalkış geri sayımını başlattı. %s saniye sonra tahliye alanındaki herkes tahliye edilecek."):format(starterName, tostring(math.floor(departureCountdownMs / 1000))),
                type = "primary"
            })
            return true, 0
        end
    end

    local departingPlayers = GetArcPlayersInsideExtractionZone(bucketId)
    local completed = 0
    for _, playerId in ipairs(departingPlayers) do
        if TryCompletePlayerExtraction(playerId, bucketId, { suppressStateNotify = true }) then
            completed = completed + 1
        end
    end

    if not arcRaidState[bucketId] then
        return true, completed
    end

    if completed > 0 and groupMembers[bucketId] and #groupMembers[bucketId] > 0 then
        local message
        if isManualDeparture then
            message = ("%s kalkışı başlattı. Bölgedeki %s operatif tahliye edildi."):format(GetArcPlayerName(departSource), tostring(completed))
        elseif departurePending then
            message = ("Kalkış geri sayımı tamamlandı. Bölgedeki %s operatif tahliye edildi."):format(tostring(completed))
        else
            message = ("Ready süresi doldu. Bölgedeki %s operatif otomatik olarak tahliye edildi."):format(tostring(completed))
        end
        CleanupArcExtraction(bucketId, {
            message = message,
            type = "success"
        })
    elseif completed == 0 then
        CleanupArcExtraction(bucketId, {
            message = isManualDeparture
                and "Kalkış tetiklendi ama o anda bölgede tahliye olacak yaşayan operatif yoktu."
                or (departurePending and "Kalkış geri sayımı bitti ancak tahliye alanında kimse yoktu. Helikopter boş kalktı.")
                or "Ready süresi doldu ancak tahliye alanında kimse yoktu. Helikopter boş kalktı.",
            type = isManualDeparture and "error" or "primary"
        })
    end

    return true, completed
end

GetArcPlayerName = function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    return Player and (Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname) or ("ID " .. tostring(source))
end

TryCompletePlayerExtraction = function(source, bucketId, options)
    options = options or {}
    if not IsArcActivePlayer(bucketId, source) then
        return false
    end

    FinalizeArcExtractionResult(source, 'extracted', bucketId)
    RestorePlayerInventory(source, true, 'arc_pvp')
    TriggerClientEvent('gs-survival:client:arcExtracted', source)
    TriggerClientEvent('gs-survival:client:stopEverything', source, true, 'arc_pvp')
    ServerHelpers.NotifyPlayer(source, "Tahliye başarılı. Baskın ekipmanın ana depoya aktarıldı.", "success")

    RemoveArcRaidPlayer(bucketId, source)
    eliminatedArcPlayers[bucketId] = eliminatedArcPlayers[bucketId] or {}
    eliminatedArcPlayers[bucketId][source] = nil

    if #groupMembers[bucketId] > 0 then
        SyncArcRaidPlayers(bucketId)
        if options.suppressStateNotify ~= true then
            SyncArcExtractionState(bucketId, {
                message = ("Takımdan bir operatif tahliye edildi. Sahadaki baskın devam ediyor."),
                type = "primary"
            })
        end
    else
        CleanupArcExtraction(bucketId)
        CleanBucketEntities(bucketId)
        ResetBucketState(bucketId)
    end

    return true
end

local function AdvanceArcExtractionPhase(bucketId)
    local extractionState = GetArcExtractionState(bucketId)
    if not extractionState or arcFinalizeLocks[bucketId] then
        return
    end

    local now = GetGameTimer()

    if extractionState.phase == 'idle' then
        if now >= (tonumber(extractionState.availableAt or 0) or 0) then
            SetArcExtractionPhase(bucketId, 'available', 0)
            SyncArcExtractionState(bucketId, {
                message = "Tahliye penceresi açıldı. Extraction alanına gidip airlift çağrısı yap.",
                type = "primary"
            })
        end
        return
    end

    if extractionState.phase == 'called' then
        if now >= tonumber(extractionState.phaseEndsAt or 0) then
            if tonumber(extractionState.inboundDelayMs or 0) > 0 then
                SetArcExtractionPhase(bucketId, 'inbound', extractionState.inboundDelayMs)
                SyncArcExtractionState(bucketId, {
                    message = "Airlift inbound. Bölgeye yaklaş ve iniş alanını tut.",
                    type = "primary"
                })
            else
                local manualCountdownSeconds = math.max(0, math.floor((tonumber(extractionState.manualDepartureCountdownMs or 0) or 0) / 1000))
                local readyPhaseTimeoutMs = tonumber(extractionState.readyWindowMs or 0) or 0
                SetArcExtractionPhase(bucketId, 'ready', readyPhaseTimeoutMs)
                SyncArcExtractionState(bucketId, {
                    message = extractionState.manualDepartureEnabled == false
                        and "Helikopter sahaya ulaştı. Tahliye alanında bekle; süre dolunca içeridekiler otomatik tahliye olacak."
                        or ("Helikopter sahaya ulaştı. Tahliye alanına gir; bir operatif E ile kalkış sayacını başlatırsa içeridekiler %s saniye sonra tahliye olacak, aksi halde %s saniye sonunda otomatik tahliye edilecek."):format(tostring(manualCountdownSeconds), tostring(math.floor(readyPhaseTimeoutMs / 1000))),
                    type = "success"
                })
            end
        end
        return
    end

    if extractionState.phase == 'inbound' then
        if now >= tonumber(extractionState.phaseEndsAt or 0) then
            local manualCountdownSeconds = math.max(0, math.floor((tonumber(extractionState.manualDepartureCountdownMs or 0) or 0) / 1000))
            local readyPhaseTimeoutMs = tonumber(extractionState.readyWindowMs or 0) or 0
            SetArcExtractionPhase(bucketId, 'ready', readyPhaseTimeoutMs)
            SyncArcExtractionState(bucketId, {
                message = extractionState.manualDepartureEnabled == false
                    and "Helikopter sahaya ulaştı. Tahliye alanında bekle; süre dolunca içeridekiler otomatik tahliye olacak."
                    or ("Helikopter sahaya ulaştı. Tahliye alanına gir; bir operatif E ile kalkış sayacını başlatırsa içeridekiler %s saniye sonra tahliye olacak, aksi halde %s saniye sonunda otomatik tahliye edilecek."):format(tostring(manualCountdownSeconds), tostring(math.floor(readyPhaseTimeoutMs / 1000))),
                type = "success"
            })
        end
        return
    end

    if extractionState.phase == 'ready' then
        local phaseEndsAt = tonumber(extractionState.phaseEndsAt or 0) or 0
        local readyExpired = (phaseEndsAt > 0) and (now >= phaseEndsAt)
        if extractionState.departurePending == true and readyExpired then
            TryResolveArcExtractionDeparture(bucketId, extractionState.departureTriggeredBy, false)
        elseif readyExpired and extractionState.autoDepartureOnTimeout ~= false then
            TryResolveArcExtractionDeparture(bucketId, nil, false)
        elseif readyExpired then
            CleanupArcExtraction(bucketId)
        end
        return
    end

    if extractionState.phase == 'cleaned' then
        if (tonumber(extractionState.phaseEndsAt or 0) or 0) > 0 and now >= (tonumber(extractionState.phaseEndsAt or 0) or 0) and groupMembers[bucketId] and #groupMembers[bucketId] > 0 then
            SetArcExtractionPhase(bucketId, 'available', 0)
            SyncArcExtractionState(bucketId, {
                message = "Yeni tahliye çağrısı için saha yeniden açıldı.",
                type = "primary"
            })
        end
    end
end

local function CanReuseArcRaid(bucketId, incomingPlayerIds, playerLevel)
    return IsArcSessionJoinable(bucketId, incomingPlayerIds, {
        playerLevel = playerLevel
    })
end

local function FindReusableArcRaidBucket(incomingPlayerIds, playerLevel)
    return FindBestArcSessionForLobby(incomingPlayerIds, playerLevel)
end

local function BuildArcPreparedLoadouts(playerIds)
    local preparedLoadouts = {}

    for _, playerId in ipairs(playerIds or {}) do
        local Player = QBCore.Functions.GetPlayer(playerId)
        if not Player then
            return nil, "Hazırlık verisi alınamadı."
        end

        local loadoutStashId = RegisterArcLoadoutStash(Player)
        local loadoutItems = NormalizeInventoryItems(exports.ox_inventory:GetInventoryItems(loadoutStashId))
        local loadoutState = BuildArcPrepState(Player).loadoutState

        if loadoutState.requiresPrepared and not loadoutState.isReady then
            return nil, "Baskın çantası boş. Bu baskın için önceden ekipman hazırlaman gerekiyor."
        end

        preparedLoadouts[playerId] = {
            stashId = loadoutStashId,
            items = loadoutItems,
            state = loadoutState
        }
    end

    return preparedLoadouts
end

local function FillArcLootStash(stashId, bonusRolls, lootRegionId)
    local lootTable = ResolveArcLootTable(lootRegionId)
    if type(lootTable) ~= 'table' or #lootTable == 0 then return end

    local addedCount = 0
    local totalRolls = math.max(1, tonumber(bonusRolls) or 1)

    for _ = 1, totalRolls do
        for _, loot in ipairs(lootTable) do
            local chance = tonumber(loot.chance or 0) or 0
            if math.random(1, 100) <= chance then
                local minAmount = tonumber(loot.min or 1) or 1
                local maxAmount = tonumber(loot.max or minAmount) or minAmount
                exports.ox_inventory:AddItem(stashId, loot.item, math.random(minAmount, maxAmount))
                addedCount = addedCount + 1
            end
        end
    end

    if addedCount == 0 then
        exports.ox_inventory:AddItem(stashId, "money", math.random(100, 300))
    end
end

local function GenerateBucketId()
    local attempts = 0

    while attempts < 90000 do
        if not groupMembers[nextBucketId] then
            local bucketId = nextBucketId
            nextBucketId = nextBucketId + 1
            if nextBucketId > 99999 then
                nextBucketId = 10000
            end
            return bucketId
        end

        nextBucketId = nextBucketId + 1
        if nextBucketId > 99999 then
            nextBucketId = 10000
        end
        attempts = attempts + 1
    end

    for _ = 1, 100 do
        local fallbackBucketId = math.random(100000, 999999)
        if not groupMembers[fallbackBucketId] then
            return fallbackBucketId
        end
    end

    error('No unique routing bucket id available for gs-survival match')
end

local function GenerateArcSessionKey(bucketId)
    return ("%s_%s_%s"):format(tostring(bucketId or 'arc'), os.time(), GetGameTimer())
end

local function GetArcSessionKey(bucketId)
    local raidState = bucketId and arcRaidState[bucketId] or nil
    return raidState and raidState.sessionKey or tostring(bucketId or 'global')
end

local function BuildArcLootStashId(bucketId, containerId)
    return ("arc_loot_%s_%s_%s"):format(tostring(bucketId), GetArcSessionKey(bucketId), tostring(containerId))
end

local function BuildArcDeathStashId(bucketId, containerId)
    return ("arc_death_%s_%s_%s"):format(tostring(bucketId), GetArcSessionKey(bucketId), tostring(containerId))
end

local function GetPlayerCoordsSafe(playerId)
    local ped = GetPlayerPed(playerId)
    if ped == 0 then
        return nil
    end

    return GetEntityCoords(ped)
end

local function IsPlayerNearCoords(playerId, coords, maxDistance)
    local playerCoords = GetPlayerCoordsSafe(playerId)
    local targetCoords = ToVector3(coords)
    if not playerCoords or not targetCoords then
        return false
    end

    return #(playerCoords - targetCoords) <= (tonumber(maxDistance) or 0.0)
end

local function IsPlayerWithinLobbyProximity(anchorId, targetId)
    local anchorCoords = GetPlayerCoordsSafe(anchorId)
    local targetCoords = GetPlayerCoordsSafe(targetId)
    if not anchorCoords or not targetCoords then
        return false
    end

    return #(anchorCoords - targetCoords) <= ARC_LOBBY_PROXIMITY_RADIUS
end

local function EnsureLobbyProximity(anchorId, targetId, targetName)
    if IsPlayerWithinLobbyProximity(anchorId, targetId) then
        return true
    end

    local resolvedName = tostring(targetName or "Bu oyuncu")
    return false, ("%s liderin yanında olmadığı için işlem reddedildi."):format(resolvedName)
end

local function BuildNearbyLobbyPlayers(leaderId)
    local nearbyPlayers = {}
    local normalizedLeaderId = tonumber(leaderId)
    if not normalizedLeaderId then
        return nearbyPlayers
    end

    for _, rawPlayerId in ipairs(GetPlayers()) do
        local playerId = tonumber(rawPlayerId)
        if playerId and playerId ~= normalizedLeaderId then
            local targetPlayer = QBCore.Functions.GetPlayer(playerId)
            if targetPlayer
                and GetPlayerRoutingBucket(playerId) == 0
                and not activeLobbies[playerId]
                and not ServerHelpers.FindLobbyLeaderByMember(playerId)
                and IsPlayerWithinLobbyProximity(normalizedLeaderId, playerId) then
                nearbyPlayers[#nearbyPlayers + 1] = {
                    id = playerId,
                    name = targetPlayer.PlayerData.charinfo.firstname .. " " .. targetPlayer.PlayerData.charinfo.lastname
                }
            end
        end
    end

    table.sort(nearbyPlayers, function(a, b)
        return tostring(a.name or '') < tostring(b.name or '')
    end)

    return nearbyPlayers
end
