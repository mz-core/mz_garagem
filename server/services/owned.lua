MZGaragemOwned = MZGaragemOwned or {}

local function isGarageDebug()
  return MZGaragemConfig and MZGaragemConfig.debug == true
end

local function resolveVehicleCategory(vehicle)
  vehicle = type(vehicle) == 'table' and vehicle or {}

  local resolvedCatalog = MZGaragemVehicleDomain
    and type(MZGaragemVehicleDomain.resolveCatalog) == 'function'
    and MZGaragemVehicleDomain.resolveCatalog(vehicle.model, nil)
    or nil

  return tostring((type(resolvedCatalog) == 'table' and resolvedCatalog.category) or vehicle.category or 'car')
end

local function vehicleHasAllowedCategory(allowed, category)
  category = tostring(category or '')
  if category == '' then
    return false
  end

  for _, allowedCategory in ipairs(allowed or {}) do
    if tostring(allowedCategory) == category then
      return true
    end
  end

  return false
end

local function categoryAllowed(garage, vehicle)
  local allowed = garage.filters and garage.filters.categories or nil
  if type(allowed) ~= 'table' or #allowed == 0 then
    return true
  end

  return vehicleHasAllowedCategory(allowed, resolveVehicleCategory(vehicle))
    or vehicleHasAllowedCategory(allowed, vehicle and vehicle.category)
end

local function getVehicleOrError(plate)
  local ok, vehicle = exports['mz_vehicles']:GetVehicleByPlate(plate)
  if not ok then
    return false, vehicle
  end

  return true, vehicle
end

local function vehicleBlocked(model)
  if not MZGaragemVehicleDomain or type(MZGaragemVehicleDomain.isBlocked) ~= 'function' then
    return false, nil
  end

  return MZGaragemVehicleDomain.isBlocked(model)
end

local function validateGaragePolicy(access, vehicle, action)
  if not categoryAllowed(access.garage, vehicle) then
    return false, 'vehicle_category_not_allowed'
  end

  if action == 'withdraw' then
    local blocked = vehicleBlocked(vehicle.model)
    if blocked then
      return false, 'vehicle_blocked'
    end
  end

  if action == 'release' and access.garage.rules.allow_impounded ~= true then
    return false, 'impound_release_not_allowed'
  end

  return true
end

local function isPrivateHouseGarage(access)
  local garage = type(access) == 'table' and type(access.garage) == 'table' and access.garage or {}
  local house = type(garage.house) == 'table' and garage.house or {}

  return garage.kind == 'house'
    and (tostring(house.mode or '') == 'private' or (garage.rules and garage.rules.strict_garage == true))
end

local function countStoredVehiclesInGarage(source, garageId, exceptPlate)
  garageId = tostring(garageId or '')
  exceptPlate = tostring(exceptPlate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')

  if garageId == '' then
    return 0
  end

  local ok, vehicles = exports['mz_vehicles']:GetPlayerVehicles(source)
  if not ok then
    return 0
  end

  local count = 0
  for _, vehicle in ipairs(vehicles or {}) do
    local plate = tostring(vehicle.plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
    local state = tostring(vehicle.state or 'stored')
    if tostring(vehicle.garage or '') == garageId and state == 'stored' and plate ~= exceptPlate then
      count = count + 1
    end
  end

  return count
end

local function buildConditionPayload(vehicle)
  vehicle = type(vehicle) == 'table' and vehicle or {}
  local metadata = type(vehicle.metadata_json) == 'table' and vehicle.metadata_json or {}
  local world = type(metadata.world) == 'table' and metadata.world or {}
  local engine = tonumber(vehicle.engine) or 1000
  local body = tonumber(vehicle.body) or 1000
  local destroyed = engine <= 50.0
    or body <= 100.0

  return {
    destroyed = destroyed,
    world = {
      destroyed = destroyed,
      locked = world.locked,
      last_coords = world.last_coords,
      last_heading = world.last_heading
    }
  }
end

function MZGaragemOwned.list(source, access)
  local ok, vehicles = exports['mz_vehicles']:GetPlayerVehicles(source)
  if not ok then
    return false, vehicles
  end

  local rows = {}
  local vehiclesTotal = 0
  for _, vehicle in ipairs(vehicles or {}) do
    vehiclesTotal = vehiclesTotal + 1

    local state = tostring(vehicle.state or 'stored')
    local blocked = vehicleBlocked(vehicle.model)
    local allowedCategory = categoryAllowed(access.garage, vehicle)
    local vehicleGarage = tostring(vehicle.garage or '')
    local garageId = tostring(access.garage.id or '')
    local strictGarage = access.garage.rules.strict_garage == true
    local privateHouseGarage = isPrivateHouseGarage(access)
    local skipReason = nil

    if blocked then
      skipReason = 'vehicle_blocked'
    elseif not allowedCategory then
      skipReason = 'category_not_allowed'
    elseif state == 'impounded' and access.garage.rules.allow_impounded ~= true then
      skipReason = 'impounded_not_allowed'
    elseif privateHouseGarage and state ~= 'stored' then
      skipReason = 'house_garage_not_stored'
    elseif strictGarage and vehicleGarage ~= garageId then
      skipReason = 'wrong_garage'
    end

    if skipReason then
      if isGarageDebug() then
        print(('[mz_garagem][owned_list_skip] source=%s | citizenid=%s | garage=%s | plate=%s | model=%s | category=%s | db_category=%s | vehicle_garage=%s | state=%s | reason=%s'):format(
          tostring(source),
          tostring(access.citizenid or ''),
          garageId,
          tostring(vehicle.plate or ''),
          tostring(vehicle.model or ''),
          resolveVehicleCategory(vehicle),
          tostring(vehicle.category or ''),
          vehicleGarage,
          state,
          skipReason
        ))
      end
    else
      rows[#rows + 1] = MZGaragemDTO.buildOwnedEntry(access.garage, vehicle)
    end
  end

  if isGarageDebug() then
    print(('[mz_garagem][owned_list] source=%s | citizenid=%s | garage=%s | vehicles_total=%s | entries_count=%s'):format(
      tostring(source),
      tostring(access.citizenid or ''),
      tostring(access.garage.id or ''),
      tostring(vehiclesTotal),
      tostring(#rows)
    ))
  end

  return true, MZGaragemDTO.sort(rows)
end

function MZGaragemOwned.withdraw(source, access, plate)
  local ok, vehicle = getVehicleOrError(plate)
  if not ok then
    return false, vehicle
  end

  local playerOwns = exports['mz_vehicles']:PlayerOwnsVehicle(access.citizenid, plate)
  if playerOwns ~= true then
    return false, 'vehicle_access_denied'
  end

  local policyOk, policyErr = validateGaragePolicy(access, vehicle, 'withdraw')
  if not policyOk then
    return false, policyErr
  end

  local expectedGarage = MZGaragemAccess.getExpectedGarageId(access.garage)
  local takeOutOk, updatedVehicle = exports['mz_vehicles']:TakeOutVehicle(source, plate, expectedGarage)
  if not takeOutOk then
    return false, updatedVehicle
  end

  local conditionPayload = buildConditionPayload(updatedVehicle)

  return true, {
    kind = 'persistent',
    plate = tostring(updatedVehicle.plate or ''),
    vehicle_model = tostring(updatedVehicle.model or ''),
    model = tostring(updatedVehicle.model or ''),
    props = updatedVehicle.props_json or {},
    fuel = tonumber(updatedVehicle.fuel) or 100,
    engine = tonumber(updatedVehicle.engine) or 1000,
    body = tonumber(updatedVehicle.body) or 1000,
    destroyed = conditionPayload.destroyed,
    world = conditionPayload.world
  }
end

function MZGaragemOwned.releaseImpound(source, access, plate)
  local ok, vehicle = getVehicleOrError(plate)
  if not ok then
    return false, vehicle
  end

  local playerOwns = exports['mz_vehicles']:PlayerOwnsVehicle(access.citizenid, plate)
  if playerOwns ~= true then
    return false, 'vehicle_access_denied'
  end

  local policyOk, policyErr = validateGaragePolicy(access, vehicle, 'release')
  if not policyOk then
    return false, policyErr
  end

  local releaseOk, result = exports['mz_vehicles']:ReleaseImpoundVehicle(plate, access.garage.id, source)
  if not releaseOk then
    return false, result
  end

  return true, result
end

function MZGaragemOwned.store(source, access, payload)
  local ok, vehicle = getVehicleOrError(payload.plate)
  if not ok then
    return false, vehicle
  end

  if vehicle.owner_type ~= 'player' then
    return false, 'garage_kind_mismatch'
  end

  local playerOwns = exports['mz_vehicles']:PlayerOwnsVehicle(access.citizenid, payload.plate)
  if playerOwns ~= true then
    return false, 'vehicle_access_denied'
  end

  local policyOk, policyErr = validateGaragePolicy(access, vehicle, 'store')
  if not policyOk then
    return false, policyErr
  end

  if isPrivateHouseGarage(access) then
    local garageId = tostring(access.garage.id or '')
    local slots = math.floor(tonumber(access.garage.house and access.garage.house.slots) or 2)
    if slots < 1 then slots = 1 end

    local vehicleGarage = tostring(vehicle.garage or '')
    if vehicleGarage ~= garageId then
      local currentCount = countStoredVehiclesInGarage(source, garageId, payload.plate)
      if currentCount >= slots then
        if isGarageDebug() then
          print(('[mz_garagem][house_garage_full] source=%s | citizenid=%s | garage=%s | slots=%s | current=%s | plate=%s'):format(
            tostring(source),
            tostring(access.citizenid or ''),
            garageId,
            tostring(slots),
            tostring(currentCount),
            tostring(payload.plate or '')
          ))
        end
        return false, 'house_garage_full'
      end
    end
  end

  local storedOk, storedVehicle = exports['mz_vehicles']:StoreVehicle(
    source,
    payload.plate,
    access.garage.id,
    payload.props or {},
    payload.fuel,
    payload.engine,
    payload.body,
    payload.destroyed
  )

  if not storedOk then
    return false, storedVehicle
  end

  return true, storedVehicle
end

function MZGaragemOwned.rollbackWithdraw(access, plate)
  local playerOwns = exports['mz_vehicles']:PlayerOwnsVehicle(access.citizenid, plate)
  if playerOwns ~= true then
    return false, 'vehicle_access_denied'
  end

  local ok = exports['mz_vehicles']:SetVehicleStored(plate, true)
  if ok ~= true then
    return false, ok
  end

  return true
end
