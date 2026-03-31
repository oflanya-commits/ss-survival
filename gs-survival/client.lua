local resourceName = GetCurrentResourceName()
local clientModules = {
    'client/init.lua',
    'client/nui.lua',
    'client/world.lua',
    'client/crafting.lua',
    'client/gameplay.lua',
    'client/lobby.lua',
}

-- Client modülleri bootstrap tarafından LoadResourceFile ile birleştirilip tek chunk olarak çalıştırılır.
local clientBundle = {}
for _, modulePath in ipairs(clientModules) do
    local moduleSource = LoadResourceFile(resourceName, modulePath)
    if not moduleSource then
        error(('Failed to load client module: %s'):format(modulePath))
    end

    clientBundle[#clientBundle + 1] = ('--# source: %s\n%s'):format(modulePath, moduleSource)
end

local clientChunk, loadError = load(table.concat(clientBundle, '\n'), ('@@%s/client_bundle.lua'):format(resourceName))
if not clientChunk then
    error(('Failed to compile client bundle: %s'):format(loadError))
end

clientChunk()
