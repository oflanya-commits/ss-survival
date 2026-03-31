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

    local previewCoords, previewHeading = GetArcBarricadePreviewPosition(ped, {
        heading = GetEntityHeading(ped)
    })
    local previewEntity = CreateObjectNoOffset(model, previewCoords.x, previewCoords.y, previewCoords.z, false, false, false)
    SetEntityAsMissionEntity(previewEntity, true, true)
    SetEntityCollision(previewEntity, false, false)
    SetEntityAlpha(previewEntity, math.max(60, math.min(tonumber(config.PreviewAlpha) or 160, 255)), false)
    SetEntityHeading(previewEntity, previewHeading)
    SetModelAsNoLongerNeeded(model)

    arcBarricadePreview = {
        entity = previewEntity,
        slot = data and data.slot or nil,
        heading = previewHeading,
        lastCoords = previewCoords
    }

    ShowArcBarricadePlacementUi()
    NotifyForMode("Sol tık ile yerleştir, Q / E ile döndür, BACKSPACE ile iptal et.", "primary", 5000, "ARC Barricade")

    CreateThread(function()
        local lastPedRefreshAt = GetGameTimer()
        while arcBarricadePreview and arcBarricadePreview.entity and DoesEntityExist(arcBarricadePreview.entity) do
            Wait(0)

            local now = GetGameTimer()
            if now - lastPedRefreshAt >= 200 then
                ped = PlayerPedId()
                lastPedRefreshAt = now
            end
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 38, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)

            if IsDisabledControlJustPressed(0, 44) then
                arcBarricadePreview.heading = arcBarricadePreview.heading + (tonumber(config.RotationStep) or 3.0)
            elseif IsDisabledControlJustPressed(0, 38) then
                arcBarricadePreview.heading = arcBarricadePreview.heading - (tonumber(config.RotationStep) or 3.0)
            end

            local placementCoords, placementHeading = GetArcBarricadePreviewPosition(ped, arcBarricadePreview)
            SetEntityCoordsNoOffset(arcBarricadePreview.entity, placementCoords.x, placementCoords.y, placementCoords.z, false, false, false)
            SetEntityHeading(arcBarricadePreview.entity, placementHeading)
            PlaceObjectOnGroundProperly(arcBarricadePreview.entity)

            if IsDisabledControlJustPressed(0, 177) then
                DeleteEntity(arcBarricadePreview.entity)
                arcBarricadePreview = nil
                HideArcBarricadePlacementUi()
                NotifyForMode("Barricade yerleştirme iptal edildi.", "error", 3500, "ARC Barricade")
                return
            end

            if IsDisabledControlJustPressed(0, 24) then
                local finalizedCoords = GetEntityCoords(arcBarricadePreview.entity)
                local finalizedHeading = GetEntityHeading(arcBarricadePreview.entity)
                local itemSlot = arcBarricadePreview.slot
                DeleteEntity(arcBarricadePreview.entity)
                arcBarricadePreview = nil
                HideArcBarricadePlacementUi()

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

RegisterNetEvent('gs-survival:client:removeArcBarricade', function(barricadeId)
    RemoveLocalArcBarricade(tostring(barricadeId or ''))
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

