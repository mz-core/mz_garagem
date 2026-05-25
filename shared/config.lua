MZGaragemConfig = {
  debug = false,
  UseMzInteract = true,
  FallbackToLegacyMarkers = true,
  draw_markers = true,
  interaction_distance = 3.0,
  marker_draw_distance = 18.0,
  allowNearbyStore = true,
  maxVehicleDistance = 8.0,
  maxGarageDistance = 12.0,
  DefaultInteractIcon = {
    textureDict = 'mod_icon',
    textureName = 'garage'
  },
  DefaultStoreIcon = {
    textureDict = 'mod_icon',
    textureName = 'garage'
  },
  marker = {
    type = 36,
    scale = vec3(0.5, 0.5, 0.5),
    color = { r = 57, g = 229, b = 140, a = 110 }
  },
  warp_into_vehicle = true,
  delete_vehicle_on_store = true,
  service = {
    plate_prefix = 'SRV',
    pending_spawn_timeout_seconds = 30,
    runtime_cleanup_interval_ms = 2000
  },
  ui = {
    title = 'Garagem'
  },
  images = {
    baseUrl = 'https://fivem.mazinho.org/imagens/carros/',
    extension = 'png',
    fallbackImage = 'vehicle-fallback.svg'
  }
}

-- Exemplo de icone por garagem:
-- interact = {
--   icon = {
--     textureDict = 'mod_icon',
--     textureName = 'arsenal_icon'
--   }
-- }
--
-- Exemplo de icone no ponto de guardar, caso use marker type 9:
-- store = {
--   interact = {
--     marker = {
--       type = 9
--     },
--     icon = {
--       textureDict = 'mod_icon',
--       textureName = 'arsenal_icon'
--     }
--   }
-- }
