local resourceName = GetCurrentResourceName()
local serverModules = {
    { path = 'server/core.lua', sharedScope = true },
    { path = 'server/lobby.lua' },
    { path = 'server/modes.lua' },
    { path = 'server/lifecycle.lua' },
    { path = 'server/loot.lua' },
}

local function BuildBundledModule(resource, module)
    local modulePath = type(module) == 'table' and module.path or module
    local sharedScope = type(module) == 'table' and module.sharedScope == true
    local moduleSource = LoadResourceFile(resource, modulePath)
    if not moduleSource then
        error(('Failed to load server module: %s'):format(modulePath))
    end

    if sharedScope then
        return ('--# source: %s\n%s'):format(modulePath, moduleSource)
    end

    return ('--# source: %s\ndo\n%s\nend'):format(modulePath, moduleSource)
end

local serverBundle = {}
for _, module in ipairs(serverModules) do
    serverBundle[#serverBundle + 1] = BuildBundledModule(resourceName, module)
end

local serverChunk, loadError = load(table.concat(serverBundle, '\n'), ('@@%s/server_bundle.lua'):format(resourceName))
if not serverChunk then
    error(('Failed to compile server bundle: %s'):format(loadError))
end

serverChunk()
