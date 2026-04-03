local resourceName = GetCurrentResourceName()
local clientModules = {
    { path = 'client/init.lua', sharedScope = true },
    { path = 'client/nui.lua' },
    { path = 'client/world.lua' },
    { path = 'client/crafting.lua' },
    { path = 'client/gameplay.lua' },
    { path = 'client/lobby.lua' },
}

local function BuildBundledModule(resource, module)
    local modulePath = type(module) == 'table' and module.path or module
    local sharedScope = type(module) == 'table' and module.sharedScope == true
    local moduleSource = LoadResourceFile(resource, modulePath)
    if not moduleSource then
        error(('Failed to load client module: %s'):format(modulePath))
    end

    if sharedScope then
        return ('--# source: %s\n%s'):format(modulePath, moduleSource)
    end

    return ('--# source: %s\ndo\n%s\nend'):format(modulePath, moduleSource)
end

-- Client modülleri bootstrap tarafından LoadResourceFile ile birleştirilip tek chunk olarak çalıştırılır.
local clientBundle = {}
for _, module in ipairs(clientModules) do
    clientBundle[#clientBundle + 1] = BuildBundledModule(resourceName, module)
end

local clientChunk, loadError = load(table.concat(clientBundle, '\n'), ('@@%s/client_bundle.lua'):format(resourceName))
if not clientChunk then
    error(('Failed to compile client bundle: %s'):format(loadError))
end

clientChunk()
