local resourceName = GetCurrentResourceName()
local serverModules = {
    'server/core.lua',
    'server/lobby.lua',
    'server/modes.lua',
    'server/lifecycle.lua',
    'server/loot.lua',
}

local serverBundle = {}
for _, modulePath in ipairs(serverModules) do
    local moduleSource = LoadResourceFile(resourceName, modulePath)
    if not moduleSource then
        error(('Failed to load server module: %s'):format(modulePath))
    end

    serverBundle[#serverBundle + 1] = ('--# source: %s\n%s'):format(modulePath, moduleSource)
end

local serverChunk, loadError = load(table.concat(serverBundle, '\n'), ('@@%s/server_bundle.lua'):format(resourceName))
if not serverChunk then
    error(('Failed to compile server bundle: %s'):format(loadError))
end

serverChunk()
