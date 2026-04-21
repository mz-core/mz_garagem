MZGaragemClient = MZGaragemClient or {
  serviceVehiclesByPlate = {}
}

MZGaragemClientHelpers = MZGaragemClientHelpers or {}

local MOD_FIELDS = {
  [0] = 'modSpoilers',
  [1] = 'modFrontBumper',
  [2] = 'modRearBumper',
  [3] = 'modSideSkirt',
  [4] = 'modExhaust',
  [5] = 'modFrame',
  [6] = 'modGrille',
  [7] = 'modHood',
  [8] = 'modFender',
  [9] = 'modRightFender',
  [10] = 'modRoof',
  [11] = 'modEngine',
  [12] = 'modBrakes',
  [13] = 'modTransmission',
  [14] = 'modHorns',
  [15] = 'modSuspension',
  [16] = 'modArmor',
  [17] = 'modKit17',
  [19] = 'modKit19',
  [21] = 'modKit21',
  [23] = 'modFrontWheels',
  [24] = 'modBackWheels',
  [25] = 'modPlateHolder',
  [26] = 'modVanityPlate',
  [27] = 'modTrimA',
  [28] = 'modOrnaments',
  [29] = 'modDashboard',
  [30] = 'modDial',
  [31] = 'modDoorSpeaker',
  [32] = 'modSeats',
  [33] = 'modSteeringWheel',
  [34] = 'modShifterLeavers',
  [35] = 'modAPlate',
  [36] = 'modSpeakers',
  [37] = 'modTrunk',
  [38] = 'modHydrolic',
  [39] = 'modEngineBlock',
  [40] = 'modAirFilter',
  [41] = 'modStruts',
  [42] = 'modArchCover',
  [43] = 'modAerials',
  [44] = 'modTrimB',
  [45] = 'modTank',
  [46] = 'modWindows',
  [47] = 'modKit47',
  [48] = 'modLivery',
  [49] = 'modKit49'
}

local function round(value, decimals)
  local power = 10 ^ (decimals or 0)
  return math.floor((tonumber(value) or 0) * power + 0.5) / power
end

local function normalizeNotifyType(notifyType)
  notifyType = tostring(notifyType or 'info'):lower()

  if notifyType == 'success' or notifyType == 'error' or notifyType == 'warning' or notifyType == 'info' then
    return notifyType
  end

  if notifyType == 'inform' then
    return 'info'
  end

  return 'info'
end

local function getNotifyTitle(customTitle)
  if customTitle and tostring(customTitle) ~= '' then
    return tostring(customTitle)
  end

  return tostring(MZGaragemConfig.ui and MZGaragemConfig.ui.title or 'Garagem')
end

local function canUseVehiclesExports()
  return GetResourceState('mz_vehicles') == 'started'
end

local function logVehiclesBridgeError(exportName, err)
  print(('[mz_garagem][vehicles_bridge] export "%s" failed: %s'):format(
    tostring(exportName or 'unknown'),
    tostring(err or 'unknown_error')
  ))
end

local function callVehiclesExport(exportName, ...)
  if not canUseVehiclesExports() then
    return false, nil, nil, 'mz_vehicles_unavailable'
  end

  local ok, a, b = pcall(function(...)
    return exports['mz_vehicles'][exportName](...)
  end, ...)

  if not ok then
    logVehiclesBridgeError(exportName, a)
    return false, nil, nil, 'mz_vehicles_export_failed'
  end

  return true, a, b, nil
end

function MZGaragemClientHelpers.notify(message, notifyType, title)
  local normalizedType = normalizeNotifyType(notifyType)
  local resourceState = GetResourceState('mz_notify')
  local payload = {
    type = normalizedType,
    title = getNotifyTitle(title),
    message = tostring(message or 'Unknown'),
    duration = 5000
  }

  if resourceState == 'started' then
    exports['mz_notify']:Notify(payload)
    return
  end

  if lib and type(lib.notify) == 'function' then
    lib.notify({
      title = payload.title,
      description = payload.message,
      type = normalizedType == 'info' and 'inform' or normalizedType
    })
    return
  end

  print(('[mz_garagem][%s] %s - %s'):format(normalizedType, payload.title, payload.message))
end

function MZGaragemClientHelpers.showHelpText(message)
  BeginTextCommandDisplayHelp('STRING')
  AddTextComponentSubstringPlayerName(tostring(message or ''))
  EndTextCommandDisplayHelp(0, false, false, -1)
end

function MZGaragemClientHelpers.drawGarageMarker(garage)
  if MZGaragemConfig.draw_markers ~= true then
    return
  end

  local marker = MZGaragemConfig.marker or {}
  local color = marker.color or {}
  local scale = marker.scale or vec3(0.5, 0.5, 0.5)
  local coords = garage.zone.coords

  DrawMarker(
    marker.type or 36,
    coords.x, coords.y, coords.z,
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    scale.x or 0.5, scale.y or 0.5, scale.z or 0.5,
    color.r or 57, color.g or 229, color.b or 140, color.a or 110,
    false, false, 2, true, nil, nil, false
  )
end

function MZGaragemClientHelpers.getPlate(vehicle)
  local ok, plate, _, bridgeErr = callVehiclesExport('GetVehiclePlate', vehicle)
  if ok then
    return tostring(plate or '')
  end

  if bridgeErr ~= 'mz_vehicles_unavailable' then
    return ''
  end

  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return ''
  end

  return tostring(GetVehicleNumberPlateText(vehicle) or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
end

function MZGaragemClientHelpers.loadModel(model)
  local ok, modelHash, modelErr, bridgeErr = callVehiclesExport('LoadModel', model)
  if ok then
    return modelHash, modelErr
  end

  if bridgeErr ~= 'mz_vehicles_unavailable' then
    return nil, bridgeErr
  end

  local modelHash = type(model) == 'number' and model or joaat(tostring(model or ''))
  if not IsModelInCdimage(modelHash) then
    return nil, 'model_not_found'
  end

  RequestModel(modelHash)

  local timeoutAt = GetGameTimer() + 10000
  while not HasModelLoaded(modelHash) do
    Wait(0)
    if GetGameTimer() > timeoutAt then
      return nil, 'model_timeout'
    end
  end

  return modelHash
end

function MZGaragemClientHelpers.findAvailableSpawnPoint(garage)
  local points = garage.spawn_points or {}
  if #points == 0 then
    return nil
  end

  local firstFree = nil
  for _, point in ipairs(points) do
    local occupied = IsPositionOccupied(
      point.x,
      point.y,
      point.z,
      4.0,
      false,
      true,
      false,
      false,
      false,
      0,
      false
    )

    if not occupied then
      firstFree = point
      break
    end
  end

  return firstFree
end

function MZGaragemClientHelpers.isVehicleEmpty(vehicle)
  local ok, isEmpty, _, bridgeErr = callVehiclesExport('IsVehicleEmpty', vehicle)
  if ok then
    return isEmpty == true
  end

  if bridgeErr ~= 'mz_vehicles_unavailable' then
    return false
  end

  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false
  end

  if GetPedInVehicleSeat(vehicle, -1) ~= 0 then
    return false
  end

  local maxPassengers = GetVehicleMaxNumberOfPassengers(vehicle)
  for seat = 0, maxPassengers - 1 do
    if GetPedInVehicleSeat(vehicle, seat) ~= 0 then
      return false
    end
  end

  return true
end

function MZGaragemClientHelpers.findNearbyVehicleForStore(garage)
  if MZGaragemConfig.allowNearbyStore ~= true then
    return nil, 'nearby_store_disabled'
  end

  if not garage or type(garage.zone) ~= 'table' or not garage.zone.coords then
    return nil, 'garage_not_found'
  end

  local ped = PlayerPedId()
  local playerCoords = GetEntityCoords(ped)
  local garageCoords = garage.zone.coords
  local maxVehicleDistance = tonumber(MZGaragemConfig.maxVehicleDistance or 8.0) or 8.0
  local maxGarageDistance = tonumber(MZGaragemConfig.maxGarageDistance or 12.0) or 12.0

  if #(playerCoords - garageCoords) > maxGarageDistance then
    return nil, 'garage_too_far'
  end

  local nearestVehicle = nil
  local nearestDistance = nil

  for _, vehicle in ipairs(GetGamePool('CVehicle')) do
    if vehicle ~= 0 and DoesEntityExist(vehicle) and MZGaragemClientHelpers.isVehicleEmpty(vehicle) then
      local vehicleCoords = GetEntityCoords(vehicle)
      local playerDistance = #(playerCoords - vehicleCoords)
      local garageDistance = #(garageCoords - vehicleCoords)

      if playerDistance <= maxVehicleDistance and garageDistance <= maxGarageDistance then
        if not nearestDistance or playerDistance < nearestDistance then
          nearestVehicle = vehicle
          nearestDistance = playerDistance
        end
      end
    end
  end

  if not nearestVehicle then
    return nil, 'nearby_vehicle_not_found'
  end

  return nearestVehicle
end

function MZGaragemClientHelpers.getVehicleProperties(vehicle)
  local ok, props, _, bridgeErr = callVehiclesExport('GetVehicleProperties', vehicle)
  if ok and type(props) == 'table' then
    return props
  end

  if bridgeErr ~= 'mz_vehicles_unavailable' then
    return {}
  end

  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return {}
  end

  local pearlescentColor, wheelColor = GetVehicleExtraColours(vehicle)
  local colorPrimary, colorSecondary = GetVehicleColours(vehicle)

  if GetIsVehiclePrimaryColourCustom(vehicle) then
    local r, g, b = GetVehicleCustomPrimaryColour(vehicle)
    colorPrimary = { r, g, b }
  end

  if GetIsVehicleSecondaryColourCustom(vehicle) then
    local r, g, b = GetVehicleCustomSecondaryColour(vehicle)
    colorSecondary = { r, g, b }
  end

  local extras = {}
  for extraId = 0, 20 do
    if DoesExtraExist(vehicle, extraId) then
      local enabled = IsVehicleExtraTurnedOn(vehicle, extraId)
      extras[tostring(extraId)] = enabled == 1 or enabled == true
    end
  end

  local neonEnabled = {
    IsVehicleNeonLightEnabled(vehicle, 0),
    IsVehicleNeonLightEnabled(vehicle, 1),
    IsVehicleNeonLightEnabled(vehicle, 2),
    IsVehicleNeonLightEnabled(vehicle, 3)
  }

  local neonColor = table.pack(GetVehicleNeonLightsColour(vehicle))
  local tyreSmokeColor = table.pack(GetVehicleTyreSmokeColor(vehicle))

  local windowStatus = {}
  for index = 0, 7 do
    windowStatus[index] = IsVehicleWindowIntact(vehicle, index) == 1
  end

  local doorStatus = {}
  for index = 0, 5 do
    doorStatus[index] = IsVehicleDoorDamaged(vehicle, index) == 1
  end

  local tireBurstState = {}
  for index = 0, 5 do
    tireBurstState[index] = IsVehicleTyreBurst(vehicle, index, false)
  end

  local props = {
    model = GetEntityModel(vehicle),
    plate = MZGaragemClientHelpers.getPlate(vehicle),
    plateIndex = GetVehicleNumberPlateTextIndex(vehicle),
    bodyHealth = round(GetVehicleBodyHealth(vehicle), 1),
    engineHealth = round(GetVehicleEngineHealth(vehicle), 1),
    tankHealth = round(GetVehiclePetrolTankHealth(vehicle), 1),
    fuelLevel = round(GetVehicleFuelLevel(vehicle), 1),
    dirtLevel = round(GetVehicleDirtLevel(vehicle), 1),
    color1 = colorPrimary,
    color2 = colorSecondary,
    pearlescentColor = pearlescentColor,
    dashboardColor = GetVehicleDashboardColour(vehicle),
    wheelColor = wheelColor,
    wheels = GetVehicleWheelType(vehicle),
    windowTint = GetVehicleWindowTint(vehicle),
    neonEnabled = neonEnabled,
    neonColor = neonColor,
    interiorColor = GetVehicleInteriorColour(vehicle),
    extras = extras,
    tyreSmokeColor = tyreSmokeColor,
    tireBurstState = tireBurstState,
    windowStatus = windowStatus,
    doorStatus = doorStatus,
    modCustomTiresF = GetVehicleModVariation(vehicle, 23),
    modCustomTiresR = GetVehicleModVariation(vehicle, 24),
    liveryRoof = GetVehicleRoofLivery(vehicle)
  }

  local hasCustomXenon, xr, xg, xb = GetVehicleXenonLightsCustomColor(vehicle)
  if hasCustomXenon then
    props.xenonColor = { xr, xg, xb }
  else
    props.xenonColor = GetVehicleXenonLightsColor(vehicle)
  end

  props.modTurbo = IsToggleModOn(vehicle, 18)
  props.modSmokeEnabled = IsToggleModOn(vehicle, 20)
  props.modXenon = IsToggleModOn(vehicle, 22)

  for modIndex, fieldName in pairs(MOD_FIELDS) do
    props[fieldName] = GetVehicleMod(vehicle, modIndex)
  end

  return props
end

function MZGaragemClientHelpers.setVehicleProperties(vehicle, props)
  local ok, _, _, bridgeErr = callVehiclesExport('SetVehicleProperties', vehicle, props)
  if ok then
    return
  end

  if bridgeErr ~= 'mz_vehicles_unavailable' then
    return
  end

  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or type(props) ~= 'table' then
    return
  end

  SetVehicleModKit(vehicle, 0)

  if props.extras then
    for extraId, enabled in pairs(props.extras) do
      SetVehicleExtra(vehicle, tonumber(extraId), enabled and 0 or 1)
    end
  end

  local currentPrimary, currentSecondary = GetVehicleColours(vehicle)
  local currentPearlescent, currentWheelColor = GetVehicleExtraColours(vehicle)

  if props.plate ~= nil then
    SetVehicleNumberPlateText(vehicle, tostring(props.plate))
  end

  if props.plateIndex ~= nil then
    SetVehicleNumberPlateTextIndex(vehicle, props.plateIndex)
  end

  if props.bodyHealth ~= nil then
    SetVehicleBodyHealth(vehicle, (tonumber(props.bodyHealth) or 1000) + 0.0)
  end

  if props.engineHealth ~= nil then
    SetVehicleEngineHealth(vehicle, (tonumber(props.engineHealth) or 1000) + 0.0)
  end

  if props.tankHealth ~= nil then
    SetVehiclePetrolTankHealth(vehicle, (tonumber(props.tankHealth) or 1000) + 0.0)
  end

  if props.fuelLevel ~= nil then
    SetVehicleFuelLevel(vehicle, (tonumber(props.fuelLevel) or 100) + 0.0)
  end

  if props.dirtLevel ~= nil then
    SetVehicleDirtLevel(vehicle, (tonumber(props.dirtLevel) or 0) + 0.0)
  end

  if props.color1 ~= nil then
    if type(props.color1) == 'table' then
      SetVehicleCustomPrimaryColour(vehicle, props.color1[1] or 0, props.color1[2] or 0, props.color1[3] or 0)
    else
      ClearVehicleCustomPrimaryColour(vehicle)
      SetVehicleColours(vehicle, tonumber(props.color1) or currentPrimary, currentSecondary)
    end
  end

  if props.color2 ~= nil then
    if type(props.color2) == 'table' then
      SetVehicleCustomSecondaryColour(vehicle, props.color2[1] or 0, props.color2[2] or 0, props.color2[3] or 0)
    else
      ClearVehicleCustomSecondaryColour(vehicle)
      SetVehicleColours(vehicle, props.color1 or currentPrimary, tonumber(props.color2) or currentSecondary)
    end
  end

  SetVehicleExtraColours(
    vehicle,
    tonumber(props.pearlescentColor) or currentPearlescent,
    tonumber(props.wheelColor) or currentWheelColor
  )

  if props.dashboardColor ~= nil then
    SetVehicleDashboardColour(vehicle, props.dashboardColor)
  end

  if props.interiorColor ~= nil then
    SetVehicleInteriorColour(vehicle, props.interiorColor)
  end

  if props.wheels ~= nil then
    SetVehicleWheelType(vehicle, props.wheels)
  end

  if props.windowTint ~= nil then
    SetVehicleWindowTint(vehicle, props.windowTint)
  end

  if props.neonEnabled then
    for index = 1, 4 do
      SetVehicleNeonLightEnabled(vehicle, index - 1, props.neonEnabled[index] == true)
    end
  end

  if props.neonColor and type(props.neonColor) == 'table' then
    SetVehicleNeonLightsColour(vehicle, props.neonColor[1] or 255, props.neonColor[2] or 255, props.neonColor[3] or 255)
  end

  if props.tyreSmokeColor and type(props.tyreSmokeColor) == 'table' then
    SetVehicleTyreSmokeColor(vehicle, props.tyreSmokeColor[1] or 255, props.tyreSmokeColor[2] or 255, props.tyreSmokeColor[3] or 255)
  end

  ToggleVehicleMod(vehicle, 18, props.modTurbo == true)
  ToggleVehicleMod(vehicle, 20, props.modSmokeEnabled == true)
  ToggleVehicleMod(vehicle, 22, props.modXenon == true)

  for modIndex, fieldName in pairs(MOD_FIELDS) do
    if props[fieldName] ~= nil then
      local useCustomTires = false
      if modIndex == 23 then
        useCustomTires = props.modCustomTiresF == true
      elseif modIndex == 24 then
        useCustomTires = props.modCustomTiresR == true
      end

      SetVehicleMod(vehicle, modIndex, tonumber(props[fieldName]) or -1, useCustomTires)
    end
  end

  if props.modLivery ~= nil and GetVehicleLiveryCount(vehicle) > 0 and tonumber(props.modLivery) and tonumber(props.modLivery) >= 0 then
    SetVehicleLivery(vehicle, tonumber(props.modLivery))
  end

  if props.xenonColor ~= nil then
    if type(props.xenonColor) == 'table' then
      SetVehicleXenonLightsCustomColor(vehicle, props.xenonColor[1] or 255, props.xenonColor[2] or 255, props.xenonColor[3] or 255)
    else
      SetVehicleXenonLightsColor(vehicle, tonumber(props.xenonColor) or 0)
    end
  end

  if props.windowStatus then
    for index, intact in pairs(props.windowStatus) do
      if intact ~= true then
        SmashVehicleWindow(vehicle, tonumber(index))
      end
    end
  end

  if props.doorStatus then
    for index, damaged in pairs(props.doorStatus) do
      if damaged == true then
        SetVehicleDoorBroken(vehicle, tonumber(index), true)
      end
    end
  end

  if props.tireBurstState then
    for index, burst in pairs(props.tireBurstState) do
      if burst == true then
        SetVehicleTyreBurst(vehicle, tonumber(index), false, 1000.0)
      end
    end
  end

  if props.liveryRoof ~= nil then
    SetVehicleRoofLivery(vehicle, tonumber(props.liveryRoof) or 0)
  end
end

function MZGaragemClientHelpers.deleteVehicleSafely(vehicle)
  local ok, _, _, bridgeErr = callVehiclesExport('DeleteVehicleSafely', vehicle)
  if ok then
    return
  end

  if bridgeErr ~= 'mz_vehicles_unavailable' then
    return
  end

  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return
  end

  local ped = PlayerPedId()
  if IsPedInVehicle(ped, vehicle, false) then
    TaskLeaveVehicle(ped, vehicle, 16)
    Wait(300)
  end

  SetEntityAsMissionEntity(vehicle, true, true)
  DeleteVehicle(vehicle)

  if DoesEntityExist(vehicle) then
    DeleteEntity(vehicle)
  end
end
