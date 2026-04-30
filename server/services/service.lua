MZGaragemService = MZGaragemService or {}

local runtimeState = {
  by_id = {},
  by_plate = {},
  by_player_garage = {}
}

local function shouldLogServiceOpen(access)
  local garage = type(access) == 'table' and access.garage or access
  local garageId = tostring(type(garage) == 'table' and garage.id or '')
  return garageId == 'police_service'
end

local function logServiceOpen(stage, source, access, detail)
  if not shouldLogServiceOpen(access) then
    return
  end

  detail = type(detail) == 'table' and detail or {}
  local garage = type(access) == 'table' and access.garage or {}
  local fleet = type(detail.fleet) == 'table' and detail.fleet or nil
  local fleetEntries = fleet and type(fleet.entries) == 'table' and #fleet.entries or 0

  print(('[mz_garagem][open_service][%s][source:%s] garage_id=%s | kind=%s | org_code=%s | fleet_id=%s | fleet_found=%s | fleet_entries=%s | entries_count=%s | active_runtime=%s | error=%s'):format(
    tostring(stage or 'unknown'),
    tostring(source or 'unknown'),
    tostring(garage.id or ''),
    tostring(garage.kind or ''),
    tostring(garage.org_code or ''),
    tostring(garage.fleet_id or ''),
    tostring(fleet ~= nil),
    tostring(fleetEntries),
    tostring(detail.entries_count or 0),
    tostring(detail.active_runtime == true),
    tostring(detail.error or '')
  ))
end

local function getFleet(garage)
  if not garage or not garage.fleet_id then
    return nil
  end

  return MZGaragemServiceFleet and MZGaragemServiceFleet[garage.fleet_id] or nil
end

local function getPlayerGarageKey(citizenid, garageId)
  return ('%s:%s'):format(tostring(citizenid or ''), tostring(garageId or ''))
end

local function makeRuntimeId(citizenid, garageId, entryId)
  return ('%s:%s:%s:%s'):format(
    tostring(citizenid or ''),
    tostring(garageId or ''),
    tostring(entryId or ''),
    tostring(os.time())
  )
end

local function getRuntime(runtimeId)
  return runtimeState.by_id[tostring(runtimeId or '')]
end

local function removeRuntime(runtimeId)
  local runtime = getRuntime(runtimeId)
  if not runtime then
    return
  end

  runtimeState.by_id[runtime.runtime_id] = nil

  if runtime.plate then
    runtimeState.by_plate[runtime.plate] = nil
  end

  local key = getPlayerGarageKey(runtime.citizenid, runtime.garage_id)
  if runtimeState.by_player_garage[key] == runtime.runtime_id then
    runtimeState.by_player_garage[key] = nil
  end
end

local function pruneRuntime(runtime)
  if not runtime then
    return nil
  end

  local timeoutSeconds = tonumber(MZGaragemConfig.service.pending_spawn_timeout_seconds or 30) or 30
  local age = os.time() - (tonumber(runtime.created_at) or 0)

  if runtime.status == 'pending' and age > timeoutSeconds then
    removeRuntime(runtime.runtime_id)
    return nil
  end

  if runtime.status == 'active' and tonumber(runtime.net_id or 0) > 0 then
    if not NetworkDoesNetworkIdExist(runtime.net_id) then
      removeRuntime(runtime.runtime_id)
      return nil
    end
  end

  return runtime
end

local function getActiveRuntime(access)
  local key = getPlayerGarageKey(access.citizenid, access.garage.id)
  local runtimeId = runtimeState.by_player_garage[key]
  if not runtimeId then
    return nil
  end

  return pruneRuntime(getRuntime(runtimeId))
end

local function findFleetEntry(garage, entryId)
  local fleet = getFleet(garage)
  if not fleet then
    return nil
  end

  for _, entry in ipairs(fleet.entries or {}) do
    if tostring(entry.entry_id or '') == tostring(entryId or '') then
      return entry
    end
  end

  return nil
end

local function categoryAllowed(garage, fleetEntry)
  local allowed = garage.filters and garage.filters.categories or nil
  if type(allowed) ~= 'table' or #allowed == 0 then
    return true
  end

  local resolvedCatalog = MZGaragemVehicleDomain
    and type(MZGaragemVehicleDomain.resolveCatalog) == 'function'
    and MZGaragemVehicleDomain.resolveCatalog(fleetEntry.model, nil)
    or nil
  local vehicleCategory = tostring((type(resolvedCatalog) == 'table' and resolvedCatalog.category) or fleetEntry.category or 'car')
  for _, category in ipairs(allowed) do
    if tostring(category) == vehicleCategory or tostring(category) == tostring(fleetEntry.category or '') then
      return true
    end
  end

  return false
end

local function vehicleBlocked(model)
  if not MZGaragemVehicleDomain or type(MZGaragemVehicleDomain.isBlocked) ~= 'function' then
    return false, nil
  end

  return MZGaragemVehicleDomain.isBlocked(model)
end

local function plateExistsAnywhere(plate)
  if runtimeState.by_plate[plate] then
    return true
  end

  local ok = exports['mz_core']:GetVehicleByPlate(plate)
  return ok == true
end

local function generatePlate()
  local prefix = tostring(MZGaragemConfig.service.plate_prefix or 'SRV'):upper():sub(1, 4)

  for _ = 1, 50 do
    local candidate = ('%s%04d'):format(prefix, math.random(0, 9999))
    if not plateExistsAnywhere(candidate) then
      return candidate
    end
  end

  return ('%s%06d'):format(prefix, math.random(0, 999999))
end

function MZGaragemService.list(source, access)
  local fleet = getFleet(access.garage)
  if not fleet then
    logServiceOpen('list_error', source, access, {
      error = 'service_fleet_not_found'
    })
    return false, 'service_fleet_not_found'
  end

  local activeRuntime = getActiveRuntime(access)
  local limitOne = access.garage.service.limit_one_active == true
  local rows = {}

  for _, entry in ipairs(fleet.entries or {}) do
    local blocked = vehicleBlocked(entry.model)

    if not blocked and categoryAllowed(access.garage, entry) then
      local runtime = nil
      local lockedByLimit = false

      if activeRuntime and activeRuntime.entry_id == entry.entry_id then
        runtime = activeRuntime
      elseif activeRuntime and limitOne then
        lockedByLimit = true
      end

      rows[#rows + 1] = MZGaragemDTO.buildServiceEntry(access.garage, entry, runtime, lockedByLimit)
    end
  end

  logServiceOpen('list_ok', source, access, {
    fleet = fleet,
    entries_count = #rows,
    active_runtime = activeRuntime ~= nil
  })

  return true, MZGaragemDTO.sort(rows)
end

function MZGaragemService.withdraw(source, access, entryId)
  local fleetEntry = findFleetEntry(access.garage, entryId)
  if not fleetEntry then
    return false, 'service_entry_not_found'
  end

  local blocked = vehicleBlocked(fleetEntry.model)
  if blocked then
    return false, 'vehicle_blocked'
  end

  if not categoryAllowed(access.garage, fleetEntry) then
    return false, 'vehicle_category_not_allowed'
  end

  local activeRuntime = getActiveRuntime(access)
  if activeRuntime and access.garage.service.limit_one_active == true then
    return false, 'service_vehicle_active'
  end

  local runtimeId = makeRuntimeId(access.citizenid, access.garage.id, fleetEntry.entry_id)
  local plate = generatePlate()
  local runtime = {
    runtime_id = runtimeId,
    status = 'pending',
    source = source,
    citizenid = access.citizenid,
    garage_id = tostring(access.garage.id),
    fleet_id = tostring(access.garage.fleet_id or ''),
    entry_id = tostring(fleetEntry.entry_id or ''),
    model = tostring(fleetEntry.model or ''),
    plate = plate,
    fuel = tonumber(fleetEntry.fuel) or 100,
    engine = tonumber(fleetEntry.engine) or 1000,
    body = tonumber(fleetEntry.body) or 1000,
    props = fleetEntry.props or {},
    created_at = os.time(),
    net_id = 0
  }

  runtimeState.by_id[runtimeId] = runtime
  runtimeState.by_plate[plate] = runtimeId
  runtimeState.by_player_garage[getPlayerGarageKey(access.citizenid, access.garage.id)] = runtimeId

  return true, {
    kind = 'service',
    runtime_id = runtimeId,
    plate = plate,
    vehicle_model = runtime.model,
    model = runtime.model,
    props = runtime.props,
    fuel = runtime.fuel,
    engine = runtime.engine,
    body = runtime.body,
    entry_id = runtime.entry_id
  }
end

function MZGaragemService.confirmSpawn(source, runtimeId, netId)
  local runtime = pruneRuntime(getRuntime(runtimeId))
  if not runtime then
    return false, 'runtime_not_found'
  end

  if tonumber(runtime.source) ~= tonumber(source) then
    return false, 'runtime_access_denied'
  end

  runtime.status = 'active'
  runtime.net_id = tonumber(netId) or 0

  return true
end

function MZGaragemService.cancelPendingSpawn(source, runtimeId)
  local runtime = pruneRuntime(getRuntime(runtimeId))
  if not runtime then
    return false, 'runtime_not_found'
  end

  if tonumber(runtime.source) ~= tonumber(source) then
    return false, 'runtime_access_denied'
  end

  removeRuntime(runtime.runtime_id)
  return true, runtime
end

function MZGaragemService.releaseRuntime(source, runtimeId)
  local runtime = pruneRuntime(getRuntime(runtimeId))
  if not runtime then
    return false, 'runtime_not_found'
  end

  if tonumber(runtime.source) ~= tonumber(source) then
    return false, 'runtime_access_denied'
  end

  removeRuntime(runtime.runtime_id)
  return true, runtime
end

function MZGaragemService.store(source, access, payload)
  local runtime = nil

  if payload.runtime_id then
    runtime = pruneRuntime(getRuntime(payload.runtime_id))
  elseif payload.plate then
    local runtimeId = runtimeState.by_plate[tostring(payload.plate or '')]
    runtime = pruneRuntime(getRuntime(runtimeId))
  end

  if not runtime then
    return false, 'runtime_not_found'
  end

  if tonumber(runtime.source) ~= tonumber(source) then
    return false, 'runtime_access_denied'
  end

  if tostring(runtime.garage_id) ~= tostring(access.garage.id) then
    return false, 'runtime_wrong_garage'
  end

  removeRuntime(runtime.runtime_id)
  return true, runtime
end

function MZGaragemService.cleanupSource(source)
  local toRemove = {}

  for runtimeId, runtime in pairs(runtimeState.by_id) do
    if tonumber(runtime.source) == tonumber(source) then
      toRemove[#toRemove + 1] = runtimeId
    end
  end

  for _, runtimeId in ipairs(toRemove) do
    removeRuntime(runtimeId)
  end
end

function MZGaragemService.resetAll()
  runtimeState.by_id = {}
  runtimeState.by_plate = {}
  runtimeState.by_player_garage = {}
end
