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

local function BuildLootItemSet()
    lootItemSet = {}
    if Config and Config.LootTable then
        for _, loot in ipairs(Config.LootTable) do
            lootItemSet[loot.item] = true
        end
    end
end

BuildLootItemSet()

local function CountMembers(memberTable)
    local count = 0
    for _ in pairs(memberTable or {}) do
        count = count + 1
    end
    return count
end

local function IsPlayerInList(playerList, playerId)
    for _, listedPlayerId in ipairs(playerList or {}) do
        if tonumber(listedPlayerId) == tonumber(playerId) then
            return true
        end
    end

    return false
end

local function IsBucketMember(bucketId, playerId)
    if not bucketId or tonumber(bucketId) == 0 then
        return false
    end

    return IsPlayerInList(groupMembers[bucketId] or {}, playerId)
end

local function IsPedEntityDead(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return true
    end

    return GetEntityHealth(entity) <= 0
end

local function CountAliveBucketNpcs(bucketId)
    if not bucketId or bucketId == 0 then
        return 0
    end

    local aliveCount = 0
    for _, entity in ipairs(GetAllPeds()) do
        if GetEntityRoutingBucket(entity) == bucketId and not IsPedAPlayer(entity) and not IsPedEntityDead(entity) then
            aliveCount = aliveCount + 1
        end
    end

    return aliveCount
end

local function FindLobbyLeaderByMember(memberId)
    for leaderId, data in pairs(activeLobbies) do
        if data.members and data.members[memberId] then
            return leaderId
        end
    end

    return nil
end

local function GetGameMode(modeId)
    local gameModes = Config and Config.GameModes or {}
    return gameModes[modeId or 'classic'] or gameModes.classic
end

local function GetGameModeId(modeId)
    local gameMode = GetGameMode(modeId)
    return gameMode and gameMode.id or 'classic'
end

local function GetModeConfig(modeId)
    if GetGameModeId(modeId) == 'arc_pvp' then
        return Config.ArcPvP or {}
    end

    return Config.Survival or {}
end

local function GetArcConfig()
    return Config.ArcPvP or {}
end

local function GetArcRaidMaxPlayers()
    local configuredLimit = tonumber(GetArcConfig().MaxPlayersPerRaid)
    if not configuredLimit or configuredLimit <= 0 then
        return nil
    end

    return math.floor(configuredLimit)
end

local function GetArcRaidPopulation(bucketId)
    local members = groupMembers[bucketId] or {}
    return #members
end

local function EnsureArcRaidSquadState(bucketId)
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

local function CreateArcRaidSquad(bucketId, playerIds)
    local squadState = EnsureArcRaidSquadState(bucketId)
    if not squadState then
        return nil
    end

    local squadId = squadState.nextId
    squadState.nextId = squadId + 1

    local members = {}
    for _, playerId in ipairs(playerIds or {}) do
        local resolvedPlayerId = tonumber(playerId)
        if resolvedPlayerId and not IsPlayerInList(members, resolvedPlayerId) then
            members[#members + 1] = resolvedPlayerId
            squadState.playerMap[resolvedPlayerId] = squadId
        end
    end

    squadState.squads[squadId] = {
        members = members
    }

    return squadId
end

local function GetArcRaidSquadMembers(bucketId, playerId)
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

local function RemoveArcRaidSquadPlayer(bucketId, playerId)
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

local function AddArcRaidPlayerToSquad(bucketId, playerId, preferredMembers)
    local squadState = EnsureArcRaidSquadState(bucketId)
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
        return CreateArcRaidSquad(bucketId, { resolvedPlayerId })
    end

    local squad = squadState.squads[preferredSquadId]
    if not squad then
        return CreateArcRaidSquad(bucketId, { resolvedPlayerId })
    end

    if not IsPlayerInList(squad.members, resolvedPlayerId) then
        squad.members[#squad.members + 1] = resolvedPlayerId
    end
    squadState.playerMap[resolvedPlayerId] = preferredSquadId

    return preferredSquadId
end

local function EnsureArcRaidPlayerProfileState(bucketId)
    if not bucketId then
        return nil
    end

    arcRaidPlayerProfiles[bucketId] = arcRaidPlayerProfiles[bucketId] or {}
    return arcRaidPlayerProfiles[bucketId]
end

local function BuildArcPlayerDisplayName(Player, fallbackPlayerId)
    local charinfo = Player and Player.PlayerData and Player.PlayerData.charinfo or nil
    local firstname = charinfo and tostring(charinfo.firstname or '') or ''
    local lastname = charinfo and tostring(charinfo.lastname or '') or ''
    local fullName = (firstname .. " " .. lastname):match("^%s*(.-)%s*$") or ''

    if fullName ~= '' then
        return fullName
    end

    return ("ID %s"):format(tostring(fallbackPlayerId))
end

local function RememberArcRaidPlayerProfile(bucketId, playerId, Player)
    local resolvedPlayerId = tonumber(playerId)
    local profileState = EnsureArcRaidPlayerProfileState(bucketId)
    if not resolvedPlayerId or not profileState then
        return nil
    end

    profileState[resolvedPlayerId] = {
        citizenid = Player and Player.PlayerData and Player.PlayerData.citizenid or nil,
        name = BuildArcPlayerDisplayName(Player, resolvedPlayerId)
    }

    return profileState[resolvedPlayerId]
end

local function GetArcRaidPlayerProfile(bucketId, playerId)
    local resolvedPlayerId = tonumber(playerId)
    return resolvedPlayerId and arcRaidPlayerProfiles[bucketId] and arcRaidPlayerProfiles[bucketId][resolvedPlayerId] or nil
end

local function SetArcPlayerBucketIndex(playerId, bucketId)
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

local function AdjustArcPendingReconnectCount(bucketId, delta)
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

local function FindArcBucketByPlayer(playerId)
    local resolvedPlayerId = tonumber(playerId)
    if not resolvedPlayerId then
        return nil
    end

    local indexedBucketId = tonumber(arcPlayerBucketIndex[resolvedPlayerId])
    if indexedBucketId and indexedBucketId ~= 0 then
        if groupMembers[indexedBucketId] and IsPlayerInList(groupMembers[indexedBucketId], resolvedPlayerId) then
            return indexedBucketId
        end

        arcPlayerBucketIndex[resolvedPlayerId] = nil
    end

    for bucketId, members in pairs(groupMembers) do
        if IsPlayerInList(members, resolvedPlayerId) then
            arcPlayerBucketIndex[resolvedPlayerId] = tonumber(bucketId)
            return bucketId
        end
    end

    return nil
end

local function GetArcExtractionConfig()
    return (GetArcConfig() and GetArcConfig().Extraction) or {}
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
    local lootRegions = GetArcConfig().LootRegions or {}
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

    return GetArcConfig().LootTable or {}, nil, nil
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
    local policy = tostring(GetArcConfig().DisconnectPolicy or 'rollback'):lower()
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
    local arcConfig = GetArcConfig()
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
    local debounceMs = tonumber(GetArcConfig().StartDebounceMs) or 6000
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
    local modeConfig = GetModeConfig(modeId)
    return modeConfig.Metadata or {}
end

local function GetModeStages(modeId)
    if GetGameModeId(modeId) == 'arc_pvp' then
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
    if GetGameModeId(modeId) == 'arc_pvp' then
        return (Config.ArcPvP and Config.ArcPvP.BackupStashPrefix or 'arc_backup_') .. citizenId
    end

    local backupCfg = (Config.Survival and Config.Survival.BackupStash) or {}
    return (backupCfg.Prefix or 'surv_backup_') .. citizenId
end

local function RegisterBackupStash(modeId, stashId)
    if GetGameModeId(modeId) == 'arc_pvp' then
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
        Player.Functions.SetMetaData(metadata.modeKey, isActive and GetGameModeId(modeId) or nil)
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

    if metadata.modeKey and Player.PlayerData.metadata[metadata.modeKey] == GetGameModeId(modeId) then
        return true
    end

    local legacyModeId = Player.PlayerData.metadata["survival_mode"]
    if legacyModeId == GetGameModeId(modeId) then
        return true
    end

    if GetGameModeId(modeId) == 'classic' and Player.PlayerData.metadata["in_survival"] then
        return true
    end

    return false
end

local function GetActiveModeId(Player)
    for configuredModeId, _ in pairs((Config and Config.GameModes) or {}) do
        if IsModeActive(Player, configuredModeId) then
            return GetGameModeId(configuredModeId)
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
    local hasArcReconnectState = GetGameModeId(activeModeId) == 'arc_pvp' and arcDisconnectStates[cid] ~= nil

    if hasBackupItems or hasCachedBackup or hasArcReconnectState then
        return activeModeId
    end

    -- Bucket 0 with no recoverable backup/reconnect data means only stale mode metadata remains.
    ClearAllModeState(Player)
    Player.Functions.Save()
    return nil
end

local function GetPlayerStarterLoadout(Player, modeId)
    if GetGameModeId(modeId) == 'arc_pvp' then
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
    if GetGameModeId(modeId) == 'arc_pvp' and preparedLoadout and #preparedLoadout > 0 then
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
    local requirePrepared = GetArcConfig().RequirePreparedLoadout == true
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

    local leaderId = FindLobbyLeaderByMember(source)
    return leaderId, leaderId and activeLobbies[leaderId] or nil, false
end

local function BuildArcUiSummaryState(source, prepState)
    prepState = prepState or {}

    local leaderId, lobby, isLeader = GetLobbyContext(source)
    local isMember = leaderId ~= nil and not isLeader
    local localPed = GetPlayerPed(source)
    local strictValidation = GetArcConfig().StrictDeploymentValidation == true
    local allowInventory = GetArcConfig().AllowPersonalInventory ~= false
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

    if not bucketId or GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
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

    if GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
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

    local maxRaidPlayers = GetArcRaidMaxPlayers()
    local incomingCount = #(incomingPlayerIds or {})
    if maxRaidPlayers and (GetArcRaidPopulation(bucketId) + incomingCount) > maxRaidPlayers then
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

        if HasArcRaidParticipant(bucketId, playerId) or IsPlayerInList(members, playerId) then
            return false, 'already_participant'
        end
    end

    return true
end

local function FindBestArcSessionForLobby(incomingPlayerIds, playerLevel)
    local settings = GetArcAdmissionSettings()
    local candidates = {}

    for bucketId, modeId in pairs(bucketModes) do
        if GetGameModeId(modeId) == 'arc_pvp' then
            local joinable, denyReason = IsArcSessionJoinable(bucketId, incomingPlayerIds, {
                playerLevel = playerLevel
            })
            if joinable then
                candidates[#candidates + 1] = {
                    bucketId = bucketId,
                    remainingMs = GetArcRaidRemainingMs(bucketId),
                    population = GetArcRaidPopulation(bucketId)
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

    if GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' or not arcRaidState[bucketId] then
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

    if IsPlayerInList(groupMembers[bucketId] or {}, playerId) then
        return false, "Bu ARC oturumuna zaten bağlısın."
    end

    local maxRaidPlayers = GetArcRaidMaxPlayers()
    if maxRaidPlayers and (GetArcRaidPopulation(bucketId) + 1) > maxRaidPlayers then
        return false, "ARC oturumu dolduğu için geri dönüş reddedildi."
    end

    return true
end

local function CleanupArcSessionIfAbandoned(bucketId)
    if not bucketId or GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' or not arcRaidState[bucketId] then
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

    RemoveArcRaidSquadPlayer(bucketId, playerId)
    if arcRaidPlayerProfiles[bucketId] then
        arcRaidPlayerProfiles[bucketId][tonumber(playerId)] = nil
    end
    groupSizes[bucketId] = #members
    SetArcPlayerBucketIndex(playerId, nil)
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
    SetArcExtractionPhase(bucketId, 'called', extractionState.callAckDelayMs, {
        zone = selectedZone,
        calledBy = callerSource,
        callerName = callerName
    })
    for _, playerId in ipairs(groupMembers[bucketId] or {}) do
        TriggerClientEvent('gs-survival:client:playSignalFlare', playerId, {
            coords = Vector3ToTable(ToVector3(selectedZone.coords))
        })
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
    TriggerClientEvent('QBCore:Functions:Notify', source, "Tahliye başarılı. Baskın ekipmanın ana depoya aktarıldı.", "success")

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
                and not FindLobbyLeaderByMember(playerId)
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

-- [Davetler]
RegisterNetEvent('gs-survival:server:sendInvite', function(tId)
    local src = source
    tId = tonumber(tId)
    if not tId then
        return
    end
    local lobby = activeLobbies[src]

    if not lobby then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Önce bir lobi kurmalısın!", "error")
        return
    end

    if tonumber(tId) == tonumber(src) then
        return
    end

    if CountMembers(lobby.members) >= MAX_LOBBY_MEMBERS then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Lobi zaten dolu! (Maksimum " .. MAX_LOBBY_SIZE .. " kişi)", "error")
        return
    end

    if lobby.members[tId] then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Bu oyuncu zaten senin lobinde.", "error")
        return
    end

    if activeLobbies[tId] or FindLobbyLeaderByMember(tId) then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Bu oyuncunun zaten aktif bir lobisi var.", "error")
        return
    end

    local targetPlayer = QBCore.Functions.GetPlayer(tId)
    if not targetPlayer or GetPlayerRoutingBucket(tId) ~= 0 then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Bu oyuncu şu anda ARC/lobi daveti alamaz.", "error")
        return
    end

    local canInvite, proximityError = EnsureLobbyProximity(src, tId, targetPlayer and (targetPlayer.PlayerData.charinfo.firstname .. " " .. targetPlayer.PlayerData.charinfo.lastname) or nil)
    if not canInvite then
        TriggerClientEvent('QBCore:Functions:Notify', src, proximityError, "error")
        return
    end

    TriggerClientEvent('gs-survival:client:receiveInvite', tId, src)
    TriggerClientEvent('QBCore:Functions:Notify', src, "Davet gönderildi!", "success")
end)

AddEventHandler('ox_inventory:onItemDropped', function(source, inventory, slot, item)
    -- Eğer yere atılan eşyanın metadatasında 'survivalItem' varsa
    if item.metadata and item.metadata.survivalItem then
        -- Eşyayı yerden (drop'tan) anında sil, kimse alamasın
        exports.ox_inventory:RemoveItem(inventory, item.name, item.count, item.metadata, slot)
        TriggerClientEvent('QBCore:Functions:Notify', source, "Survival eşyalarını yere atamazsın, eşya imha edildi!", "error")
    end
end)

CleanBucketEntities = function(bucketId)
    if not bucketId or bucketId == 0 then return end

    -- NPC'leri temizle
    local peds = GetAllPeds()
    for _, entity in ipairs(peds) do
        if GetEntityRoutingBucket(entity) == bucketId and not IsPedAPlayer(entity) then
            DeleteEntity(entity)
        end
    end

    -- Yerde kalan objeleri temizle
    local objects = GetAllObjects()
    for _, entity in ipairs(objects) do
        if GetEntityRoutingBucket(entity) == bucketId then
            DeleteEntity(entity)
        end
    end
end

local function SyncArcRaidPlayers(bucketId)
    if GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' or not groupMembers[bucketId] then
        return
    end

    for _, playerId in ipairs(groupMembers[bucketId]) do
        TriggerClientEvent('gs-survival:client:updateArcRaidPlayers', playerId, GetArcRaidSquadMembers(bucketId, playerId), groupMembers[bucketId])
    end
end

local function BuildLobbyMemberList(leaderId)
    local lobby = activeLobbies[leaderId]
    local memberList = {}

    if lobby then
        table.insert(memberList, {
            id = leaderId,
            name = lobby.leaderName,
            isLeader = true,
            isReady = true
        })

        for id, info in pairs(lobby.members) do
            local memberName = type(info) == "table" and info.name or info
            local isReady = type(info) == "table" and info.isReady == true or false
            table.insert(memberList, {
                id = id,
                name = memberName,
                isReady = isReady
            })
        end
    end

    return memberList
end

local function SyncLobbyMembers(leaderId)
    local lobby = activeLobbies[leaderId]
    if not lobby then return end

    local memberList = BuildLobbyMemberList(leaderId)
    TriggerClientEvent('gs-survival:client:syncLobbyMembers', leaderId, leaderId, memberList)
    TriggerClientEvent('gs-survival:client:refreshMenuState', leaderId)

    for memberId, _ in pairs(lobby.members) do
        TriggerClientEvent('gs-survival:client:syncLobbyMembers', memberId, leaderId, memberList)
        TriggerClientEvent('gs-survival:client:refreshMenuState', memberId)
    end
end

local function BuildActiveLobbyList(source)
    local lobbies = {}
    local memberLobbyLeaderId = FindLobbyLeaderByMember(source)

    for leaderId, lobby in pairs(activeLobbies) do
        local isOwnLobby = tonumber(leaderId) == tonumber(source)
        local isJoinedLobby = tonumber(memberLobbyLeaderId) == tonumber(leaderId)
        local isPublic = lobby.isPublic == true
        local isNearbyLeader = IsPlayerWithinLobbyProximity(leaderId, source)

        if isPublic or isOwnLobby or isJoinedLobby then
            local memberCount = CountMembers(lobby.members)
            local readyCount = 0

            for _, info in pairs(lobby.members or {}) do
                if type(info) == "table" and info.isReady == true then
                    readyCount = readyCount + 1
                end
            end

            table.insert(lobbies, {
                leaderId = leaderId,
                leaderName = lobby.leaderName,
                playerCount = memberCount + 1,
                memberCount = memberCount,
                readyCount = readyCount,
                maxPlayers = MAX_LOBBY_SIZE,
                isOwnLobby = isOwnLobby,
                isJoinedLobby = isJoinedLobby,
                isPublic = isPublic,
                canJoin = isPublic and isNearbyLeader and not isOwnLobby and not isJoinedLobby and (memberCount + 1) < MAX_LOBBY_SIZE
            })
        end
    end

    table.sort(lobbies, function(a, b)
        if a.isOwnLobby ~= b.isOwnLobby then
            return a.isOwnLobby
        end

        if a.playerCount ~= b.playerCount then
            return a.playerCount > b.playerCount
        end

        return tostring(a.leaderName) < tostring(b.leaderName)
    end)

    return lobbies
end

local function AddMemberToLobby(leaderId, memberId, memberName)
    activeLobbies[leaderId].members[memberId] = {
        name = memberName,
        isReady = false
    }

    TriggerClientEvent('gs-survival:client:addInvited', leaderId, memberId)
    TriggerClientEvent('gs-survival:client:joinedLobby', memberId, {
        leaderId = leaderId,
        isPublic = activeLobbies[leaderId].isPublic == true
    })
    TriggerClientEvent('gs-survival:client:setReadyState', memberId, false)
    TriggerClientEvent('QBCore:Functions:Notify', leaderId, memberName .. " lobiye katıldı!", "success")
    SyncLobbyMembers(leaderId)
end
local function GetPlayerSurvivalLevel(Player)
    local survivalMetadata = GetModeMetadata('classic')
    return tonumber(Player.PlayerData.metadata[survivalMetadata.level or 'survival_level'] or 1) or 1
end

local function GetMinimumPlayerSurvivalLevel(playerIds)
    local minimumLevel = nil

    for _, playerId in ipairs(playerIds or {}) do
        local Player = QBCore.Functions.GetPlayer(playerId)
        if not Player then
            return nil, "ARC seviye doğrulaması başarısız: oyuncu bulunamadı."
        end

        local playerLevel = GetPlayerSurvivalLevel(Player)
        if minimumLevel == nil or playerLevel < minimumLevel then
            minimumLevel = playerLevel
        end
    end

    return minimumLevel or 1
end

local function ResolveModeStageId(modeId, requestedStageId, playerLevel)
    if GetGameModeId(modeId) == 'arc_pvp' then
        return 1
    end

    local resolvedStageId = tonumber(requestedStageId)
    local stages = GetModeStages(modeId)

    if not resolvedStageId or not stages[resolvedStageId] then
        return nil
    end

    if resolvedStageId > playerLevel then
        return nil, "Bu bölge için yeterli seviyeniz yok!"
    end

    return resolvedStageId
end

local function BuildStartingGroup(src, invited)
    local peps = { src }
    local lobby = activeLobbies[src]

    if lobby then
        for memberId, info in pairs(lobby.members) do
            local isReady = type(info) == "table" and info.isReady == true or false
            local memberName = type(info) == "table" and info.name or tostring(info or memberId)
            if not isReady then
                return nil, memberName .. " oyuncusu henüz hazır değil!"
            end

            local canStartTogether, proximityError = EnsureLobbyProximity(src, memberId, memberName)
            if not canStartTogether then
                return nil, proximityError
            end

            table.insert(peps, memberId)
        end
    end

    return peps
end

local function ValidateArcStartParticipants(playerIds)
    if GetArcConfig().StrictDeploymentValidation ~= true then
        return true
    end

    for _, playerId in ipairs(playerIds or {}) do
        local targetPlayer = QBCore.Functions.GetPlayer(playerId)
        if not targetPlayer then
            return false, "Deploy doğrulaması başarısız: oyuncu bulunamadı."
        end

        if GetPlayerRoutingBucket(playerId) ~= 0 then
            return false, "Deploy doğrulaması başarısız: oyunculardan biri zaten aktif bir dünyada."
        end

        local activeModeId = ResolvePlayerActiveModeState(playerId, targetPlayer)
        if activeModeId and activeModeId ~= '' then
            return false, "Deploy doğrulaması başarısız: oyunculardan biri başka bir modda görünüyor."
        end
    end

    return true
end

local function StartModeOperation(src, invited, stageId, modeId)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if FindLobbyLeaderByMember(src) then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Operasyonu yalnızca lobi lideri başlatabilir.", "error")
        return
    end

    local selectedModeId = GetGameModeId(modeId)
    if not Config.GameModes or not Config.GameModes[selectedModeId] then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Geçersiz oyun modu!", "error")
        return
    end

    local playerLevel = GetPlayerSurvivalLevel(Player)
    local arcJoinLevel = playerLevel

    local peps, groupError = BuildStartingGroup(src, invited)
    if not peps then
        TriggerClientEvent('QBCore:Functions:Notify', src, groupError or "Takım oluşturulamadı.", "error")
        return
    end

    if selectedModeId == 'arc_pvp' then
        local validParticipants, validationError = ValidateArcStartParticipants(peps)
        if not validParticipants then
            TriggerClientEvent('QBCore:Functions:Notify', src, validationError or "ARC deploy doğrulaması başarısız.", "error")
            return
        end

        arcJoinLevel, groupError = GetMinimumPlayerSurvivalLevel(peps)
        if not arcJoinLevel then
            TriggerClientEvent('QBCore:Functions:Notify', src, groupError or "ARC seviye doğrulaması başarısız.", "error")
            return
        end
    end

    local resolvedStageId = nil
    local stageError = nil
    local stageData = nil
    local preparedArcLoadouts = nil
    local deploymentState = nil
    local joiningExistingArcRaid = false
    local bId = nil

    if selectedModeId == 'arc_pvp' then
        preparedArcLoadouts, groupError = BuildArcPreparedLoadouts(peps)
        if not preparedArcLoadouts then
            TriggerClientEvent('QBCore:Functions:Notify', src, groupError or "ARC loadout hazırlığı eksik.", "error")
            return
        end

        local canJoinArc, admissionResult = CanLobbyJoinArcSession(peps, arcJoinLevel)
        if not canJoinArc then
            TriggerClientEvent('QBCore:Functions:Notify', src, admissionResult or "ARC admission doğrulaması başarısız.", "error")
            return
        end

        bId = admissionResult and admissionResult.bucketId or nil
        if bId and admissionResult and admissionResult.joinExisting then
            deploymentState = BuildArcJoinDeploymentPayload(bId)
            if deploymentState then
                joiningExistingArcRaid = true
                resolvedStageId = GetArcRaidStageId(bId)
                stageData = GetStageData(selectedModeId, resolvedStageId)
            end
        end

        if not joiningExistingArcRaid then
            bId = nil
            resolvedStageId, stageError = ResolveModeStageId(selectedModeId, stageId, selectedModeId == 'arc_pvp' and arcJoinLevel or playerLevel)
            if not resolvedStageId then
                TriggerClientEvent('QBCore:Functions:Notify', src, stageError or "Geçersiz operasyon bölgesi!", "error")
                return
            end

            stageData = GetStageData(selectedModeId, resolvedStageId)
            deploymentState, groupError = BuildArcDeploymentState(stageData, resolvedStageId, bId)
            if not deploymentState then
                TriggerClientEvent('QBCore:Functions:Notify', src, groupError or "ARC deployment bölgesi seçilemedi.", "error")
                return
            end
        end
    else
        resolvedStageId, stageError = ResolveModeStageId(selectedModeId, stageId, playerLevel)
        if not resolvedStageId then
            TriggerClientEvent('QBCore:Functions:Notify', src, stageError or "Geçersiz operasyon bölgesi!", "error")
            return
        end

        stageData = GetStageData(selectedModeId, resolvedStageId)
    end

    if not bId then
        bId = GenerateBucketId()
    end

    if joiningExistingArcRaid then
        groupMembers[bId] = groupMembers[bId] or {}
        for _, playerId in ipairs(peps) do
            if not IsPlayerInList(groupMembers[bId], playerId) then
                groupMembers[bId][#groupMembers[bId] + 1] = playerId
            end
        end
        TrackArcRaidParticipants(bId, peps)
        EnsureArcSessionAdmissionState(bId)
        groupSizes[bId] = #groupMembers[bId]
    else
        groupSizes[bId] = #peps
        groupMembers[bId] = peps
        TrackArcRaidParticipants(bId, peps)
        lobbyStage[bId] = resolvedStageId
        bucketModes[bId] = selectedModeId
        eliminatedArcPlayers[bId] = {}
        openedArcContainers[bId] = {}
        arcDeathContainers[bId] = {}
        if selectedModeId == 'arc_pvp' and deploymentState then
            arcSessionAdmission[bId] = nil
            arcSessionEliminations[bId] = {}
            arcSessionExtractions[bId] = {}
            arcSessionDisconnects[bId] = {}
            local raidDurationMs = tonumber(deploymentState.raidDurationMs) or 0
            local startedAt = GetGameTimer()
            arcRaidState[bId] = {
                deployment = deploymentState,
                sessionKey = GenerateArcSessionKey(bId),
                startedAt = startedAt,
                endsAt = startedAt + raidDurationMs,
                resultLedger = {}
            }
            EnsureArcSessionAdmissionState(bId)
            InitializeArcExtractionState(bId)
            deploymentState.extraction = BuildArcExtractionClientState(bId)
        else
            arcRaidState[bId] = nil
        end
    end

    if selectedModeId == 'arc_pvp' then
        CreateArcRaidSquad(bId, peps)
    else
        bucketWaveState[bId] = 0
    end

    activeLobbies[src] = nil

    for _, playerId in pairs(peps) do
        local targetPlayer = QBCore.Functions.GetPlayer(playerId)
        if targetPlayer then
            local cid = targetPlayer.PlayerData.citizenid
            local stashId = GetBackupStashId(selectedModeId, cid)

            ClearAllModeState(targetPlayer)
            SetModeActiveState(targetPlayer, selectedModeId, true)
            targetPlayer.Functions.Save()

            RegisterBackupStash(selectedModeId, stashId)
            exports.ox_inventory:ClearInventory(stashId)

            if not playerBackups[cid] then
                playerBackups[cid] = {}
                local items = exports.ox_inventory:GetInventoryItems(playerId)
                if items then
                    for _, item in pairs(items) do
                        table.insert(playerBackups[cid], { name = item.name, count = item.count, metadata = item.metadata })
                        exports.ox_inventory:AddItem(stashId, item.name, item.count, item.metadata)
                    end
                end
            end

            exports.ox_inventory:ClearInventory(playerId)
            Wait(250)

            if selectedModeId == 'arc_pvp' then
                RegisterArcMainStash(targetPlayer)
                RegisterArcLoadoutStash(targetPlayer)
                RememberArcRaidPlayerProfile(bId, playerId, targetPlayer)
            end

            GiveModeLoadout(playerId, targetPlayer, selectedModeId, preparedArcLoadouts and preparedArcLoadouts[playerId] and preparedArcLoadouts[playerId].items or nil)
            if selectedModeId == 'arc_pvp' and preparedArcLoadouts and preparedArcLoadouts[playerId] then
                exports.ox_inventory:ClearInventory(preparedArcLoadouts[playerId].stashId)
            end
            SetPlayerRoutingBucket(playerId, bId)
            SetArcPlayerBucketIndex(playerId, bId)

            if selectedModeId == 'arc_pvp' and deploymentState and deploymentState.insertion then
                SetEntityCoords(GetPlayerPed(playerId), deploymentState.insertion.x, deploymentState.insertion.y, deploymentState.insertion.z)
            elseif stageData and stageData.center then
                SetEntityCoords(GetPlayerPed(playerId), stageData.center.x, stageData.center.y, stageData.center.z)
            end

            TriggerClientEvent('hospital:client:Revive', playerId)
            if selectedModeId == 'arc_pvp' then
                TriggerClientEvent('gs-survival:client:initArcPvP', playerId, bId, GetArcRaidSquadMembers(bId, playerId), groupMembers[bId], resolvedStageId, deploymentState)
            else
                TriggerClientEvent('gs-survival:client:initSurvival', playerId, bId, 1, peps, resolvedStageId)
            end
        end
    end

    if selectedModeId == 'arc_pvp' then
        SyncArcRaidPlayers(bId)
        SyncArcExtractionState(bId)
        if not joiningExistingArcRaid and GetArcExtractionState(bId) then
            CreateThread(function()
                while groupMembers[bId] and arcRaidState[bId] and not arcFinalizeLocks[bId] do
                    AdvanceArcExtractionPhase(bId)
                    Wait(1000)
                end
            end)
        end
    end

    if selectedModeId == 'arc_pvp' and deploymentState and not joiningExistingArcRaid then
        CreateThread(function()
            Wait(tonumber(deploymentState.raidDurationMs or 0) or 0)
            if not groupMembers[bId] or GetGameModeId(bucketModes[bId]) ~= 'arc_pvp' then
                return
            end

            if IsArcExtractionEnabled() and GetArcExtractionState(bId) and GetArcExtractionState(bId).autoFailIfNoExtract == true then
                FinalizeArcMatch(bId, {}, 'failed_to_extract')
                return
            end

            local alivePlayers = GetArcAlivePlayers(bId)
            FinalizeArcMatch(bId, alivePlayers, 'timeout')
        end)
    end
end

-- [Başlatma]
RegisterNetEvent('gs-survival:server:startSurvival', function(invited, stageId, modeId)
    local src = source
    local requestedMode = GetGameModeId(modeId or 'classic')
    if requestedMode ~= 'classic' then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Klasik Hayatta Kalma için startSurvival, ARC Baskını için startArcPvP akışı kullanılmalıdır.", "error")
        return
    end

    local ok, err = pcall(StartModeOperation, src, invited, stageId, 'classic')
    if not ok then
        print(string.format("^1[CLASSIC START]^7 %s", tostring(err)))
        TriggerClientEvent('QBCore:Functions:Notify', src, "Klasik operasyon başlatılırken beklenmeyen bir hata oluştu.", "error")
    end
end)

RegisterNetEvent('gs-survival:server:startArcPvP', function(invited, stageId)
    local src = source
    local acquired, lockState = AcquireArcStartLock(src)
    if not acquired then
        TriggerClientEvent('QBCore:Functions:Notify', src, lockState or "ARC deploy isteği reddedildi.", "error")
        return
    end

    local ok, err = pcall(StartModeOperation, src, invited, stageId, 'arc_pvp')
    ReleaseArcStartLock(lockState)

    if not ok then
        print(string.format("^1[ARC START]^7 %s", tostring(err)))
        TriggerClientEvent('QBCore:Functions:Notify', src, "ARC deploy sırasında beklenmeyen bir hata oluştu.", "error")
    end
end)

RegisterNetEvent('gs-survival:server:startArcExtractionCall', function(zoneId)
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)

    if bucketId == 0 or not IsBucketMember(bucketId, src) or GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Tahliye yalnızca ARC baskını sırasında çağrılabilir.", "error")
        return
    end

    local ok, err = StartArcExtractionCall(bucketId, src, zoneId)
    if not ok then
        TriggerClientEvent('QBCore:Functions:Notify', src, err or "Tahliye hattı çağrılamadı.", "error")
    end
end)

RegisterNetEvent('gs-survival:server:departArcExtraction', function()
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)

    if GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Kalkış yalnızca ARC baskını sırasında başlatılabilir.", "error")
        return
    end

    local ok, err = TryResolveArcExtractionDeparture(bucketId, src, true)
    if not ok then
        TriggerClientEvent('QBCore:Functions:Notify', src, err or "Kalkış başlatılamadı.", "error")
    end
end)

RegisterNetEvent('gs-survival:server:spawnWave', function(bId, wave, stageId)
    local src = source
    local bucketId = tonumber(bId)
    local waveNumber = math.floor(tonumber(wave) or 0)

    if not bucketId or bucketId <= 0 or GetPlayerRoutingBucket(src) ~= bucketId then
        return
    end

    if not IsBucketMember(bucketId, src) then
        return
    end

    if GetGameModeId(bucketModes[bucketId]) == 'arc_pvp' then
        return
    end

    if waveNumber <= 0 then
        return
    end

    local previousWave = tonumber(bucketWaveState[bucketId] or 0) or 0
    if waveNumber ~= (previousWave + 1) then
        return
    end

    if previousWave > 0 and CountAliveBucketNpcs(bucketId) > 0 then
        return
    end

    -- [GÜNCELLEME]: Lobi stage bilgisini çek ve stageData'nın varlığını garantile
    local sId = (lobbyStage and lobbyStage[bucketId]) or tonumber(stageId) or 1
    local stageData = Config.Stages[sId]

    -- Eğer stageData bulunamazsa Stage 1'i baz al ki sistem çökmesin
    if not stageData then
        stageData = Config.Stages[1]
        sId = 1
    end

    -- [EKLEME]: Önce stage içindeki dalgaya bak
    local cfg = stageData.Waves and stageData.Waves[waveNumber]

    if not cfg or not groupMembers[bucketId] or #groupMembers[bucketId] == 0 then return end

    bucketWaveState[bucketId] = waveNumber

    local multiplier = stageData and stageData.multiplier or 1.0
    CleanBucketEntities(bucketId)

    -- [GÜNCELLEME]: Spawn noktalarını öncelikle stageData'dan al
    local spawnPoints = (stageData and stageData.spawnPoints) or Config.SpawnPoints
    if type(spawnPoints) ~= 'table' or #spawnPoints == 0 then
        return
    end

    -- Config'deki npcCountPerPlayer her bir spawn noktasında doğacak sayı olsun
    local countPerPoint = cfg.npcCount or 1

    for _, pos in pairs(spawnPoints) do
        for i = 1, countPerPoint do
            Wait(150) -- Sunucuyu yormamak için kısa bir bekleme

            local npc = CreatePed(4, cfg.pedModel, pos.x + math.random(-2,2), pos.y + math.random(-2,2), pos.z, 0.0, true, true)

            -- Entity oluşana kadar bekle
            local timeout = 0
            while not DoesEntityExist(npc) and timeout < 100 do
                Wait(10)
                timeout = timeout + 1
            end

            if DoesEntityExist(npc) then
                SetEntityRoutingBucket(npc, bucketId)

                -- Köpek Dalgası Kontrolü
                if not cfg.isDogWave then
                    GiveWeaponToPed(npc, GetHashKey(cfg.weapon or "weapon_pistol"), 999, false, true)
                    -- Oyunculara saldırması için (rastgele bir grup üyesini hedef alır)
                    local randomTarget = groupMembers[bucketId][math.random(1, #groupMembers[bucketId])]
                    TaskCombatPed(npc, GetPlayerPed(randomTarget), 0, 16)
                else
                    -- Köpekler için saldırı komutu
                    local randomTarget = groupMembers[bucketId][math.random(1, #groupMembers[bucketId])]
                    TaskCombatPed(npc, GetPlayerPed(randomTarget), 0, 16)
                end

                -- Client tarafında Blip ve Target ayarları için gönder
                for _, pId in pairs(groupMembers[bucketId]) do
                    -- Multiplier (zorluk çarpanı) parametre olarak eklendi
                    TriggerClientEvent('gs-survival:client:setupNpc', pId, NetworkGetNetworkIdFromEntity(npc), multiplier)
                end
            end
        end
    end
end)

QBCore.Functions.CreateCallback('gs-survival:server:hasCraftMaterials', function(source, cb, item, amount, multiplier, stashId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(false) end

    local craftSource = ResolveArcCraftSource(Player, stashId)
    if stashId and not craftSource then
        return cb(false)
    end

    if type(item) == 'table' then
        return cb(HasCraftRequirements(Player, item, craftSource))
    end

    local validRecipe = FindCraftRecipeArgs(item, amount)
    if not validRecipe then
        return cb(false)
    end

    local normalizedMultiplier = NormalizeCraftMultiplier(multiplier)
    local inventoryItems = GetCraftInventoryItems(Player, craftSource)
    if normalizedMultiplier > GetCraftMaxCraftable(inventoryItems, validRecipe.requirements) then
        return cb(false)
    end

    cb(HasCraftRequirements(Player, BuildScaledCraftRequirements(validRecipe.requirements, normalizedMultiplier), craftSource))
end)

QBCore.Functions.CreateCallback('gs-survival:server:getCraftMenuData', function(source, cb, stashId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        return cb({})
    end

    local craftSource = ResolveArcCraftSource(Player, stashId)
    if stashId and not craftSource then
        return cb({})
    end

    cb(BuildCraftRecipesForPlayer(Player, craftSource))
end)

RegisterNetEvent('gs-survival:server:createLobby', function(isPublic)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if activeLobbies[src] then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Zaten aktif bir lobin var.", "error")
        return
    end

    if FindLobbyLeaderByMember(src) then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Önce mevcut lobinden ayrılmalısın.", "error")
        return
    end

    activeLobbies[src] = {
        leaderName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname,
        members = {},
        isPublic = isPublic == true
    }

    TriggerClientEvent('gs-survival:client:lobbyCreated', src, {
        isPublic = activeLobbies[src].isPublic == true
    })
    SyncLobbyMembers(src)
end)

QBCore.Functions.CreateCallback('gs-survival:server:getActiveLobbies', function(source, cb)
    cb(BuildActiveLobbyList(source))
end)

QBCore.Functions.CreateCallback('gs-survival:server:getArcPrepState', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    cb(BuildArcPrepState(Player))
end)

QBCore.Functions.CreateCallback('gs-survival:server:getArcMenuState', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    local prepState = BuildArcPrepState(Player)
    cb({
        prep = prepState,
        summary = BuildArcUiSummaryState(source, prepState)
    })
end)

QBCore.Functions.CreateCallback('gs-survival:server:getArcLockerState', function(source, cb, focusSide)
    local Player = QBCore.Functions.GetPlayer(source)
    cb(BuildArcLockerState(Player, focusSide))
end)



-- Davet Onaylandığında Lobiyi Kaydet
RegisterNetEvent('gs-survival:server:confirmInvite', function(leaderId)
    local src = source
    leaderId = tonumber(leaderId)
    local leader = QBCore.Functions.GetPlayer(leaderId)
    local member = QBCore.Functions.GetPlayer(src)

    if src == leaderId then return end

    if leader and member then
        if not activeLobbies[leaderId] then
            TriggerClientEvent('QBCore:Functions:Notify', src, "Bu lobi artık aktif değil.", "error")
            return
        end

        if activeLobbies[src] or FindLobbyLeaderByMember(src) then
            TriggerClientEvent('QBCore:Functions:Notify', src, "Zaten başka bir lobidesin.", "error")
            return
        end

        if CountMembers(activeLobbies[leaderId].members) >= MAX_LOBBY_MEMBERS then
            TriggerClientEvent('QBCore:Functions:Notify', src, "Lobi dolu olduğu için katılamadın.", "error")
            return
        end

        if GetPlayerRoutingBucket(src) ~= 0 or GetPlayerRoutingBucket(leaderId) ~= 0 then
            TriggerClientEvent('QBCore:Functions:Notify', src, "Bu lobiye katılmak için aktif operasyon dışında olmalısın.", "error")
            return
        end

        local memberName = member.PlayerData.charinfo.firstname .. " " .. member.PlayerData.charinfo.lastname
        local canJoin, proximityError = EnsureLobbyProximity(leaderId, src, memberName)
        if not canJoin then
            TriggerClientEvent('QBCore:Functions:Notify', src, proximityError, "error")
            TriggerClientEvent('QBCore:Functions:Notify', leaderId, memberName .. " daveti kabul etmeye çalıştı ama yanında olmadığı için alınmadı.", "error")
            return
        end

        AddMemberToLobby(leaderId, src, memberName)
    end
end)

RegisterNetEvent('gs-survival:server:joinPublicLobby', function(leaderId)
    local src = source
    local member = QBCore.Functions.GetPlayer(src)
    leaderId = tonumber(leaderId)

    if not leaderId or not member or src == leaderId then
        return
    end

    local lobby = activeLobbies[leaderId]
    if not lobby then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Bu lobi artık aktif değil.", "error")
        return
    end

    if lobby.isPublic ~= true then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Bu lobi private olduğu için doğrudan katılamazsın.", "error")
        return
    end

    if activeLobbies[src] or FindLobbyLeaderByMember(src) then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Zaten başka bir lobidesin.", "error")
        return
    end

    if CountMembers(lobby.members) >= MAX_LOBBY_MEMBERS then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Lobi dolu olduğu için katılamadın.", "error")
        return
    end

    if GetPlayerRoutingBucket(src) ~= 0 or GetPlayerRoutingBucket(leaderId) ~= 0 then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Bu lobiye katılmak için aktif operasyon dışında olmalısın.", "error")
        return
    end

    local memberName = member.PlayerData.charinfo.firstname .. " " .. member.PlayerData.charinfo.lastname
    local canJoin, proximityError = EnsureLobbyProximity(leaderId, src, memberName)
    if not canJoin then
        TriggerClientEvent('QBCore:Functions:Notify', src, proximityError, "error")
        TriggerClientEvent('QBCore:Functions:Notify', leaderId, memberName .. " public lobiye uzaktan katılmaya çalıştı.", "error")
        return
    end

    AddMemberToLobby(leaderId, src, memberName)
end)

RegisterNetEvent('gs-survival:server:denyInvite', function(leaderId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    leaderId = tonumber(leaderId)

    if not leaderId or not Player or tonumber(src) == leaderId or not activeLobbies[leaderId] then
        return
    end

    local playerName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
    TriggerClientEvent('QBCore:Functions:Notify', leaderId, playerName .. " daveti reddetti.", "error")
end)

-- Lobi Üyelerini Çekme (Hem Lider hem Üye için)
QBCore.Functions.CreateCallback('gs-survival:server:getLobbyMembers', function(source, cb, leaderId)
    cb(BuildLobbyMemberList(leaderId))
end)

local function RecoverPlayerAfterResourceRestart(playerId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then
        return
    end

    local activeModeId = ResolvePlayerActiveModeState(playerId, Player)
    if not activeModeId then
        return
    end

    local cid = Player.PlayerData.citizenid
    local backupStashId = GetBackupStashId(activeModeId, cid)
    RegisterBackupStash(activeModeId, backupStashId)

    local backupItems = NormalizeInventoryItems(exports.ox_inventory:GetInventoryItems(backupStashId))
    local hadBackupItems = backupItems and #backupItems > 0
    local restored = false

    -- Her durumda oyuncunun üstündeki geçici maç envanterini temizle
    exports.ox_inventory:ClearInventory(playerId)
    Wait(250)

    if hadBackupItems then
        for _, item in ipairs(backupItems) do
            exports.ox_inventory:AddItem(playerId, item.name, item.count, item.metadata)
        end
        exports.ox_inventory:ClearInventory(backupStashId)
        restored = true
    end

    playerBackups[cid] = nil
    if arcDisconnectStates[cid] and arcDisconnectStates[cid].allowRejoin == true and arcDisconnectStates[cid].resolved ~= true then
        AdjustArcPendingReconnectCount(arcDisconnectStates[cid].bucketId, -1)
    end
    arcDisconnectStates[cid] = nil
    ClearAllModeState(Player)
    Player.Functions.Save()

    if GetPlayerRoutingBucket(playerId) ~= 0 then
        SetPlayerRoutingBucket(playerId, 0)
    end

    TriggerClientEvent('gs-survival:client:cleanupBeforeLeave', playerId)

    if restored then
        TriggerClientEvent('QBCore:Functions:Notify', playerId,
            "Kaynak yeniden başlatıldı; eşyaların yedekten geri verildi ve aktif baskın güvenli şekilde kapatıldı.",
            "primary")
    else
        TriggerClientEvent('QBCore:Functions:Notify', playerId,
            "Kaynak yeniden başlatıldı; yedek bulunamadığı için geçici baskın yükün temizlendi ve eski mod durumu kapatıldı.",
            "error")
    end
end

local function RetryRecoverPlayerAfterResourceRestart(playerId, maxAttempts, delayMs)
    local targetId = tonumber(playerId)
    local attempts = tonumber(maxAttempts) or 1
    local waitMs = math.max(500, tonumber(delayMs) or 3000)

    if not targetId or attempts <= 0 then
        return
    end

    CreateThread(function()
        for attempt = 1, attempts do
            if QBCore.Functions.GetPlayer(targetId) then
                RecoverPlayerAfterResourceRestart(targetId)
                if attempt > 1 then
                    print(("[gs-survival] Restart recovery retried for player %s on attempt %s."):format(targetId, attempt))
                end
                return
            end

            if attempt < attempts then
                Wait(waitMs)
            end
        end

        print(("[gs-survival] Restart recovery skipped for player %s after %s attempts; QBCore player state never became ready."):format(targetId, attempts))
    end)
end

RegisterNetEvent('gs-survival:server:toggleReady', function()
    local src = source

    for leaderId, data in pairs(activeLobbies) do
        if data.members and data.members[src] then
            if type(data.members[src]) ~= "table" then
                data.members[src] = { name = tostring(data.members[src]), isReady = false }
            end

            local nextReadyState = data.members[src].isReady ~= true
            data.members[src].isReady = nextReadyState
            TriggerClientEvent('gs-survival:client:setReadyState', src, nextReadyState)
            TriggerClientEvent('QBCore:Functions:Notify', src, nextReadyState and "Hazır durumun liderine iletildi." or "Hazır durumun kaldırıldı.", nextReadyState and "success" or "primary")
            TriggerClientEvent('QBCore:Functions:Notify', leaderId, data.members[src].name .. (nextReadyState and " hazır durumda." or " artık hazır değil."), nextReadyState and "success" or "primary")
            SyncLobbyMembers(leaderId)
            return
        end
    end
end)

-- Lobi Dağıtma
RegisterNetEvent('gs-survival:server:disbandLobby', function()
    local src = source
    if activeLobbies[src] then
        for memberId, _ in pairs(activeLobbies[src].members) do
            TriggerClientEvent('gs-survival:client:setReadyState', memberId, false)
            TriggerClientEvent('gs-survival:client:forceLeaveLobby', memberId)
        end
        activeLobbies[src] = nil
    end
end)

-- Lobiden Ayrılma (Üye İçin)
RegisterNetEvent('gs-survival:server:leaveLobby', function(leaderId)
    local src = source
    if activeLobbies[leaderId] and activeLobbies[leaderId].members[src] then
        activeLobbies[leaderId].members[src] = nil
        TriggerClientEvent('gs-survival:client:setReadyState', src, false)
        TriggerClientEvent('gs-survival:client:removeFromInvited', leaderId, src)
        TriggerClientEvent('QBCore:Functions:Notify', leaderId, "Bir üye lobiden ayrıldı.", "error")
        SyncLobbyMembers(leaderId)
    end
end)

-- Malzemeleri Sil ve Eşyayı Ver
RegisterNetEvent('gs-survival:server:finishCrafting', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    data = data or {}

    -- [GÜVENLİK]: İstenen item ve miktarın Config.CraftRecipes'te gerçekten tanımlı olduğunu doğrula
    local validRecipe = FindCraftRecipeArgs(data.item, data.amount)

    if not validRecipe then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Geçersiz üretim talebi!", "error")
        return
    end

    local craftSource = ResolveArcCraftSource(Player, data.stashId)
    if data.stashId and not craftSource then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Geçersiz ARC depo talebi!", "error")
        return
    end

    local multiplier = NormalizeCraftMultiplier(data.multiplier)
    local inventoryItems = GetCraftInventoryItems(Player, craftSource)
    local maxCraftable = GetCraftMaxCraftable(inventoryItems, validRecipe.requirements)
    if multiplier > maxCraftable then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Seçtiğin üretim adedi için yeterli malzeme yok!", "error")
        return
    end

    local scaledRequirements = BuildScaledCraftRequirements(validRecipe.requirements, multiplier)
    local craftedAmount = (tonumber(validRecipe.amount) or 0) * multiplier

    -- Config'deki requirements kullan, client'tan gelen data.requirements yerine
    local canCraft = HasCraftRequirements(Player, scaledRequirements, craftSource)

    if canCraft then
        if craftSource then
            local removedRequirements = {}
            for _, req in pairs(scaledRequirements) do
                local removed = exports.ox_inventory:RemoveItem(craftSource.stashId, req.item, req.amount)
                if not removed then
                    for _, rollback in ipairs(removedRequirements) do
                        exports.ox_inventory:AddItem(craftSource.stashId, rollback.item, rollback.amount)
                    end
                    TriggerClientEvent('QBCore:Functions:Notify', src, "Depodaki malzemeler güncellendi, craft iptal edildi.", "error")
                    return
                end

                table.insert(removedRequirements, {
                    item = req.item,
                    amount = req.amount
                })
            end

            local added = exports.ox_inventory:AddItem(craftSource.stashId, validRecipe.item, craftedAmount)
            if not added then
                for _, rollback in ipairs(removedRequirements) do
                    exports.ox_inventory:AddItem(craftSource.stashId, rollback.item, rollback.amount)
                end
                TriggerClientEvent('QBCore:Functions:Notify', src, "Üretilen eşya depoya eklenemediği için işlem geri alındı.", "error")
                return
            end

            TriggerClientEvent('QBCore:Functions:Notify', src, (validRecipe.label or validRecipe.item) .. " " .. craftSource.label .. " içinde üretildi!", "success")
            TriggerClientEvent('gs-survival:client:refreshCraftMenuCounts', src, craftSource.side)
            return
        end

        for _, req in pairs(scaledRequirements) do
            Player.Functions.RemoveItem(req.item, req.amount)
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[req.item], "remove")
        end
        Player.Functions.AddItem(validRecipe.item, craftedAmount)
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[validRecipe.item], "add")
        TriggerClientEvent('QBCore:Functions:Notify', src, (validRecipe.label or validRecipe.item) .. " üretildi!", "success")
    else
        TriggerClientEvent('QBCore:Functions:Notify', src, craftSource and "Seçili ARC deposunda yeterli malzeme yok!" or "Yeterli malzemen yok!", "error")
    end
end)

local arcBarricadeItemName = GetArcBarricadeConfig().Item or 'arc_barricade_kit'

QBCore.Functions.CreateUseableItem(arcBarricadeItemName, function(source, item)
    TriggerClientEvent('gs-survival:client:useArcBarricadeKit', source, {
        slot = item and item.slot or nil
    })
end)

RegisterNetEvent('gs-survival:server:requestArcBarricadeSync', function()
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)

    if GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
        return TriggerClientEvent('gs-survival:client:syncArcBarricades', src, {})
    end

    SyncArcBarricadesToPlayer(src, bucketId)
end)

RegisterNetEvent('gs-survival:server:placeArcBarricade', function(data)
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)
    local config = GetArcBarricadeConfig()
    local itemName = config.Item or arcBarricadeItemName
    local model = config.Model
    local placementCoords = ToVector3(data and data.coords)
    local placementHeading = tonumber(data and data.heading or 0.0) or 0.0
    local maxRaidBarricades = math.max(1, math.floor(tonumber(config.MaxPerRaid) or 16))
    local maxPlayerBarricades = math.max(1, math.floor(tonumber(config.MaxPerPlayer) or 2))
    local interactDistance = math.max(1.0, tonumber(config.InteractDistance) or 4.0)
    local minSpacing = math.max(0.5, tonumber(config.MinSpacing) or 2.5)

    if GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' or not IsArcActivePlayer(bucketId, src) then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Barricade kit sadece aktif ARC oyuncuları tarafından kullanılabilir.", "error")
        return
    end

    if not placementCoords or not model or not IsPlayerNearCoords(src, placementCoords, interactDistance) then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Barricade için geçerli bir yer seçmedin.", "error")
        return
    end

    local totalBarricades, playerBarricades = CountArcBarricades(bucketId, src)
    if totalBarricades >= maxRaidBarricades then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Bu ARC baskınında daha fazla barricade kurulamıyor.", "error")
        return
    end

    if playerBarricades >= maxPlayerBarricades then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Kendi barricade limitine ulaştın.", "error")
        return
    end

    for _, barricadeState in pairs(arcPlacedBarricades[bucketId] or {}) do
        local existingCoords = ToVector3(barricadeState.coords)
        if existingCoords and #(placementCoords - existingCoords) < minSpacing then
            TriggerClientEvent('QBCore:Functions:Notify', src, "Barricade'ler birbirine çok yakın olamaz.", "error")
            return
        end
    end

    local removeSlot = tonumber(data and data.slot or nil)
    if removeSlot and removeSlot <= 0 then
        removeSlot = nil
    end
    local removed = exports.ox_inventory:RemoveItem(src, itemName, 1, nil, removeSlot)
    if not removed then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            removed = Player.Functions.RemoveItem(itemName, 1, removeSlot)
            if removed and QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[itemName] then
                TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], "remove")
            end
        end
    end

    if not removed then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Barricade kit envanterinde bulunamadı.", "error")
        return
    end

    arcPlacedBarricades[bucketId] = arcPlacedBarricades[bucketId] or {}
    local barricadeId = ("arc_barricade_%s_%s"):format(bucketId, nextArcBarricadeId)
    nextArcBarricadeId = nextArcBarricadeId + 1
    arcPlacedBarricades[bucketId][barricadeId] = {
        coords = {
            x = placementCoords.x,
            y = placementCoords.y,
            z = placementCoords.z
        },
        heading = placementHeading,
        model = model,
        ownerId = src
    }

    BroadcastArcBarricade(bucketId, barricadeId)
    TriggerClientEvent('QBCore:Functions:Notify', src, (config.Label or "ARC Barricade Kit") .. " kuruldu.", "success")
end)

RegisterNetEvent('gs-survival:server:buyUpgrade', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local upgradeId = data.type -- Config'deki anahtar (armor veya weapon)
    local upgradeData = Config.Upgrades[upgradeId]

    -- [GÜVENLİK]: Config'de böyle bir ürün var mı?
    if not upgradeData then
        print("^1[HATA]^7 Gecersiz market urunu: " .. tostring(upgradeId))
        return
    end

    local cid = Player.PlayerData.citizenid
    local price = upgradeData.price
    local value = upgradeData.value
    local metaName = upgradeData.metadataName
    local sqlCol = upgradeData.sqlColumn

    -- [GÜVENLİK]: SQL sütun adı whitelist kontrolü — Config.Upgrades'tan türetilir (SQL injection koruması)
    local allowedColumns = {}
    for _, v in pairs(Config.Upgrades) do
        if v.sqlColumn then allowedColumns[v.sqlColumn] = true end
    end
    if not allowedColumns[sqlCol] then
        print("^1[HATA]^7 Gecersiz SQL kolonu: " .. tostring(sqlCol))
        return
    end

    -- [SAHİPLİK KONTROLÜ]: Zaten sahip mi?
    local currentUpgrade = Player.PlayerData.metadata[metaName]
    if currentUpgrade == value then
        return TriggerClientEvent('ox_lib:notify', src, {
            title = 'Survival Market',
            description = 'Zaten bu geliştirmeye sahipsin!',
            type = 'error'
        })
    end

    -- [ÖDEME VE KAYIT]
    if Player.Functions.RemoveMoney('cash', price, "survival-upgrade") or Player.Functions.RemoveMoney('bank', price, "survival-upgrade") then

        -- 1. RAM Güncelle (Metadata)
        Player.Functions.SetMetaData(metaName, value)

        -- 2. SQL Güncelle (oxmysql)
        local query = string.format('UPDATE players SET %s = ? WHERE citizenid = ?', sqlCol)
        exports.oxmysql:update(query, {value, cid}, function(affectedRows)
            if affectedRows > 0 then
                print(string.format("^2[SUCCESS]^7 %s guncellendi: %s", metaName, cid))
            end
        end)

        Player.Functions.Save()

        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Survival Market',
            description = upgradeData.label .. ' satın alındı!',
            type = 'success'
        })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Survival Market',
            description = 'Yeterli paran yok! Gereken: $' .. price,
            type = 'error'
        })
    end
end)

ResetBucketState = function(bucketId)
    if not bucketId then return end
    groupMembers[bucketId] = nil
    groupSizes[bucketId] = nil
    lobbyStage[bucketId] = nil
    bucketModes[bucketId] = nil
    openedArcContainers[bucketId] = nil
    arcDeathContainers[bucketId] = nil
    arcPlacedBarricades[bucketId] = nil
    eliminatedArcPlayers[bucketId] = nil
    arcRaidState[bucketId] = nil
    arcRaidParticipants[bucketId] = nil
    arcSessionAdmission[bucketId] = nil
    arcSessionEliminations[bucketId] = nil
    arcSessionExtractions[bucketId] = nil
    arcSessionDisconnects[bucketId] = nil
    arcRaidSquads[bucketId] = nil
    arcRaidPlayerProfiles[bucketId] = nil
    arcPendingReconnectCounts[bucketId] = nil
    bucketWaveState[bucketId] = nil

    for playerId, indexedBucketId in pairs(arcPlayerBucketIndex) do
        if tonumber(indexedBucketId) == tonumber(bucketId) then
            arcPlayerBucketIndex[playerId] = nil
        end
    end

    openedNpcLoot[bucketId] = nil

    arcFinalizeLocks[bucketId] = nil
end

local function RestoreBaseInventoryState(targetId, modeId)
    local TPlayer = QBCore.Functions.GetPlayer(targetId)
    if not TPlayer then return nil end

    local cid = TPlayer.PlayerData.citizenid
    local resolvedModeId = GetGameModeId(modeId)
    local backupStashId = GetBackupStashId(resolvedModeId, cid)

    ClearAllModeState(TPlayer)
    TPlayer.Functions.Save()

    TriggerClientEvent('gs-survival:client:cleanupBeforeLeave', targetId)
    TriggerClientEvent('ox_inventory:disarm', targetId)
    if arcDisconnectStates[cid] and arcDisconnectStates[cid].allowRejoin == true and arcDisconnectStates[cid].resolved ~= true then
        AdjustArcPendingReconnectCount(arcDisconnectStates[cid].bucketId, -1)
    end
    arcDisconnectStates[cid] = nil

    return TPlayer, cid, backupStashId, exports.ox_inventory:GetInventoryItems(targetId)
end

local function RestoreSurvivalInventory(targetId, victoryStatus, modeId)
    local TPlayer, cid, backupStashId, currentInv = RestoreBaseInventoryState(targetId, modeId)
    if not TPlayer then return end

    local itemsToKeep = {}
    if victoryStatus and currentInv then
        for _, item in pairs(currentInv) do
            if lootItemSet[item.name] or (Config.SpecialLootItems and Config.SpecialLootItems[item.name]) then
                table.insert(itemsToKeep, { name = item.name, count = item.count, metadata = item.metadata })
            end
        end
    end

    exports.ox_inventory:ClearInventory(targetId)
    Wait(600)
    SetPlayerRoutingBucket(targetId, 0)
    SetArcPlayerBucketIndex(targetId, nil)
    Wait(200)

    if playerBackups[cid] then
        for _, item in pairs(playerBackups[cid]) do
            exports.ox_inventory:AddItem(targetId, item.name, item.count, item.metadata)
        end
        playerBackups[cid] = nil
    end

    exports.ox_inventory:ClearInventory(backupStashId)

    for _, loot in pairs(itemsToKeep) do
        exports.ox_inventory:AddItem(targetId, loot.name, loot.count, loot.metadata)
    end
end

local function RestoreArcInventory(targetId, victoryStatus, modeId)
    local TPlayer, cid, backupStashId, currentInv = RestoreBaseInventoryState(targetId, modeId)
    if not TPlayer then return end

    if victoryStatus and currentInv then
        local mainStashId = RegisterArcMainStash(TPlayer)
        if mainStashId then
            for _, item in pairs(currentInv) do
                exports.ox_inventory:AddItem(mainStashId, item.name, item.count, item.metadata)
            end
        else
            print(string.format("^1[ARC PVP]^7 Ana stash kaydı başarısız: %s", tostring(cid)))
            TriggerClientEvent('QBCore:Functions:Notify', targetId, "Arc ana stash açılamadı, loot aktarımı yapılamadı.", "error")
        end
    end

    exports.ox_inventory:ClearInventory(targetId)
    Wait(600)
    SetPlayerRoutingBucket(targetId, 0)
    SetArcPlayerBucketIndex(targetId, nil)
    Wait(200)

    if playerBackups[cid] then
        for _, item in pairs(playerBackups[cid]) do
            exports.ox_inventory:AddItem(targetId, item.name, item.count, item.metadata)
        end
        playerBackups[cid] = nil
    end

    exports.ox_inventory:ClearInventory(backupStashId)
end

RestorePlayerInventory = function(targetId, victoryStatus, modeId)
    if GetGameModeId(modeId) == 'arc_pvp' then
        RestoreArcInventory(targetId, victoryStatus, modeId)
        return
    end

    RestoreSurvivalInventory(targetId, victoryStatus, modeId)
end

local function HandleArcDisconnect(source, bucketId, reason)
    local Player = QBCore.Functions.GetPlayer(source)
    local profile = GetArcRaidPlayerProfile(bucketId, source)
    local cid = Player and Player.PlayerData and Player.PlayerData.citizenid or (profile and profile.citizenid) or nil
    if not cid or cid == '' then return end

    local policy = GetArcDisconnectPolicy()
    local policyInfo = BuildArcDisconnectPolicyInfo(policy)
    local admissionSettings = GetArcAdmissionSettings()
    local allowRejoin = policy == 'rejoin' and admissionSettings.rejoinPolicy == 'same_session_only'
    local playerPed = GetPlayerPed(source)
    local lastCoords = playerPed ~= 0 and Vector3ToTable(GetEntityCoords(playerPed)) or nil

    local previousDisconnectState = arcDisconnectStates[cid]
    if previousDisconnectState and previousDisconnectState.allowRejoin == true and previousDisconnectState.resolved ~= true then
        AdjustArcPendingReconnectCount(previousDisconnectState.bucketId, -1)
    end

    arcDisconnectStates[cid] = {
        bucketId = bucketId,
        citizenId = cid,
        policy = policyInfo.key,
        policyLabel = policyInfo.label,
        reason = tostring(reason or 'disconnect'),
        disconnectedAt = os.time(),
        extraction = BuildArcExtractionDisconnectState(bucketId),
        allowRejoin = allowRejoin,
        resolved = false,
        playerName = profile and profile.name or BuildArcPlayerDisplayName(Player, source),
        lastCoords = lastCoords,
        squadMembers = GetArcRaidSquadMembers(bucketId, source)
    }

    eliminatedArcPlayers[bucketId] = eliminatedArcPlayers[bucketId] or {}
    eliminatedArcPlayers[bucketId][source] = true
    EnsureArcSessionAdmissionState(bucketId)
    MarkArcSessionPlayerHistory(arcSessionDisconnects, bucketId, source, cid, {
        at = os.time(),
        reason = tostring(reason or 'disconnect')
    })
    if policy == 'death' then
        MarkArcSessionPlayerHistory(arcSessionEliminations, bucketId, source, cid, {
            at = os.time(),
            reason = 'disconnect_policy_death'
        })
    end
    if allowRejoin then
        AdjustArcPendingReconnectCount(bucketId, 1)
    end

    FinalizeArcExtractionResult(source, 'disconnected', bucketId)
    return arcDisconnectStates[cid]
end

local function RejoinArcDisconnectedPlayer(source, Player, disconnectState)
    if not Player or not disconnectState then
        return false, "ARC geri dönüş verisi bulunamadı."
    end

    local cid = Player.PlayerData.citizenid
    local bucketId = tonumber(disconnectState.bucketId)
    local canRejoin, rejoinError = CanPlayerRejoinArcSession(bucketId, source, cid)
    if not canRejoin then
        return false, rejoinError
    end

    groupMembers[bucketId] = groupMembers[bucketId] or {}
    if not IsPlayerInList(groupMembers[bucketId], source) then
        groupMembers[bucketId][#groupMembers[bucketId] + 1] = source
    end
    groupSizes[bucketId] = #groupMembers[bucketId]
    SetArcPlayerBucketIndex(source, bucketId)

    AddArcRaidPlayerToSquad(bucketId, source, disconnectState.squadMembers)
    RememberArcRaidPlayerProfile(bucketId, source, Player)

    eliminatedArcPlayers[bucketId] = eliminatedArcPlayers[bucketId] or {}
    eliminatedArcPlayers[bucketId][source] = nil
    ClearArcSessionPlayerHistory(arcSessionDisconnects, bucketId, source, cid)

    local deploymentState = BuildArcJoinDeploymentPayload(bucketId)
    local rejoinCoords = disconnectState.lastCoords
        or (deploymentState and deploymentState.insertion)
        or (arcRaidState[bucketId] and arcRaidState[bucketId].deployment and arcRaidState[bucketId].deployment.insertion)
        or (arcRaidState[bucketId] and arcRaidState[bucketId].deployment and arcRaidState[bucketId].deployment.center)

    SetPlayerRoutingBucket(source, bucketId)
    SetArcPlayerBucketIndex(source, bucketId)
    if rejoinCoords and rejoinCoords.x and rejoinCoords.y and rejoinCoords.z then
        SetEntityCoords(GetPlayerPed(source), rejoinCoords.x, rejoinCoords.y, rejoinCoords.z)
    end

    TriggerClientEvent('hospital:client:Revive', source)
    TriggerClientEvent('gs-survival:client:initArcPvP', source, bucketId, GetArcRaidSquadMembers(bucketId, source), groupMembers[bucketId], GetArcRaidStageId(bucketId), deploymentState, {
        wasReconnect = true,
        coords = rejoinCoords
    })

    disconnectState.resolved = true
    if disconnectState.allowRejoin == true then
        AdjustArcPendingReconnectCount(bucketId, -1)
    end
    arcDisconnectStates[cid] = nil

    SyncArcRaidPlayers(bucketId)
    SyncArcExtractionState(bucketId, {
        message = ("%s ARC baskınına yeniden bağlandı."):format(GetArcPlayerName(source)),
        type = "success"
    })

    return true
end

local function ResolveReconnectRestoreItems(stashItems, cid)
    local normalizedStashItems = NormalizeInventoryItems(stashItems)
    if #normalizedStashItems > 0 then
        return normalizedStashItems, 'stash'
    end

    local memoryBackupItems = NormalizeInventoryItems(playerBackups[cid])
    if #memoryBackupItems > 0 then
        return memoryBackupItems, 'memory'
    end

    return {}, nil
end

local function FinalizeArcReconnectCleanup(source, Player, cid, backupStashId, disconnectState)
    playerBackups[cid] = nil
    exports.ox_inventory:ClearInventory(backupStashId)

    if GetPlayerRoutingBucket(source) ~= 0 then
        SetPlayerRoutingBucket(source, 0)
        SetArcPlayerBucketIndex(source, nil)
    end

    TriggerClientEvent('gs-survival:client:cleanupBeforeLeave', source)
    TriggerClientEvent('ox_inventory:disarm', source)

    ClearAllModeState(Player)
    Player.Functions.Save()

    if disconnectState and disconnectState.bucketId then
        disconnectState.resolved = true
        ClearArcSessionPlayerHistory(arcSessionDisconnects, disconnectState.bucketId, source, cid)
        CleanupArcSessionIfAbandoned(disconnectState.bucketId)
    end

    arcDisconnectStates[cid] = nil
end

local function RestoreArcDisconnectBaseInventory(source, Player, cid, backupStashId, disconnectState, backupItems)
    exports.ox_inventory:ClearInventory(source)
    Wait(250)

    for _, item in ipairs(backupItems or {}) do
        exports.ox_inventory:AddItem(source, item.name, item.count, item.metadata)
    end

    FinalizeArcReconnectCleanup(source, Player, cid, backupStashId, disconnectState)
end

local ArcLockerHelpers = {
    metadataMaxDepth = 12
}

function ArcLockerHelpers.NormalizeSide(side, fallbackSide)
    if side == 'loadout' or side == 'main' then
        return side
    end
    return fallbackSide == 'loadout' and 'loadout' or 'main'
end

function ArcLockerHelpers.FindItemBySlot(stashId, slot)
    if not stashId or not slot then return nil end

    for _, item in pairs(exports.ox_inventory:GetInventoryItems(stashId) or {}) do
        if tonumber(item and item.slot or 0) == tonumber(slot) then
            return item
        end
    end

    return nil
end

function ArcLockerHelpers.MetadataEqual(a, b, depth, seen)
    depth = tonumber(depth) or 0
    seen = seen or {}

    if a == b then
        return true
    end

    -- ARC locker metadata is expected to stay shallow; cap recursion to avoid pathological nesting/cycles.
    if depth > ArcLockerHelpers.metadataMaxDepth then
        return false
    end

    if type(a) ~= type(b) then
        return false
    end

    if type(a) ~= 'table' then
        return a == b
    end

    if seen[a] and seen[a] == b then
        return true
    end
    seen[a] = b

    for key, value in pairs(a) do
        if not ArcLockerHelpers.MetadataEqual(value, b[key], depth + 1, seen) then
            return false
        end
    end

    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end

    return true
end

function ArcLockerHelpers.GetStackState(itemName)
    local oxItem = (exports.ox_inventory:Items() or {})[itemName] or {}
    return oxItem.weapon == true
end

function ArcLockerHelpers.BuildTransferRequest(fromSide, slot, requestedAmount, toSide, targetSlot)
    return {
        fromSide = ArcLockerHelpers.NormalizeSide(fromSide, 'main'),
        toSide = toSide == nil and nil or ArcLockerHelpers.NormalizeSide(toSide, fromSide == 'loadout' and 'main' or 'loadout'),
        slot = tonumber(slot),
        targetSlot = tonumber(targetSlot),
        requestedAmount = tonumber(requestedAmount),
        mode = tonumber(requestedAmount) and 'partial' or 'full_stack'
    }
end

function ArcLockerHelpers.ResolveTransferCount(selectedItem, request)
    local fullCount = tonumber(selectedItem and selectedItem.count or 0) or 0
    if fullCount <= 0 then
        return 0, 'missing'
    end

    if request and request.mode == 'partial' and request.requestedAmount and request.requestedAmount > 0 and request.requestedAmount < fullCount then
        return math.floor(request.requestedAmount), 'partial'
    end

    return fullCount, 'full_stack'
end

FinalizeArcMatch = function(bucketId, winners, reason)
    if not bucketId or arcFinalizeLocks[bucketId] then
        return
    end

    arcFinalizeLocks[bucketId] = true
    local members = groupMembers[bucketId] or {}
    local winnerLookup = {}

    if type(winners) == 'table' then
        for _, playerId in ipairs(winners) do
            winnerLookup[tonumber(playerId)] = true
 end
    elseif winners then
        winnerLookup[tonumber(winners)] = true
    end

    CleanupArcExtraction(bucketId)
    CleanBucketEntities(bucketId)

    for _, playerId in ipairs(members) do
        local isWinner = winnerLookup[tonumber(playerId)] == true
        FinalizeArcExtractionResult(playerId, isWinner and 'extracted' or (reason == 'failed_to_extract' and 'failed_to_extract' or 'left_raid'), bucketId)
        RestorePlayerInventory(playerId, isWinner, 'arc_pvp')
        TriggerClientEvent('gs-survival:client:stopEverything', playerId, isWinner, 'arc_pvp')
        if isWinner then
            local successText = reason == 'timeout'
                and "Baskın süresi doldu, hayatta kalan ekipman ana depoya aktarıldı."
                or reason == 'extraction'
                and "Tahliye başarılı. Baskında taşıdığın ekipman ana depoya aktarıldı."
                or "ARC baskını başarıyla tamamlandı. Taşıdığın ekipman ana depoya aktarıldı."
            TriggerClientEvent('QBCore:Functions:Notify', playerId, successText, "success")
        else
            local failureText = reason == 'failed_to_extract'
                and "Tahliye penceresi kapandı. Saha dışına çıkamadığın için hazırladığın yük kaybedildi."
                or "ARC baskını başarısız oldu. Hazırladığın yük kaybedildi."
            TriggerClientEvent('QBCore:Functions:Notify', playerId, failureText, "error")
        end
    end

    ResetBucketState(bucketId)
    arcFinalizeLocks[bucketId] = nil
end
-- [Bitiş ve Geri Yükleme]
RegisterNetEvent('gs-survival:server:finishSurvival', function(isVictory)
    local src = source
    -- Aynı oyuncu için çift tetiklenmeyi önle
    if finishingPlayers[src] then return end
    finishingPlayers[src] = true
    Citizen.SetTimeout(5000, function() finishingPlayers[src] = nil end)

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then finishingPlayers[src] = nil return end

    local bucketId = GetPlayerRoutingBucket(src)
    local modeId = GetGameModeId(bucketModes[bucketId])

    if modeId == 'arc_pvp' then
        finishingPlayers[src] = nil
        return
    end

    local isActuallyDead = false
    if Player.PlayerData and Player.PlayerData.metadata then
       isActuallyDead = Player.PlayerData.metadata["isdead"] or Player.PlayerData.metadata["inlaststand"]
    end

    local status = isVictory
    if isActuallyDead then status = false end

    if status then
        local playedStage = lobbyStage[bucketId] or 1
        local currentWave = bucketWaveState[bucketId] or 0
        local maxWaves = GetClassicMaxWaveForStage(playedStage)
        local hasAliveNpc = CountAliveBucketNpcs(bucketId) > 0
        if currentWave <= 0 or currentWave < maxWaves or hasAliveNpc then
            status = false
        end
    end

    if isActuallyDead then
        local allDead = true
        if groupMembers[bucketId] then
            for _, playerId in ipairs(groupMembers[bucketId]) do
                local pData = QBCore.Functions.GetPlayer(playerId)
                if pData and pData.PlayerData and pData.PlayerData.metadata then
                    if not (pData.PlayerData.metadata["isdead"] or pData.PlayerData.metadata["inlaststand"]) then
                        allDead = false
                        break
                    end
                end
            end
        end

        if allDead then
            CleanBucketEntities(bucketId)
            if groupMembers[bucketId] then
                for _, playerId in ipairs(groupMembers[bucketId]) do
                    RestorePlayerInventory(playerId, false, modeId)
                    TriggerClientEvent('gs-survival:client:stopEverything', playerId, false)
                end
            end
            ResetBucketState(bucketId)
        end
    elseif status then
        -- [DURUM 3]: ZAFER DURUMU
        local isLastPerson = false
        if not groupMembers[bucketId] or #groupMembers[bucketId] <= 1 then
            CleanBucketEntities(bucketId)
            isLastPerson = true
        end

        -- [DÜZELTME]: Seviye Atlatma ve SQL Kaydı
        local playedStage = lobbyStage[bucketId] or 1
        local survivalMetadata = GetModeMetadata('classic')
        local currentLevel = Player.PlayerData.metadata[survivalMetadata.level or "survival_level"] or 1

        if playedStage == currentLevel then
            local nextLevel = currentLevel + 1
            Player.Functions.SetMetaData(survivalMetadata.level or "survival_level", nextLevel)

            -- BURASI EKLENDİ: Metadata ile yetinmeyip direkt DB'ye yazıyoruz
            exports.oxmysql:update('UPDATE players SET survival_level = ? WHERE citizenid = ?', {nextLevel, Player.PlayerData.citizenid})
            Player.Functions.Save()
        end

        RestorePlayerInventory(src, true, modeId)
        TriggerClientEvent('gs-survival:client:stopEverything', src, true)

        if groupMembers[bucketId] then
            for i, id in ipairs(groupMembers[bucketId]) do
                if id == src then table.remove(groupMembers[bucketId], i) break end
            end
        end

        if isLastPerson then
            ResetBucketState(bucketId)
        end
    else
        -- [DURUM 4]: ALANDAN KAÇMA VEYA DİĞER DURUMLAR
        local isLastPerson = false
        if not groupMembers[bucketId] or #groupMembers[bucketId] <= 1 then
            CleanBucketEntities(bucketId)
            isLastPerson = true
        end

        RestorePlayerInventory(src, false, modeId)
        TriggerClientEvent('gs-survival:client:stopEverything', src, false)

        if groupMembers[bucketId] then
            for i, id in ipairs(groupMembers[bucketId]) do
                if id == src then table.remove(groupMembers[bucketId], i) break end
            end
        end

        if isLastPerson then
            ResetBucketState(bucketId)
        end
    end
end)

-- [OYUNDAN ÇIKTIĞINDA]
AddEventHandler('playerDropped', function(reason)
    local src = source

    -- 1. [LOBİ TEMİZLİĞİ] (Maç başlamadan önceki lobi aşaması için)
    if activeLobbies[src] then
        for memberId, _ in pairs(activeLobbies[src].members) do
            TriggerClientEvent('gs-survival:client:setReadyState', memberId, false)
            TriggerClientEvent('gs-survival:client:forceLeaveLobby', memberId)
        end
        activeLobbies[src] = nil
    end

    -- Eğer bu kişi bir liderin davetli listesindeyse onu sil
    for leaderId, data in pairs(activeLobbies) do
        if data.members and data.members[src] then
            data.members[src] = nil
            -- Lidere arkadaşının çıktığını haber ver
            TriggerClientEvent('QBCore:Functions:Notify', leaderId, "Bir grup üyesi sunucudan ayrıldı.", "error")
            -- Liderin ekranındaki (invitedPlayers) listesini güncelle
            TriggerClientEvent('gs-survival:client:removeFromInvited', leaderId, src)
            SyncLobbyMembers(leaderId)
            break
        end
    end

    -- 2. [MAÇ TEMİZLİĞİ] (Senin mevcut bucket mantığın)
    local bucketId = GetPlayerRoutingBucket(src)
    if bucketId == 0 or not (groupMembers and groupMembers[bucketId]) then
        bucketId = FindArcBucketByPlayer(src)
    end
    if bucketId ~= 0 and groupMembers and groupMembers[bucketId] then
        if GetGameModeId(bucketModes[bucketId]) == 'arc_pvp' then
            local disconnectState = HandleArcDisconnect(src, bucketId, reason)
            local droppedProfile = GetArcRaidPlayerProfile(bucketId, src)
            local droppedName = disconnectState and disconnectState.playerName or (droppedProfile and droppedProfile.name) or ("ID " .. tostring(src))
            local disconnectInfo = BuildArcDisconnectPolicyInfo()
            for _, playerId in ipairs(groupMembers[bucketId]) do
                if tonumber(playerId) ~= tonumber(src) then
                    TriggerClientEvent('QBCore:Functions:Notify', playerId, ("%s bağlantı kaybetti. Aktif policy: %s."):format(droppedName, disconnectInfo.label), "primary")
                end
            end
        end

        RemoveArcRaidPlayer(bucketId, src)
        local pendingReconnects = GetArcPendingReconnectCount(bucketId)

        if #groupMembers[bucketId] > 0 then
            SyncArcRaidPlayers(bucketId)
            if GetGameModeId(bucketModes[bucketId]) == 'arc_pvp' and #GetArcAlivePlayers(bucketId) == 0 and pendingReconnects == 0 then
                FinalizeArcMatch(bucketId, {}, 'disconnect')
                return
            end
        end

        -- Eğer odada kimse kalmadıysa dünyayı temizle
        if #groupMembers[bucketId] == 0 then
            if GetGameModeId(bucketModes[bucketId]) == 'arc_pvp' and pendingReconnects > 0 then
                local admissionState = EnsureArcSessionAdmissionState(bucketId)
                if admissionState then
                    admissionState.phase = 'awaiting_rejoin'
                    admissionState.reason = 'awaiting_rejoin'
                end
                return
            end
            CleanupArcExtraction(bucketId)
            CleanBucketEntities(bucketId)
            ResetBucketState(bucketId)
        end
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    CreateThread(function()
        Wait(2000)
        for _, playerId in ipairs(GetPlayers()) do
            RetryRecoverPlayerAfterResourceRestart(playerId, 10, 3000)
        end
    end)
end)
-- [TEKRAR GİRDİĞİNDE EŞYALARI GERİ VERME]
QBCore.Functions.CreateCallback('gs-survival:server:checkReconnectBackup', function(source, cb, reconnectAction)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return cb({ restored = false }) end

    local cid = Player.PlayerData.citizenid
    local disconnectState = arcDisconnectStates[cid]
    local savedModeId = disconnectState and 'arc_pvp' or nil
    local activeModeId = ResolvePlayerActiveModeState(src, Player) or GetActiveModeId(Player)
    local modeId = savedModeId or activeModeId or 'classic'
    local stashId = GetBackupStashId(modeId, cid)
    local disconnectInfo = disconnectState and BuildArcDisconnectPolicyInfo(disconnectState.policy) or nil
    local hasArcReconnectState = modeId == 'arc_pvp'
    reconnectAction = type(reconnectAction) == 'string' and reconnectAction:lower() or nil

    -- Stash'i kayıt et ve mevcut içeriğini kontrol et
    RegisterBackupStash(modeId, stashId)
    local items = exports.ox_inventory:GetInventoryItems(stashId)

    if not IsModeActive(Player, modeId) and not hasArcReconnectState then
        -- Stash'te arta kalan eşya varsa sessizce temizle, bildirim gösterme
        if items and next(items) then
            exports.ox_inventory:ClearInventory(stashId)
        end
        if playerBackups[cid] then playerBackups[cid] = nil end
        if disconnectState and disconnectState.bucketId then
            disconnectState.resolved = true
            ClearArcSessionPlayerHistory(arcSessionDisconnects, disconnectState.bucketId, src, cid)
            CleanupArcSessionIfAbandoned(disconnectState.bucketId)
        end
        if arcDisconnectStates[cid] and arcDisconnectStates[cid].allowRejoin == true and arcDisconnectStates[cid].resolved ~= true then
            AdjustArcPendingReconnectCount(arcDisconnectStates[cid].bucketId, -1)
        end
        arcDisconnectStates[cid] = nil
        return cb({ restored = false })
    end

    if modeId == 'arc_pvp' and disconnectState and disconnectState.allowRejoin == true then
        if reconnectAction == 'rejoin' then
            local rejoined, rejoinError = RejoinArcDisconnectedPlayer(src, Player, disconnectState)
            if rejoined then
                return cb({
                    restored = false,
                    rejoined = true,
                    modeId = modeId,
                    disconnectPolicy = disconnectInfo and disconnectInfo.key or nil,
                    disconnectPolicyLabel = disconnectInfo and disconnectInfo.label or nil,
                    extraction = disconnectState.extraction or nil,
                    message = "ARC baskınına aynı session üzerinden geri bağlandın."
                })
            end

            disconnectState.rejoinError = rejoinError
        elseif reconnectAction == 'decline' then
            disconnectState.rejoinError = "ARC baskınına geri katılmayı reddettin"
        else
            local canRejoin, rejoinError = CanPlayerRejoinArcSession(tonumber(disconnectState.bucketId), src, cid)
            if canRejoin then
                return cb({
                    restored = false,
                    rejoined = false,
                    promptRejoin = true,
                    modeId = modeId,
                    disconnectPolicy = disconnectInfo and disconnectInfo.key or nil,
                    disconnectPolicyLabel = disconnectInfo and disconnectInfo.label or nil,
                    extraction = disconnectState.extraction or nil,
                    title = "Oyuna geri katılmak ister misin?",
                    message = "ARC baskınına aynı oturum üzerinden son düştüğün yerden geri dönebilirsin."
                })
            end

            disconnectState.rejoinError = rejoinError
        end
    end

    local backupItems, backupSource = ResolveReconnectRestoreItems(items, cid)

    if modeId == 'arc_pvp' and disconnectInfo and disconnectInfo.key == 'death' then
        RestoreArcDisconnectBaseInventory(src, Player, cid, stashId, disconnectState, backupItems)
        return cb({
            restored = true,
            modeId = modeId,
            disconnectPolicy = disconnectInfo.key,
            disconnectPolicyLabel = disconnectInfo.label,
            extraction = disconnectState and disconnectState.extraction or nil,
            message = #backupItems > 0
                and "Bağlantı kopması ARC ölümü sayıldı. Baskın yükün silindi ve baskın öncesi envanterin geri verildi."
                or "Bağlantı kopması ARC ölümü sayıldı. Baskın yükün silindi ve aktif durumun temizlendi."
        })
    end

    if #backupItems > 0 then
        RestoreArcDisconnectBaseInventory(src, Player, cid, stashId, disconnectState, backupItems)
        return cb({
            restored = true,
            modeId = modeId,
            disconnectPolicy = disconnectInfo and disconnectInfo.key or nil,
            disconnectPolicyLabel = disconnectInfo and disconnectInfo.label or nil,
            extraction = disconnectState and disconnectState.extraction or nil,
            backupSource = backupSource,
            message = disconnectState and disconnectState.rejoinError
                and (("%s. Güvenli dönüş uygulandı ve eşyaların teslim edildi."):format(disconnectState.rejoinError))
                or (disconnectInfo and disconnectInfo.description or "Eşyaların güvenli bölgede teslim edildi.")
        })
    end

    exports.ox_inventory:ClearInventory(src)
    Wait(250)
    FinalizeArcReconnectCleanup(src, Player, cid, stashId, disconnectState)
    cb({
        restored = true,
        modeId = modeId,
        disconnectPolicy = disconnectInfo and disconnectInfo.key or nil,
        disconnectPolicyLabel = disconnectInfo and disconnectInfo.label or nil,
        extraction = disconnectState and disconnectState.extraction or nil,
        message = disconnectInfo and disconnectInfo.key == 'death'
            and "Bağlantı kopması ARC ölümü sayıldı. Baskın yükün temizlendi ve güvenli bölgeye alındın."
            or "Aktif oyun durumu temizlendi ve güvenli bölgeye alındın."
    })
end)

-- [NPC LOOT SİSTEMİ]
RegisterNetEvent('gs-survival:server:createNpcStash', function(npcNetId, currentWave) -- currentWave parametresini ekledik
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)
    local resolvedNpcNetId = tonumber(npcNetId)
    local wave = math.max(1, math.floor(tonumber(bucketWaveState[bucketId] or 1))) -- Eğer dalga bilgisi gelmezse varsayılan 1 yap

    if bucketId == 0 or not IsBucketMember(bucketId, src) or not resolvedNpcNetId then
        beingLooted[npcNetId] = nil
        return
    end

    if beingLooted[resolvedNpcNetId] ~= src then
        return
    end

    openedNpcLoot[bucketId] = openedNpcLoot[bucketId] or {}

    if openedNpcLoot[bucketId][resolvedNpcNetId] then
        beingLooted[resolvedNpcNetId] = nil
        return
    end

    local npc = NetworkGetEntityFromNetworkId(resolvedNpcNetId)
    if npc == 0 or not DoesEntityExist(npc) or GetEntityRoutingBucket(npc) ~= bucketId or not IsPedEntityDead(npc) then
        beingLooted[resolvedNpcNetId] = nil
        return
    end

    local stashId = "surv_" .. resolvedNpcNetId .. "_" .. math.random(1111, 9999)

    beingLooted[npcNetId] = nil
    openedNpcLoot[bucketId][resolvedNpcNetId] = true

    -- [DÜZENLEME]: Artık Config.Loot üzerinden değil, Config.LootTable üzerinden dönüyor
    -- 1. Stash'i oluştur
    exports.ox_inventory:RegisterStash(stashId, "Düşman Üzeri", 10, 5000)

    -- 2. Eşyaları ekle (Kısa bir beklemeyle)
    Wait(150)

    -- Dalga arttıkça genel şansı biraz artıran çarpan (Stratejik derinlik için)
    local luckMultiplier = 1.0 + (wave * 0.05)
    local possibleLoot = {}

    for _, loot in ipairs(Config.LootTable) do
        -- SADECE dalga şartı tutuyorsa veya dalga şartı hiç yoksa item düşebilir
        if not loot.minWave or wave >= loot.minWave then
            local roll = math.random(1, 100)
            -- Şans kontrolü (Dalga çarpanı ile, maksimum %100 ile sınırlandırılmış)
            if roll <= math.min(loot.chance * luckMultiplier, 100) then
                local amount = math.random(loot.min, loot.max)
                exports.ox_inventory:AddItem(stashId, loot.item, amount)
                table.insert(possibleLoot, loot.item)
            end
        end
    end

    -- Eğer şanssızlıktan hiçbir şey çıkmadıysa boş kalmasın diye ufak bir para ekle
    if #possibleLoot == 0 then
        exports.ox_inventory:AddItem(stashId, "money", math.random(50, 150))
    end

    -- 3. ÖNCE Client'a envanteri aç komutu gönder
    TriggerClientEvent('gs-survival:client:openNpcStash', src, stashId)

    -- 4. HEMEN ARDINDAN NPC'yi ve Blip'i silmesi için sadece bucket üyelerine gönder
    if groupMembers[bucketId] then
        for _, pId in pairs(groupMembers[bucketId]) do
            TriggerClientEvent('gs-survival:client:deleteNPC', pId, npcNetId)
        end
    else
        TriggerClientEvent('gs-survival:client:deleteNPC', src, npcNetId)
    end
end)

RegisterNetEvent('gs-survival:server:moveArcLockerItem', function(fromSide, slot, focusSide, toSide, targetSlot, requestedAmount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local transferRequest = ArcLockerHelpers.BuildTransferRequest(fromSide, slot, requestedAmount, toSide, targetSlot)
    fromSide = transferRequest.fromSide
    focusSide = focusSide == 'loadout' and 'loadout' or 'main'
    slot = transferRequest.slot

    local mainStashId = RegisterArcMainStash(Player)
    local loadoutStashId = RegisterArcLoadoutStash(Player)
    if not mainStashId or not loadoutStashId or not slot then
        TriggerClientEvent('QBCore:Functions:Notify', src, "ARC stash bilgisi alınamadı.", "error")
        TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
        return
    end

    local fromStashId = fromSide == 'loadout' and loadoutStashId or mainStashId
    local normalizedToSide = transferRequest.toSide or (fromSide == 'loadout' and 'main' or 'loadout')
    local toStashId = normalizedToSide == 'loadout' and loadoutStashId or mainStashId
    local fromLabel = fromSide == 'loadout' and (Config.ArcPvP.LoadoutStashLabel or "ARC Baskın Çantası") or (Config.ArcPvP.MainStashLabel or "ARC Ana Depo")
    local toLabel = normalizedToSide == 'loadout' and (Config.ArcPvP.LoadoutStashLabel or "ARC Baskın Çantası") or (Config.ArcPvP.MainStashLabel or "ARC Ana Depo")
    local selectedItem = ArcLockerHelpers.FindItemBySlot(fromStashId, slot)
    local targetInventorySlot = transferRequest.targetSlot
    local targetItem = targetInventorySlot and ArcLockerHelpers.FindItemBySlot(toStashId, targetInventorySlot) or nil
    local sameInventory = fromStashId == toStashId

    if not selectedItem or not selectedItem.name or tonumber(selectedItem.count or 0) <= 0 then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Taşınacak eşya bulunamadı.", "error")
        TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
        return
    end

    if sameInventory and (not targetInventorySlot or targetInventorySlot == slot) then
        TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
        return
    end

    local itemCount, transferMode = ArcLockerHelpers.ResolveTransferCount(selectedItem, transferRequest)
    local itemLabel = (selectedItem.metadata and selectedItem.metadata.label) or selectedItem.label or selectedItem.name
    local isWeapon = ArcLockerHelpers.GetStackState(selectedItem.name)
    local targetMetadata = targetItem and targetItem.metadata
    local transferMetadata = selectedItem.metadata

    if targetItem and not isWeapon then
        transferMetadata = targetMetadata
    end

    if targetItem then
        if targetItem.name ~= selectedItem.name then
            TriggerClientEvent('QBCore:Functions:Notify', src, "Stack için aynı tür eşyayı hedeflemelisin.", "error")
            TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
            return
        end

        if isWeapon then
            TriggerClientEvent('QBCore:Functions:Notify', src, "Silahlar üst üste konamaz.", "error")
            TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
            return
        end
    end

    if sameInventory then
        local removed = exports.ox_inventory:RemoveItem(fromStashId, selectedItem.name, itemCount, selectedItem.metadata, slot)
        if not removed then
            TriggerClientEvent('QBCore:Functions:Notify', src, "Eşya kaynağından alınamadı.", "error")
            TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
            return
        end

        local added = exports.ox_inventory:AddItem(toStashId, selectedItem.name, itemCount, transferMetadata, targetInventorySlot)
        if not added then
            exports.ox_inventory:AddItem(fromStashId, selectedItem.name, itemCount, selectedItem.metadata, slot)
            TriggerClientEvent('QBCore:Functions:Notify', src, "Eşya yeni yuvaya taşınamadı, işlem geri alındı.", "error")
            TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
            return
        end

        local actionText = targetItem and "stacklendi" or "taşındı"
        TriggerClientEvent('QBCore:Functions:Notify', src, string.format("%s x%d, aynı depo içinde %s.", itemLabel, itemCount, actionText), "success")
        TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
        return
    end

    if not exports.ox_inventory:CanCarryItem(toStashId, selectedItem.name, itemCount, transferMetadata) then
        TriggerClientEvent('QBCore:Functions:Notify', src, string.format("%s bu eşyayı taşıyamıyor.", toLabel), "error")
        TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
        return
    end

    local added = exports.ox_inventory:AddItem(toStashId, selectedItem.name, itemCount, transferMetadata, targetInventorySlot)
    if not added then
        TriggerClientEvent('QBCore:Functions:Notify', src, string.format("%s açılırken bir hata oluştu.", toLabel), "error")
        TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
        return
    end

    local removed = exports.ox_inventory:RemoveItem(fromStashId, selectedItem.name, itemCount, selectedItem.metadata, slot)
    if not removed then
        exports.ox_inventory:RemoveItem(toStashId, selectedItem.name, itemCount, transferMetadata, targetInventorySlot)
        TriggerClientEvent('QBCore:Functions:Notify', src, "Eşya taşınırken işlem geri alındı.", "error")
        TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
        return
    end

    local actionText = targetItem and "içinde stacklendi" or "içine aktarıldı"
    TriggerClientEvent('QBCore:Functions:Notify', src, string.format("%s x%d, %s içinden %s %s.", itemLabel, itemCount, fromLabel, toLabel, actionText), "success")
    TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
end)

RegisterNetEvent('gs-survival:server:openArcLootContainer', function(containerId, rollCount)
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)

    if GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Bu sandık yalnızca ARC Baskını sırasında açılabilir.", "error")
        return
    end

    if not arcRaidState[bucketId] then
        TriggerClientEvent('QBCore:Functions:Notify', src, "ARC loot verisi henüz hazır değil.", "error")
        return
    end

    local bucketContainerState = openedArcContainers[bucketId] and openedArcContainers[bucketId][containerId]
    if not containerId then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Geçersiz loot kutusu.", "error")
        return
    end

    local nodeState = GetArcLootNodeState(bucketId, containerId)
    if not nodeState then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Geçersiz loot kutusu.", "error")
        return
    end

    if not IsPlayerNearCoords(src, nodeState.coords, 4.0) then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Bu loot kutusunu açmak için yanında olmalısın.", "error")
        return
    end

    if bucketContainerState and bucketContainerState.consumed then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Bu loot kutusu zaten açıldı.", "error")
        return
    end

    local cachedLootRegionId = bucketContainerState and bucketContainerState.lootRegion or nil
    local nodeLootRegionId = nodeState and nodeState.lootRegion or nil
    local deploymentLootRegionId = arcRaidState[bucketId] and arcRaidState[bucketId].deployment and arcRaidState[bucketId].deployment.lootRegion or nil
    local lootRegionId = NormalizeArcLootRegionId(cachedLootRegionId or nodeLootRegionId or deploymentLootRegionId)

    local stashId = bucketContainerState and bucketContainerState.stashId or BuildArcLootStashId(bucketId, containerId)
    if not bucketContainerState then
        exports.ox_inventory:RegisterStash(stashId, "Arc Loot", 15, 20000)
        FillArcLootStash(stashId, rollCount, lootRegionId)
    end

    openedArcContainers[bucketId] = openedArcContainers[bucketId] or {}
    openedArcContainers[bucketId][containerId] = {
        stashId = stashId,
        consumed = true,
        lootRegion = lootRegionId
    }

    TriggerClientEvent('gs-survival:client:openArcStash', src, stashId)

    if groupMembers[bucketId] then
        for _, playerId in ipairs(groupMembers[bucketId]) do
            TriggerClientEvent('gs-survival:client:removeArcContainer', playerId, containerId)
        end
    end
end)

RegisterNetEvent('gs-survival:server:openArcDeathContainer', function(containerId)
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)

    if GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Bu düşüş kutusu yalnızca ARC Baskını sırasında açılabilir.", "error")
        return
    end

    local containerState = arcDeathContainers[bucketId] and arcDeathContainers[bucketId][containerId]
    if not containerId or not containerState or containerState.consumed or not containerState.stashId then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Bu ölüm kutusu artık kullanılamıyor.", "error")
        return
    end

    if not IsPlayerNearCoords(src, containerState.coords, 4.0) then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Bu ölüm kutusunu açmak için yanında olmalısın.", "error")
        return
    end

    containerState.consumed = true
    TriggerClientEvent('gs-survival:client:openArcStash', src, containerState.stashId)

    if groupMembers[bucketId] then
        for _, playerId in ipairs(groupMembers[bucketId]) do
            TriggerClientEvent('gs-survival:client:removeArcContainer', playerId, containerId)
        end
    end
end)

RegisterNetEvent('gs-survival:server:handleArcDeath', function(reason)
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)

    if GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' or not groupMembers[bucketId] then
        return
    end

    eliminatedArcPlayers[bucketId] = eliminatedArcPlayers[bucketId] or {}
    if eliminatedArcPlayers[bucketId][src] then
        return
    end

    eliminatedArcPlayers[bucketId][src] = true
    FinalizeArcExtractionResult(src, 'died', bucketId)

    local deathContainerId = "death_" .. tostring(src) .. "_" .. tostring(math.random(1000, 9999))
    local deathStashId = BuildArcDeathStashId(bucketId, deathContainerId)
    local deathCoords = GetEntityCoords(GetPlayerPed(src))
    local deathItems = exports.ox_inventory:GetInventoryItems(src)

    for _, playerId in ipairs(groupMembers[bucketId] or {}) do
        TriggerClientEvent('gs-survival:client:playSignalFlare', playerId, {
            coords = Vector3ToTable(deathCoords)
        })
    end

    if deathItems and next(deathItems) then
        exports.ox_inventory:RegisterStash(deathStashId, "Arc Ölüm Kutusu", 20, 25000)
        for _, item in pairs(deathItems) do
            exports.ox_inventory:AddItem(deathStashId, item.name, item.count, item.metadata)
        end

        arcDeathContainers[bucketId] = arcDeathContainers[bucketId] or {}
        arcDeathContainers[bucketId][deathContainerId] = {
            stashId = deathStashId,
            consumed = false,
            coords = Vector3ToTable(deathCoords),
            label = (reason == 'boundary' and "Sınır Dışı Düşüş" or "Oyuncu Düşüşü"),
            rollCount = 1,
            type = 'drop'
        }

        for _, playerId in ipairs(groupMembers[bucketId]) do
            TriggerClientEvent('gs-survival:client:spawnArcDeathDrop', playerId, {
                id = deathContainerId,
                coords = deathCoords,
                label = (reason == 'boundary' and "Sınır Dışı Düşüş" or "Oyuncu Düşüşü")
            })
        end
    end

    exports.ox_inventory:ClearInventory(src)

    local alivePlayers = GetArcAlivePlayers(bucketId)
    if #alivePlayers == 0 then
        FinalizeArcMatch(bucketId, {}, reason)
    end
end)

RegisterNetEvent('gs-survival:server:returnArcToLobby', function()
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)

    if GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' or not groupMembers[bucketId] then
        return
    end

    if arcFinalizeLocks[bucketId] then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Oturum kapanışı sürüyor, lobiye dönüş isteği işlenemedi.", "error")
        return
    end

    if not (eliminatedArcPlayers[bucketId] and eliminatedArcPlayers[bucketId][src]) then
        TriggerClientEvent('QBCore:Functions:Notify', src, "Lobiye sadece elendikten sonra dönebilirsin.", "error")
        return
    end

    RestorePlayerInventory(src, false, 'arc_pvp')
    TriggerClientEvent('gs-survival:client:stopEverything', src, false, 'arc_pvp')
    TriggerClientEvent('QBCore:Functions:Notify', src, "İzleme sonlandırıldı, lobiye döndün.", "primary")

    RemoveArcRaidPlayer(bucketId, src)
    eliminatedArcPlayers[bucketId][src] = nil

    if #groupMembers[bucketId] > 0 then
        SyncArcRaidPlayers(bucketId)
        SyncArcExtractionState(bucketId)
    else
        CleanupArcExtraction(bucketId)
        CleanBucketEntities(bucketId)
        ResetBucketState(bucketId)
    end
end)

-- [DOKUNULMAYAN DİĞER KODLAR]

QBCore.Functions.CreateCallback('gs-survival:server:checkLootStatus', function(source, cb, npcNetId)
    local bucketId = GetPlayerRoutingBucket(source)
    local resolvedNpcNetId = tonumber(npcNetId)

    if bucketId == 0 or not IsBucketMember(bucketId, source) or not resolvedNpcNetId then
        return cb(false)
    end

    if beingLooted[resolvedNpcNetId] and beingLooted[resolvedNpcNetId] ~= source then
        -- Eğer bu NPC zaten birisi tarafından aranıyorsa
        TriggerClientEvent('QBCore:Functions:Notify', source, "Bu ceset zaten başkası tarafından aranıyor!", "error")
        cb(false)
    else
        -- Kimse aramıyorsa, arayan kişi olarak kaydet
        beingLooted[resolvedNpcNetId] = source
        cb(true)
    end
end)


RegisterNetEvent('gs-survival:server:cancelLoot', function(npcNetId)
    local resolvedNpcNetId = tonumber(npcNetId)
    if resolvedNpcNetId then
        beingLooted[resolvedNpcNetId] = nil
    end
end)

QBCore.Functions.CreateCallback('gs-survival:server:getNearbyPlayers', function(s, cb)
    cb(BuildNearbyLobbyPlayers(s))
end)

RegisterNetEvent('gs-survival:server:giveStarterItems', function(weaponName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local bucketId = GetPlayerRoutingBucket(src)
    if bucketId == 0 or GetGameModeId(bucketModes[bucketId]) ~= 'classic' or not IsModeActive(Player, 'classic') then
        return
    end

    local survivalMetadata = GetModeMetadata('classic')
    local hasWeaponUpgrade = Player.PlayerData.metadata[survivalMetadata.weapon or 'survival_weapon'] or "weapon_pistol"

    -- Hile kontrolü ve eşya verme
    if hasWeaponUpgrade == weaponName then
        exports.ox_inventory:AddItem(src, weaponName, 1, { survivalItem = true })
        exports.ox_inventory:AddItem(src, "ammo-9", 100, { survivalItem = true })
    end
end)
