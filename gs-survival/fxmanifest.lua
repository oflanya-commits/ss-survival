fx_version 'cerulean'
game 'gta5'

author 'Yağız'
description 'cross5m-gangnpc: Optimized Gang Protection System'
version '1.0.0'

dependencies {
    'qb-core',
    'ox_inventory',
    'ox_target',
    'ox_lib',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'client/init.lua',
    'client/nui.lua',
    'client/world.lua',
    'client/crafting.lua',
    'client/gameplay.lua',
    'client/lobby.lua',
}

shared_scripts {
    '@qb-core/shared/sh_main.lua',
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}
