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

    elseif action == 'arcProgressComplete' then
        FinalizeUiProgress(tonumber(data.data and data.data.id) or 0, false)

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
        TriggerEvent('gs-survival:client:startFinal', { modeId = 'arc_pvp', stageId = data.data and data.data.stageId })

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
