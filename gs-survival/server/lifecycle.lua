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
    local modeId = ServerHelpers.GetGameModeId(bucketModes[bucketId])

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
        local hasAliveNpc = ServerHelpers.CountAliveBucketNpcs(bucketId) > 0
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
            ServerHelpers.NotifyPlayer(leaderId, "Bir grup üyesi sunucudan ayrıldı.", "error")
            -- Liderin ekranındaki (invitedPlayers) listesini güncelle
            TriggerClientEvent('gs-survival:client:removeFromInvited', leaderId, src)
            SyncLobbyMembers(leaderId)
            break
        end
    end

    -- 2. [MAÇ TEMİZLİĞİ] (Senin mevcut bucket mantığın)
    local bucketId = GetPlayerRoutingBucket(src)
    if bucketId == 0 or not (groupMembers and groupMembers[bucketId]) then
        bucketId = ServerHelpers.FindArcBucketByPlayer(src)
    end
    if bucketId ~= 0 and groupMembers and groupMembers[bucketId] then
        if ServerHelpers.GetGameModeId(bucketModes[bucketId]) == 'arc_pvp' then
            local disconnectState = HandleArcDisconnect(src, bucketId, reason)
            local droppedProfile = ServerHelpers.GetArcRaidPlayerProfile(bucketId, src)
            local droppedName = disconnectState and disconnectState.playerName or (droppedProfile and droppedProfile.name) or ("ID " .. tostring(src))
            local disconnectInfo = BuildArcDisconnectPolicyInfo()
            for _, playerId in ipairs(groupMembers[bucketId]) do
                if tonumber(playerId) ~= tonumber(src) then
                    ServerHelpers.NotifyPlayer(playerId, ("%s bağlantı kaybetti. Aktif policy: %s."):format(droppedName, disconnectInfo.label), "primary")
                end
            end
        end

        RemoveArcRaidPlayer(bucketId, src)
        local pendingReconnects = GetArcPendingReconnectCount(bucketId)

        if #groupMembers[bucketId] > 0 then
            SyncArcRaidPlayers(bucketId)
            if ServerHelpers.GetGameModeId(bucketModes[bucketId]) == 'arc_pvp' and #GetArcAlivePlayers(bucketId) == 0 and pendingReconnects == 0 then
                FinalizeArcMatch(bucketId, {}, 'disconnect')
                return
            end
        end

        -- Eğer odada kimse kalmadıysa dünyayı temizle
        if #groupMembers[bucketId] == 0 then
            if ServerHelpers.GetGameModeId(bucketModes[bucketId]) == 'arc_pvp' and pendingReconnects > 0 then
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
            ServerHelpers.AdjustArcPendingReconnectCount(arcDisconnectStates[cid].bucketId, -1)
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

