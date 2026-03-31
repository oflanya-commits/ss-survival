-- [Davetler]
RegisterNetEvent('gs-survival:server:sendInvite', function(tId)
    local src = source
    tId = tonumber(tId)
    if not tId then
        return
    end
    local lobby = activeLobbies[src]

    if not lobby then
        ServerHelpers.NotifyPlayer(src, "Önce bir lobi kurmalısın!", "error")
        return
    end

    if tonumber(tId) == tonumber(src) then
        return
    end

    if ServerHelpers.CountMembers(lobby.members) >= (MAX_LOBBY_SIZE - 1) then
        ServerHelpers.NotifyPlayer(src, "Lobi zaten dolu! (Maksimum " .. MAX_LOBBY_SIZE .. " kişi)", "error")
        return
    end

    if lobby.members[tId] then
        ServerHelpers.NotifyPlayer(src, "Bu oyuncu zaten senin lobinde.", "error")
        return
    end

    if activeLobbies[tId] or ServerHelpers.FindLobbyLeaderByMember(tId) then
        ServerHelpers.NotifyPlayer(src, "Bu oyuncunun zaten aktif bir lobisi var.", "error")
        return
    end

    local targetPlayer = QBCore.Functions.GetPlayer(tId)
    if not targetPlayer or GetPlayerRoutingBucket(tId) ~= 0 then
        ServerHelpers.NotifyPlayer(src, "Bu oyuncu şu anda ARC/lobi daveti alamaz.", "error")
        return
    end

    local canInvite, proximityError = EnsureLobbyProximity(src, tId, targetPlayer and (targetPlayer.PlayerData.charinfo.firstname .. " " .. targetPlayer.PlayerData.charinfo.lastname) or nil)
    if not canInvite then
        ServerHelpers.NotifyPlayer(src, proximityError, "error")
        return
    end

    TriggerClientEvent('gs-survival:client:receiveInvite', tId, src)
    ServerHelpers.NotifyPlayer(src, "Davet gönderildi!", "success")
end)

AddEventHandler('ox_inventory:onItemDropped', function(source, inventory, slot, item)
    -- Eğer yere atılan eşyanın metadatasında 'survivalItem' varsa
    if item.metadata and item.metadata.survivalItem then
        -- Eşyayı yerden (drop'tan) anında sil, kimse alamasın
        exports.ox_inventory:RemoveItem(inventory, item.name, item.count, item.metadata, slot)
        ServerHelpers.NotifyPlayer(source, "Survival eşyalarını yere atamazsın, eşya imha edildi!", "error")
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
    if ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' or not groupMembers[bucketId] then
        return
    end

    for _, playerId in ipairs(groupMembers[bucketId]) do
        TriggerClientEvent('gs-survival:client:updateArcRaidPlayers', playerId, ServerHelpers.GetArcRaidSquadMembers(bucketId, playerId), groupMembers[bucketId])
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
    local memberLobbyLeaderId = ServerHelpers.FindLobbyLeaderByMember(source)

    for leaderId, lobby in pairs(activeLobbies) do
        local isOwnLobby = tonumber(leaderId) == tonumber(source)
        local isJoinedLobby = tonumber(memberLobbyLeaderId) == tonumber(leaderId)
        local isPublic = lobby.isPublic == true
        local isNearbyLeader = IsPlayerWithinLobbyProximity(leaderId, source)

        if isPublic or isOwnLobby or isJoinedLobby then
            local memberCount = ServerHelpers.CountMembers(lobby.members)
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
    ServerHelpers.NotifyPlayer(leaderId, memberName .. " lobiye katıldı!", "success")
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
    if ServerHelpers.GetGameModeId(modeId) == 'arc_pvp' then
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
    if ServerHelpers.GetArcConfig().StrictDeploymentValidation ~= true then
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
