-- [NPC LOOT SİSTEMİ]
RegisterNetEvent('gs-survival:server:createNpcStash', function(npcNetId, currentWave) -- currentWave parametresini ekledik
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)
    local resolvedNpcNetId = tonumber(npcNetId)
    local wave = math.max(1, math.floor(tonumber(bucketWaveState[bucketId] or 1))) -- Eğer dalga bilgisi gelmezse varsayılan 1 yap

    if bucketId == 0 or not ServerHelpers.IsBucketMember(bucketId, src) or not resolvedNpcNetId then
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
    if npc == 0 or not DoesEntityExist(npc) or GetEntityRoutingBucket(npc) ~= bucketId or not ServerHelpers.IsPedEntityDead(npc) then
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
        ServerHelpers.NotifyPlayer(src, "ARC stash bilgisi alınamadı.", "error")
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
        ServerHelpers.NotifyPlayer(src, "Taşınacak eşya bulunamadı.", "error")
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
            ServerHelpers.NotifyPlayer(src, "Stack için aynı tür eşyayı hedeflemelisin.", "error")
            TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
            return
        end

        if isWeapon then
            ServerHelpers.NotifyPlayer(src, "Silahlar üst üste konamaz.", "error")
            TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
            return
        end
    end

    if sameInventory then
        local removed = exports.ox_inventory:RemoveItem(fromStashId, selectedItem.name, itemCount, selectedItem.metadata, slot)
        if not removed then
            ServerHelpers.NotifyPlayer(src, "Eşya kaynağından alınamadı.", "error")
            TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
            return
        end

        local added = exports.ox_inventory:AddItem(toStashId, selectedItem.name, itemCount, transferMetadata, targetInventorySlot)
        if not added then
            exports.ox_inventory:AddItem(fromStashId, selectedItem.name, itemCount, selectedItem.metadata, slot)
            ServerHelpers.NotifyPlayer(src, "Eşya yeni yuvaya taşınamadı, işlem geri alındı.", "error")
            TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
            return
        end

        local actionText = targetItem and "stacklendi" or "taşındı"
        ServerHelpers.NotifyPlayer(src, string.format("%s x%d, aynı depo içinde %s.", itemLabel, itemCount, actionText), "success")
        TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
        return
    end

    if not exports.ox_inventory:CanCarryItem(toStashId, selectedItem.name, itemCount, transferMetadata) then
        ServerHelpers.NotifyPlayer(src, string.format("%s bu eşyayı taşıyamıyor.", toLabel), "error")
        TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
        return
    end

    local added = exports.ox_inventory:AddItem(toStashId, selectedItem.name, itemCount, transferMetadata, targetInventorySlot)
    if not added then
        ServerHelpers.NotifyPlayer(src, string.format("%s açılırken bir hata oluştu.", toLabel), "error")
        TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
        return
    end

    local removed = exports.ox_inventory:RemoveItem(fromStashId, selectedItem.name, itemCount, selectedItem.metadata, slot)
    if not removed then
        exports.ox_inventory:RemoveItem(toStashId, selectedItem.name, itemCount, transferMetadata, targetInventorySlot)
        ServerHelpers.NotifyPlayer(src, "Eşya taşınırken işlem geri alındı.", "error")
        TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
        return
    end

    local actionText = targetItem and "içinde stacklendi" or "içine aktarıldı"
    ServerHelpers.NotifyPlayer(src, string.format("%s x%d, %s içinden %s %s.", itemLabel, itemCount, fromLabel, toLabel, actionText), "success")
    TriggerClientEvent('gs-survival:client:openArcLockerManager', src, focusSide)
end)

RegisterNetEvent('gs-survival:server:openArcLootContainer', function(containerId, rollCount)
    local src = source
    local bucketId = GetPlayerRoutingBucket(src)

    if ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
        ServerHelpers.NotifyPlayer(src, "Bu sandık yalnızca ARC Baskını sırasında açılabilir.", "error")
        return
    end

    if not arcRaidState[bucketId] then
        ServerHelpers.NotifyPlayer(src, "ARC loot verisi henüz hazır değil.", "error")
        return
    end

    local bucketContainerState = openedArcContainers[bucketId] and openedArcContainers[bucketId][containerId]
    if not containerId then
        ServerHelpers.NotifyPlayer(src, "Geçersiz loot kutusu.", "error")
        return
    end

    local nodeState = GetArcLootNodeState(bucketId, containerId)
    if not nodeState then
        ServerHelpers.NotifyPlayer(src, "Geçersiz loot kutusu.", "error")
        return
    end

    if not IsPlayerNearCoords(src, nodeState.coords, 4.0) then
        ServerHelpers.NotifyPlayer(src, "Bu loot kutusunu açmak için yanında olmalısın.", "error")
        return
    end

    if bucketContainerState and bucketContainerState.consumed then
        ServerHelpers.NotifyPlayer(src, "Bu loot kutusu zaten açıldı.", "error")
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

    if ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' then
        ServerHelpers.NotifyPlayer(src, "Bu düşüş kutusu yalnızca ARC Baskını sırasında açılabilir.", "error")
        return
    end

    local containerState = arcDeathContainers[bucketId] and arcDeathContainers[bucketId][containerId]
    if not containerId or not containerState or containerState.consumed or not containerState.stashId then
        ServerHelpers.NotifyPlayer(src, "Bu ölüm kutusu artık kullanılamıyor.", "error")
        return
    end

    if not IsPlayerNearCoords(src, containerState.coords, 4.0) then
        ServerHelpers.NotifyPlayer(src, "Bu ölüm kutusunu açmak için yanında olmalısın.", "error")
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

    if ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' or not groupMembers[bucketId] then
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
            bucketId = tonumber(bucketId) or bucketId,
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

    if ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'arc_pvp' or not groupMembers[bucketId] then
        return
    end

    if arcFinalizeLocks[bucketId] then
        ServerHelpers.NotifyPlayer(src, "Oturum kapanışı sürüyor, lobiye dönüş isteği işlenemedi.", "error")
        return
    end

    if not (eliminatedArcPlayers[bucketId] and eliminatedArcPlayers[bucketId][src]) then
        ServerHelpers.NotifyPlayer(src, "Lobiye sadece elendikten sonra dönebilirsin.", "error")
        return
    end

    RestorePlayerInventory(src, false, 'arc_pvp')
    TriggerClientEvent('gs-survival:client:stopEverything', src, false, 'arc_pvp')
    ServerHelpers.NotifyPlayer(src, "İzleme sonlandırıldı, lobiye döndün.", "primary")

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

    if bucketId == 0 or not ServerHelpers.IsBucketMember(bucketId, source) or not resolvedNpcNetId then
        return cb(false)
    end

    if beingLooted[resolvedNpcNetId] and beingLooted[resolvedNpcNetId] ~= source then
        -- Eğer bu NPC zaten birisi tarafından aranıyorsa
        ServerHelpers.NotifyPlayer(source, "Bu ceset zaten başkası tarafından aranıyor!", "error")
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
    if bucketId == 0 or ServerHelpers.GetGameModeId(bucketModes[bucketId]) ~= 'classic' or not IsModeActive(Player, 'classic') then
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
