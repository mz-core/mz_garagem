fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mz_garagem'
author 'Mazus'
description 'Garage domain integrated with mz_vehicles and mz_org'
version '0.1.0'

shared_scripts {
  '@ox_lib/init.lua',
  'shared/config.lua',
  'shared/garages.lua',
  'shared/service_fleet.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/services/vehicle_domain.lua',
  'server/services/access.lua',
  'server/managed/prepare.lua',
  'server/managed/repository.lua',
  'server/managed/service.lua',
  'server/services/dto.lua',
  'server/services/owned.lua',
  'server/services/org.lua',
  'server/services/service_state_repository.lua',
  'server/services/service.lua',
  'server/callbacks.lua',
  'server/bootstrap_readiness.lua',
  'server/main.lua'
}

client_scripts {
  'client/helpers.lua',
  'client/managed.lua',
  'client/spawn.lua',
  'client/nui.lua',
  'client/main.lua',
  'client/interact.lua'
}

ui_page 'web/index.html'

files {
  'web/index.html',
  'web/style.css',
  'web/script.js',
  'web/vehicle-fallback.svg'
}

dependencies {
  'ox_lib',
  'oxmysql',
  'mz_core',
  'mz_org',
  'mz_vehicles',
  'mz_fuel'
}
