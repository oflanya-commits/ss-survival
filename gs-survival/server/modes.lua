local function StartModeOperation(src, invited, stageId, modeId)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if ServerHelpers.FindLobbyLeaderByMember(src) then
        ServerHelpers.NotifyPlayer(src, "Operasyonu yalnızca lobi lideri başlatabilir.", "error")
        return
    end

    local selectedModeId = ServerHelpers.GetGameModeId(modeId)
    if not Config.GameModes or not Config.GameModes[selectedModeId] then
        ServerHelpers.NotifyPlayer(src, "Geçersiz oyun modu!", "error")
        return
    end

    local playerLevel = GetPlayerSurvivalLevel(Player)
    local arcJoinLevel = playerLevel

    local peps, groupError = BuildStartingGroup(src, invited)
    if not peps then
        ServerHelpers.NotifyPlayer(src, groupError or "Takım oluşturulamadı.", "error")
        return
    end

    if selectedModeId == 'arc_pvp' then
        local validParticipants, validationError = ValidateArcStartParticipants(peps)
        if not validParticipants then
            ServerHelpers.NotifyPlayer(src, validationError or "ARC deploy doğrulaması başarısız.", "error")
            return
        end

        arcJoinLevel, groupError = GetMinimumPlayerSurvivalLevel(peps)
        if not arcJoinLevel then
            ServerHelpers.NotifyPlayer(src, groupError or "ARC seviye doğrulaması başarısız.", "error")
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
            ServerHelpers.NotifyPlayer(src, groupError or "ARC loadout hazırlığı eksik.", "error")
            return
        end

        local canJoinArc, admissionResult = CanLobbyJoinArcSession(peps, arcJoinLevel)
        if not canJoinArc then
            ServerHelpers.NotifyPlayer(src, admissionResult or "ARC admission doğrulaması başarısız.", "error")
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
                ServerHelpers.NotifyPlayer(src, stageError or "Geçersiz operasyon bölgesi!", "error")
                return
            end

            stageData = GetStageData(selectedModeId, resolvedStageId)
            deploymentState, groupError = BuildArcDeploymentState(stageData, resolvedStageId, bId)
            if not deploymentState then
                ServerHelpers.NotifyPlayer(src, groupError or "ARC deployment bölgesi seçilemedi.", "error")
                return
            end
        end
    else
        resolvedStageId, stageError = ResolveModeStageId(selectedModeId, stageId, playerLevel)
        if not resolvedStageId then
            ServerHelpers.NotifyPlayer(src, stageError or "Geçersiz operasyon bölgesi!", "error")
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
            if not ServerHelpers.IsPlayerInList(groupMembers[bId], playerId) then
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
        ServerHelpers.CreateArcRaidSquad(bId, peps)
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
                ServerHelpers.RememberArcRaidPlayerProfile(bId, playerId, targetPlayer)
            end

            GiveModeLoadout(playerId, targetPlayer, selectedModeId, preparedArcLoadouts and preparedArcLoadouts[playerId] and preparedArcLoadouts[playerId].items or nil)
            if selectedModeId == 'arc_pvp' and preparedArcLoadouts and preparedArcLoadouts[playerId] then
                exports.ox_inventory:ClearInventory(preparedArcLoadouts[playerId].stashId)
            end
            SetPlayerRoutingBucket(playerId, bId)
            ServerHelpers.SetArcPlayerBucketIndex(playerId, bId)

            if selectedModeId == 'arc_pvp' and deploymentState and deploymentState.insertion then
                SetEntityCoords(GetPlayerPed(playerId), deploymentState.insertion.x, deploymentState.insertion.y, deploymentState.insertion.z)
            elseif stageData and stageData.center then
                SetEntityCoords(GetPlayerPed(playerId), stageData.center.x, stageData.center.y, stageData.center.z)
            end

            TriggerClientEvent('hospital:client:Revive', playerId)
            if selectedModeId == 'arc_pvp' then
                TriggerClientEvent('gs-survival:client:initArcPvP', playerId, bId, ServerHelpers.GetArcRaidSquadMembers(bId, playerId), groupMembers[bId], resolvedStageId, deploymentState)
            else
                TriggerClientEvent('gs-survival:client:initSurvival', playerId, bId, 1, peps, resolvedStageId)
            end
        end
    end

    if selectedModeId == 'arc_pvp' then
        ServerHelpers.SyncArcRaidPlayers(bId)
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
            if not groupMembers[bId] or ServerHelpers.GetGameModeId(bucketModes[bId]) ~= 'arc_pvp' then
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
    local requestedMode = ServerHelpers.GetGameModeId(modeId or 'classic')
    if requestedMode ~= 'classic' then
        ServerHelpers.NotifyPlayer(src, "Klasik Hayatta Kalma için startSurvival, ARC Baskını için startArcPvP akışı kullanılmalıdır.", "error")
        return
    end

    local ok, err = pcall(StartModeOperation, src, invited, stageId, 'classic')
    if not ok then
        print(string.format("^1[CLASSIC START]^7 %s", tostring(err)))
        ServerHelpers.NotifyPlayer(src, "Klasik operasyon başlatılırken beklenmeyen bir hata oluştu.", "error")
    end
end)

RegisterNetEvent('gs-survival:server:startArcPvP', function(invited, stageId)
    local src = source
    local acquired, lockState = AcquireArcStartLock(src)
    if not acquired then
        ServerHelpers.NotifyPlayer(src, lockState or "ARC deploy isteği reddedildi.", "error")
        return
    end

    local ok, err = pcall(StartModeOperation, src, invited, stageId, 'arc_pvp')
    ReleaseArcStartLock(lockState)

    if not ok then
        print(string.format("^1[ARC START]^7 %s", tostring(err)))
        ServerHelpers.NotifyPlayer(src, "ARC deploy sırasında beklenmeyen bir hata oluştu.", "error")
    end
end)

RegisterNetEvent('gs-survival:server:startArcExtractionCall', function(zoneId)
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)

    if bucketId == 0 or not ServerHelpers.IsBucketMember(bucketId, src) or ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
        ServerHelpers.NotifyPlayer(src, "Tahliye yalnızca ARC baskını sırasında çağrılabilir.", "error")
        return
    end

    local ok, err = StartArcExtractionCall(bucketId, src, zoneId)
    if not ok then
        ServerHelpers.NotifyPlayer(src, err or "Tahliye hattı çağrılamadı.", "error")
    end
end)

RegisterNetEvent('gs-survival:server:departArcExtraction', function()
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)

    if ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
        ServerHelpers.NotifyPlayer(src, "Kalkış yalnızca ARC baskını sırasında başlatılabilir.", "error")
        return
    end

    local ok, err = TryResolveArcExtractionDeparture(bucketId, src, true)
    if not ok then
        ServerHelpers.NotifyPlayer(src, err or "Kalkış başlatılamadı.", "error")
    end
end)

RegisterNetEvent('gs-survival:server:spawnWave', function(bId, wave, stageId)
    local src = source
    local bucketId = tonumber(bId)
    local waveNumber = math.floor(tonumber(wave) or 0)

    if not bucketId or bucketId <= 0 or GetPlayerRoutingBucket(src) ~= bucketId then
        return
    end

    if not ServerHelpers.IsBucketMember(bucketId, src) then
        return
    end

    if ServerHelpers.GetGameModeId(bucketModes[bucketId]) == 'arc_pvp' then
        return
    end

    if waveNumber <= 0 then
        return
    end

    local previousWave = tonumber(bucketWaveState[bucketId] or 0) or 0
    if waveNumber ~= (previousWave + 1) then
        return
    end

    if previousWave > 0 and ServerHelpers.CountAliveBucketNpcs(bucketId) > 0 then
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
        ServerHelpers.NotifyPlayer(src, "Zaten aktif bir lobin var.", "error")
        return
    end

    if ServerHelpers.FindLobbyLeaderByMember(src) then
        ServerHelpers.NotifyPlayer(src, "Önce mevcut lobinden ayrılmalısın.", "error")
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
            ServerHelpers.NotifyPlayer(src, "Bu lobi artık aktif değil.", "error")
            return
        end

        if activeLobbies[src] or ServerHelpers.FindLobbyLeaderByMember(src) then
            ServerHelpers.NotifyPlayer(src, "Zaten başka bir lobidesin.", "error")
            return
        end

        if ServerHelpers.CountMembers(activeLobbies[leaderId].members) >= (MAX_LOBBY_SIZE - 1) then
            ServerHelpers.NotifyPlayer(src, "Lobi dolu olduğu için katılamadın.", "error")
            return
        end

        if GetPlayerRoutingBucket(src) ~= 0 or GetPlayerRoutingBucket(leaderId) ~= 0 then
            ServerHelpers.NotifyPlayer(src, "Bu lobiye katılmak için aktif operasyon dışında olmalısın.", "error")
            return
        end

        local memberName = member.PlayerData.charinfo.firstname .. " " .. member.PlayerData.charinfo.lastname
        local canJoin, proximityError = EnsureLobbyProximity(leaderId, src, memberName)
        if not canJoin then
            ServerHelpers.NotifyPlayer(src, proximityError, "error")
            ServerHelpers.NotifyPlayer(leaderId, memberName .. " daveti kabul etmeye çalıştı ama yanında olmadığı için alınmadı.", "error")
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
        ServerHelpers.NotifyPlayer(src, "Bu lobi artık aktif değil.", "error")
        return
    end

    if lobby.isPublic ~= true then
        ServerHelpers.NotifyPlayer(src, "Bu lobi private olduğu için doğrudan katılamazsın.", "error")
        return
    end

    if activeLobbies[src] or ServerHelpers.FindLobbyLeaderByMember(src) then
        ServerHelpers.NotifyPlayer(src, "Zaten başka bir lobidesin.", "error")
        return
    end

    if ServerHelpers.CountMembers(lobby.members) >= (MAX_LOBBY_SIZE - 1) then
        ServerHelpers.NotifyPlayer(src, "Lobi dolu olduğu için katılamadın.", "error")
        return
    end

    if GetPlayerRoutingBucket(src) ~= 0 or GetPlayerRoutingBucket(leaderId) ~= 0 then
        ServerHelpers.NotifyPlayer(src, "Bu lobiye katılmak için aktif operasyon dışında olmalısın.", "error")
        return
    end

    local memberName = member.PlayerData.charinfo.firstname .. " " .. member.PlayerData.charinfo.lastname
    local canJoin, proximityError = EnsureLobbyProximity(leaderId, src, memberName)
    if not canJoin then
        ServerHelpers.NotifyPlayer(src, proximityError, "error")
        ServerHelpers.NotifyPlayer(leaderId, memberName .. " public lobiye uzaktan katılmaya çalıştı.", "error")
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
    ServerHelpers.NotifyPlayer(leaderId, playerName .. " daveti reddetti.", "error")
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
        ServerHelpers.AdjustArcPendingReconnectCount(arcDisconnectStates[cid].bucketId, -1)
    end
    arcDisconnectStates[cid] = nil
    ClearAllModeState(Player)
    Player.Functions.Save()

    if GetPlayerRoutingBucket(playerId) ~= 0 then
        SetPlayerRoutingBucket(playerId, 0)
    end

    TriggerClientEvent('gs-survival:client:cleanupBeforeLeave', playerId)

    if restored then
        ServerHelpers.NotifyPlayer(playerId,
            "Kaynak yeniden başlatıldı; eşyaların yedekten geri verildi ve aktif baskın güvenli şekilde kapatıldı.",
            "primary")
    else
        ServerHelpers.NotifyPlayer(playerId,
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
            ServerHelpers.NotifyPlayer(src, nextReadyState and "Hazır durumun liderine iletildi." or "Hazır durumun kaldırıldı.", nextReadyState and "success" or "primary")
            ServerHelpers.NotifyPlayer(leaderId, data.members[src].name .. (nextReadyState and " hazır durumda." or " artık hazır değil."), nextReadyState and "success" or "primary")
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
        ServerHelpers.NotifyPlayer(leaderId, "Bir üye lobiden ayrıldı.", "error")
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
        ServerHelpers.NotifyPlayer(src, "Geçersiz üretim talebi!", "error")
        return
    end

    local craftSource = ResolveArcCraftSource(Player, data.stashId)
    if data.stashId and not craftSource then
        ServerHelpers.NotifyPlayer(src, "Geçersiz ARC depo talebi!", "error")
        return
    end

    local multiplier = NormalizeCraftMultiplier(data.multiplier)
    local inventoryItems = GetCraftInventoryItems(Player, craftSource)
    local maxCraftable = GetCraftMaxCraftable(inventoryItems, validRecipe.requirements)
    if multiplier > maxCraftable then
        ServerHelpers.NotifyPlayer(src, "Seçtiğin üretim adedi için yeterli malzeme yok!", "error")
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
                    ServerHelpers.NotifyPlayer(src, "Depodaki malzemeler güncellendi, craft iptal edildi.", "error")
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
                ServerHelpers.NotifyPlayer(src, "Üretilen eşya depoya eklenemediği için işlem geri alındı.", "error")
                return
            end

            ServerHelpers.NotifyPlayer(src, (validRecipe.label or validRecipe.item) .. " " .. craftSource.label .. " içinde üretildi!", "success")
            TriggerClientEvent('gs-survival:client:refreshCraftMenuCounts', src, craftSource.side)
            return
        end

        for _, req in pairs(scaledRequirements) do
            Player.Functions.RemoveItem(req.item, req.amount)
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[req.item], "remove")
        end
        Player.Functions.AddItem(validRecipe.item, craftedAmount)
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[validRecipe.item], "add")
        ServerHelpers.NotifyPlayer(src, (validRecipe.label or validRecipe.item) .. " üretildi!", "success")
    else
        ServerHelpers.NotifyPlayer(src, craftSource and "Seçili ARC deposunda yeterli malzeme yok!" or "Yeterli malzemen yok!", "error")
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

    if ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
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

    if ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' or not IsArcActivePlayer(bucketId, src) then
        ServerHelpers.NotifyPlayer(src, "Barricade kit sadece aktif ARC oyuncuları tarafından kullanılabilir.", "error")
        return
    end

    if not placementCoords or not model or not IsPlayerNearCoords(src, placementCoords, interactDistance) then
        ServerHelpers.NotifyPlayer(src, "Barricade için geçerli bir yer seçmedin.", "error")
        return
    end

    local totalBarricades, playerBarricades = CountArcBarricades(bucketId, src)
    if totalBarricades >= maxRaidBarricades then
        ServerHelpers.NotifyPlayer(src, "Bu ARC baskınında daha fazla barricade kurulamıyor.", "error")
        return
    end

    if playerBarricades >= maxPlayerBarricades then
        ServerHelpers.NotifyPlayer(src, "Kendi barricade limitine ulaştın.", "error")
        return
    end

    for _, barricadeState in pairs(arcPlacedBarricades[bucketId] or {}) do
        local existingCoords = ToVector3(barricadeState.coords)
        if existingCoords and #(placementCoords - existingCoords) < minSpacing then
            ServerHelpers.NotifyPlayer(src, "Barricade'ler birbirine çok yakın olamaz.", "error")
            return
        end
    end

    local removeSlot = tonumber(data and data.slot or nil)
    if removeSlot and removeSlot < 1 then
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
        ServerHelpers.NotifyPlayer(src, "Barricade kit envanterinde bulunamadı.", "error")
        return
    end

    arcPlacedBarricades[bucketId] = arcPlacedBarricades[bucketId] or {}
    local barricadeId = ("arc_barricade_%s_%s_%s_%s"):format(bucketId, src, GetGameTimer(), nextArcBarricadeId)
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
    ServerHelpers.NotifyPlayer(src, (config.Label or "ARC Barricade Kit") .. " kuruldu.", "success")
end)

RegisterNetEvent('gs-survival:server:removeArcBarricade', function(barricadeId)
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)
    local config = GetArcBarricadeConfig()
    local itemName = config.Item or arcBarricadeItemName
    local interactDistance = math.max(1.0, tonumber(config.InteractDistance) or 4.0)
    local normalizedBarricadeId = tostring(barricadeId or '')
    local bucketBarricades = arcPlacedBarricades[bucketId]
    local barricadeState = bucketBarricades and bucketBarricades[normalizedBarricadeId] or nil
    local barricadeCoords = ToVector3(barricadeState and barricadeState.coords)

    if ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' or not IsArcActivePlayer(bucketId, src) then
        ServerHelpers.NotifyPlayer(src, "Barricade sökme işlemi şu anda kullanılamıyor.", "error")
        return
    end

    if normalizedBarricadeId == '' or not barricadeState or not barricadeCoords then
        ServerHelpers.NotifyPlayer(src, "Bu barricade artık mevcut değil.", "error")
        return
    end

    if not IsPlayerNearCoords(src, barricadeCoords, interactDistance) then
        ServerHelpers.NotifyPlayer(src, "Barricade sökmek için daha yakında olmalısın.", "error")
        return
    end

    if exports.ox_inventory:CanCarryItem(src, itemName, 1) == false then
        ServerHelpers.NotifyPlayer(src, "Envanterinde yer yok.", "error")
        return
    end

    bucketBarricades[normalizedBarricadeId] = nil

    local added = exports.ox_inventory:AddItem(src, itemName, 1)
    if not added then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            added = Player.Functions.AddItem(itemName, 1)
            if added and QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[itemName] then
                TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], "add")
            end
        end
    end

    if not added then
        bucketBarricades[normalizedBarricadeId] = barricadeState
        ServerHelpers.NotifyPlayer(src, "Barricade kit envantere geri eklenemedi.", "error")
        return
    end

    if not next(bucketBarricades) then
        arcPlacedBarricades[bucketId] = nil
    end

    BroadcastArcBarricadeRemoval(bucketId, normalizedBarricadeId)
    ServerHelpers.NotifyPlayer(src, (config.Label or "ARC Barricade Kit") .. " söküldü.", "success")
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
        return ServerHelpers.NotifyPlayer(src, 'Zaten bu geliştirmeye sahipsin!', 'error', 'Survival Market')
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

        ServerHelpers.NotifyPlayer(src, upgradeData.label .. ' satın alındı!', 'success', 'Survival Market')
    else
        ServerHelpers.NotifyPlayer(src, 'Yeterli paran yok! Gereken: $' .. price, 'error', 'Survival Market')
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
    local resolvedModeId = ServerHelpers.GetGameModeId(modeId)
    local backupStashId = GetBackupStashId(resolvedModeId, cid)

    ClearAllModeState(TPlayer)
    TPlayer.Functions.Save()

    TriggerClientEvent('gs-survival:client:cleanupBeforeLeave', targetId)
    TriggerClientEvent('ox_inventory:disarm', targetId)
    if arcDisconnectStates[cid] and arcDisconnectStates[cid].allowRejoin == true and arcDisconnectStates[cid].resolved ~= true then
        ServerHelpers.AdjustArcPendingReconnectCount(arcDisconnectStates[cid].bucketId, -1)
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
    ServerHelpers.SetArcPlayerBucketIndex(targetId, nil)
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
            ServerHelpers.NotifyPlayer(targetId, "Arc ana stash açılamadı, loot aktarımı yapılamadı.", "error")
        end
    end

    exports.ox_inventory:ClearInventory(targetId)
    Wait(600)
    SetPlayerRoutingBucket(targetId, 0)
    ServerHelpers.SetArcPlayerBucketIndex(targetId, nil)
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
    if ServerHelpers.GetGameModeId(modeId) == 'arc_pvp' then
        RestoreArcInventory(targetId, victoryStatus, modeId)
        return
    end

    RestoreSurvivalInventory(targetId, victoryStatus, modeId)
end

local function HandleArcDisconnect(source, bucketId, reason)
    local Player = QBCore.Functions.GetPlayer(source)
    local profile = ServerHelpers.GetArcRaidPlayerProfile(bucketId, source)
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
        ServerHelpers.AdjustArcPendingReconnectCount(previousDisconnectState.bucketId, -1)
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
        playerName = profile and profile.name or ServerHelpers.BuildArcPlayerDisplayName(Player, source),
        lastCoords = lastCoords,
        squadMembers = ServerHelpers.GetArcRaidSquadMembers(bucketId, source)
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
        ServerHelpers.AdjustArcPendingReconnectCount(bucketId, 1)
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
    if not ServerHelpers.IsPlayerInList(groupMembers[bucketId], source) then
        groupMembers[bucketId][#groupMembers[bucketId] + 1] = source
    end
    groupSizes[bucketId] = #groupMembers[bucketId]
    ServerHelpers.SetArcPlayerBucketIndex(source, bucketId)

    ServerHelpers.AddArcRaidPlayerToSquad(bucketId, source, disconnectState.squadMembers)
    ServerHelpers.RememberArcRaidPlayerProfile(bucketId, source, Player)

    eliminatedArcPlayers[bucketId] = eliminatedArcPlayers[bucketId] or {}
    eliminatedArcPlayers[bucketId][source] = nil
    ClearArcSessionPlayerHistory(arcSessionDisconnects, bucketId, source, cid)

    local deploymentState = BuildArcJoinDeploymentPayload(bucketId)
    local rejoinCoords = disconnectState.lastCoords
        or (deploymentState and deploymentState.insertion)
        or (arcRaidState[bucketId] and arcRaidState[bucketId].deployment and arcRaidState[bucketId].deployment.insertion)
        or (arcRaidState[bucketId] and arcRaidState[bucketId].deployment and arcRaidState[bucketId].deployment.center)

    SetPlayerRoutingBucket(source, bucketId)
    ServerHelpers.SetArcPlayerBucketIndex(source, bucketId)
    if rejoinCoords and rejoinCoords.x and rejoinCoords.y and rejoinCoords.z then
        SetEntityCoords(GetPlayerPed(source), rejoinCoords.x, rejoinCoords.y, rejoinCoords.z)
    end

    TriggerClientEvent('hospital:client:Revive', source)
    TriggerClientEvent('gs-survival:client:initArcPvP', source, bucketId, ServerHelpers.GetArcRaidSquadMembers(bucketId, source), groupMembers[bucketId], GetArcRaidStageId(bucketId), deploymentState, {
        wasReconnect = true,
        coords = rejoinCoords
    })

    disconnectState.resolved = true
    if disconnectState.allowRejoin == true then
        ServerHelpers.AdjustArcPendingReconnectCount(bucketId, -1)
    end
    arcDisconnectStates[cid] = nil

    ServerHelpers.SyncArcRaidPlayers(bucketId)
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
        ServerHelpers.SetArcPlayerBucketIndex(source, nil)
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
            ServerHelpers.NotifyPlayer(playerId, successText, "success")
        else
            local failureText = reason == 'failed_to_extract'
                and "Tahliye penceresi kapandı. Saha dışına çıkamadığın için hazırladığın yük kaybedildi."
                or "ARC baskını başarısız oldu. Hazırladığın yük kaybedildi."
            ServerHelpers.NotifyPlayer(playerId, failureText, "error")
        end
    end

    ResetBucketState(bucketId)
    arcFinalizeLocks[bucketId] = nil
end
