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
