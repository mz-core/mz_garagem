MZGaragemService = MZGaragemService or {}

local runtimeState = {
  by_id = {},
  by_plate = {},
  by_player_garage = {}
}
local runtimeSequence = 0

local function shouldLogServiceOpen(access)
  local garage = type(access) == 'table' and access.garage or access
  local garageId = tostring(type(garage) == 'table' and garage.id or '')
  return MZGaragemConfig and MZGaragemConfig.debug == true and garageId == 'police_service'
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

local function normalizePlate(value)
  return tostring(value or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
end

local stateCache = {}
local sourceCitizen = {}

local function rememberSourceCitizen(source, citizenid)
  local normalizedSource = tonumber(source)
  local normalizedCitizen = tostring(citizenid or '')
  if normalizedSource and normalizedSource > 0 and normalizedCitizen ~= '' then
    sourceCitizen[normalizedSource] = normalizedCitizen
  end
end

local function statePersistenceEnabled()
  local service = MZGaragemConfig and MZGaragemConfig.service or {}
  return service.persist_state ~= false
end

local function getStateRepository()
  return MZGaragemServiceStateRepository
end

local function clampNumber(value, fallback, minimum, maximum)
  local numeric = tonumber(value)
  if not numeric then
    numeric = tonumber(fallback)
  end
  if not numeric then
    numeric = fallback
  end
  if type(numeric) ~= 'number' then
    return fallback
  end

  if minimum and numeric < minimum then numeric = minimum end
  if maximum and numeric > maximum then numeric = maximum end
  return numeric + 0.0
end

local function copyTable(value)
  local out = {}
  for key, item in pairs(type(value) == 'table' and value or {}) do
    out[key] = item
  end
  return out
end

local function copyFleetEntry(entry)
  return copyTable(entry)
end

local function logServiceState(stage, detail)
  if not (MZGaragemConfig and MZGaragemConfig.debug == true) then
    return
  end

  print(('[mz_garagem][service_state][%s] %s'):format(
    tostring(stage or 'unknown'),
    tostring(detail or '')
  ))
end

local function loadCitizenState(citizenid)
  local key = tostring(citizenid or '')
  local cache = stateCache[key]
  if cache and cache.loaded == true then
    return cache
  end

  cache = cache or { loaded = false, rows = {} }
  cache.loaded = true
  cache.rows = cache.rows or {}
  stateCache[key] = cache

  if not statePersistenceEnabled() or key == '' then
    return cache
  end

  local repository = getStateRepository()
  if not repository or type(repository.loadForCitizen) ~= 'function' then
    return cache
  end

  local ok, rows = pcall(repository.loadForCitizen, key)
  if not ok then
    print(('[mz_garagem] falha ao carregar estado da frota de servico: %s'):format(tostring(rows)))
    return cache
  end

  for _, row in ipairs(type(rows) == 'table' and rows or {}) do
    local garageId = tostring(row.garage_id or '')
    local entryId = tostring(row.entry_id or '')
    if garageId ~= '' and entryId ~= '' then
      cache.rows[garageId] = cache.rows[garageId] or {}
      cache.rows[garageId][entryId] = row
    end
  end

  return cache
end

local function getSavedState(citizenid, garageId, entryId)
  if not statePersistenceEnabled() then
    return nil
  end

  local cache = loadCitizenState(citizenid)
  local garageRows = cache.rows[tostring(garageId or '')]
  if type(garageRows) ~= 'table' then
    return nil
  end

  local state = garageRows[tostring(entryId or '')]
  if state then
    logServiceState('loaded', ('citizenid=%s garage=%s entry=%s fuel=%s engine=%s body=%s destroyed=%s'):format(
      tostring(citizenid or ''),
      tostring(garageId or ''),
      tostring(entryId or ''),
      tostring(state.fuel),
      tostring(state.engine),
      tostring(state.body),
      tostring(state.destroyed == true)
    ))
  end

  return state
end

local function saveState(runtime, payload)
  if not statePersistenceEnabled() or type(runtime) ~= 'table' then
    return false
  end

  payload = type(payload) == 'table' and payload or {}
  local citizenid = tostring(runtime.citizenid or '')
  local garageId = tostring(runtime.garage_id or '')
  local entryId = tostring(runtime.entry_id or '')
  if citizenid == '' or garageId == '' or entryId == '' then
    return false
  end

  local engine = clampNumber(payload.engine, runtime.engine, 0.0, 1000.0)
  local body = clampNumber(payload.body, runtime.body, 0.0, 1000.0)
  local props = nil
  if type(payload.props) == 'table' and next(payload.props) ~= nil then
    props = copyTable(payload.props)
    props.plate = nil
  elseif type(runtime.props) == 'table' then
    props = copyTable(runtime.props)
  else
    props = {}
  end

  local state = {
    citizenid = citizenid,
    garage_id = garageId,
    fleet_id = tostring(runtime.fleet_id or ''),
    entry_id = entryId,
    fuel = clampNumber(payload.fuel, runtime.fuel, 0.0, 100.0),
    engine = engine,
    body = body,
    props = props,
    destroyed = payload.destroyed == true or engine <= 50.0 or body <= 100.0
  }

  local cache = loadCitizenState(citizenid)
  cache.rows[garageId] = cache.rows[garageId] or {}
  cache.rows[garageId][entryId] = state
  logServiceState('saved', ('citizenid=%s garage=%s entry=%s fuel=%s engine=%s body=%s'):format(
    citizenid,
    garageId,
    entryId,
    tostring(state.fuel),
    tostring(state.engine),
    tostring(state.body)
  ))

  local repository = getStateRepository()
  if repository and type(repository.upsert) == 'function' then
    local ok, err = pcall(repository.upsert, state)
    if not ok then
      print(('[mz_garagem] falha ao salvar estado da frota de servico: %s'):format(tostring(err)))
    end
  end

  return true
end

local function getPlayerGarageKey(citizenid, garageId)
  return ('%s:%s'):format(tostring(citizenid or ''), tostring(garageId or ''))
end

local function makeRuntimeId(citizenid, garageId, entryId)
  runtimeSequence = runtimeSequence + 1
  return ('%s:%s:%s:%s:%s'):format(
    tostring(citizenid or ''),
    tostring(garageId or ''),
    tostring(entryId or ''),
    tostring(os.time()),
    tostring(runtimeSequence)
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

  -- Nao removemos um runtime ativo apenas porque o servidor nao resolveu a
  -- entidade por net_id. A entidade e criada pelo cliente e pode migrar ou
  -- ficar temporariamente invisivel. A liberacao ocorre por store, cancel,
  -- release explicito ou playerDropped.
  if runtime.status == 'active' then
    local netId = tonumber(runtime.net_id or 0) or 0
    if netId > 0 and type(NetworkGetEntityFromNetworkId) == 'function' then
      local ok, entity = pcall(NetworkGetEntityFromNetworkId, netId)
      local exists = ok and entity and entity ~= 0
      if exists and type(DoesEntityExist) == 'function' then
        local existsOk, existsResult = pcall(DoesEntityExist, entity)
        exists = existsOk and existsResult == true
      end

      if not exists then
        logServiceState('entity_unresolved', ('runtime_id=%s plate=%s net_id=%s'):format(
          tostring(runtime.runtime_id or ''),
          tostring(runtime.plate or ''),
          tostring(netId)
        ))
      end
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

  local ok = exports['mz_vehicles']:GetVehicleByPlate(plate)
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
  rememberSourceCitizen(source, access and access.citizenid)
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

      local displayEntry = entry
      if not runtime then
        local saved = getSavedState(access.citizenid, access.garage.id, entry.entry_id)
        if saved then
          displayEntry = copyFleetEntry(entry)
          displayEntry.fuel = saved.fuel
          displayEntry.engine = saved.engine
          displayEntry.body = saved.body
        end
      end

      rows[#rows + 1] = MZGaragemDTO.buildServiceEntry(access.garage, displayEntry, runtime, lockedByLimit)
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
  rememberSourceCitizen(source, access and access.citizenid)
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

  local saved = getSavedState(access.citizenid, access.garage.id, fleetEntry.entry_id)
  if saved then
    logServiceState('withdraw_saved', ('citizenid=%s garage=%s entry=%s fuel=%s engine=%s body=%s'):format(
      tostring(access.citizenid or ''),
      tostring(access.garage.id or ''),
      tostring(fleetEntry.entry_id or ''),
      tostring(saved.fuel),
      tostring(saved.engine),
      tostring(saved.body)
    ))
  else
    logServiceState('withdraw_default', ('citizenid=%s garage=%s entry=%s'):format(
      tostring(access.citizenid or ''),
      tostring(access.garage.id or ''),
      tostring(fleetEntry.entry_id or '')
    ))
  end

  local runtimeId = makeRuntimeId(access.citizenid, access.garage.id, fleetEntry.entry_id)
  local plate = generatePlate()
  local runtime = {
    runtime_id = runtimeId,
    status = 'pending',
    source = source,
    citizenid = access.citizenid,
    garage_id = tostring(access.garage.id),
    org_code = tostring(access.garage.org_code or ''),
    fleet_id = tostring(access.garage.fleet_id or ''),
    entry_id = tostring(fleetEntry.entry_id or ''),
    model = tostring(fleetEntry.model or ''),
    plate = plate,
    fuel = saved and tonumber(saved.fuel) or tonumber(fleetEntry.fuel) or 100,
    engine = saved and tonumber(saved.engine) or tonumber(fleetEntry.engine) or 1000,
    body = saved and tonumber(saved.body) or tonumber(fleetEntry.body) or 1000,
    props = saved and type(saved.props) == 'table' and saved.props or fleetEntry.props or {},
    destroyed = saved and saved.destroyed == true or false,
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
    destroyed = runtime.destroyed == true,
    entry_id = runtime.entry_id,
    garage_id = runtime.garage_id,
    org_code = runtime.org_code
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

  return true, runtime
end

function MZGaragemService.cancelPendingSpawn(source, runtimeId)
  local runtime = pruneRuntime(getRuntime(runtimeId))
  if not runtime then
    return false, 'runtime_not_found'
  end

  if tonumber(runtime.source) ~= tonumber(source) then
    return false, 'runtime_access_denied'
  end

  logServiceState('cancelled', ('runtime_id=%s source=%s plate=%s'):format(
    tostring(runtime.runtime_id or ''),
    tostring(source or ''),
    tostring(runtime.plate or '')
  ))
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

  logServiceState('released', ('runtime_id=%s source=%s plate=%s status=%s'):format(
    tostring(runtime.runtime_id or ''),
    tostring(source or ''),
    tostring(runtime.plate or ''),
    tostring(runtime.status or '')
  ))
  removeRuntime(runtime.runtime_id)
  return true, runtime
end

local function resolveNetworkEntity(netId)
  netId = tonumber(netId) or 0
  if netId <= 0 then
    return nil, 'service_vehicle_entity_required'
  end

  if type(NetworkDoesNetworkIdExist) == 'function' and not NetworkDoesNetworkIdExist(netId) then
    return nil, 'service_vehicle_entity_not_found'
  end

  local entity = type(NetworkGetEntityFromNetworkId) == 'function' and NetworkGetEntityFromNetworkId(netId) or 0
  if not entity or entity == 0 or (type(DoesEntityExist) == 'function' and not DoesEntityExist(entity)) then
    return nil, 'service_vehicle_entity_not_found'
  end

  return entity
end

local function validateStoreEntity(source, runtime, payload)
  local netId = tonumber(payload.net_id or 0) or 0
  if netId <= 0 then
    return false, 'service_vehicle_entity_required'
  end

  local runtimeNetId = tonumber(runtime.net_id or 0) or 0
  local entity, entityErr = resolveNetworkEntity(netId)

  if not entity then
    if runtimeNetId > 0 and runtimeNetId ~= netId then
      entity, entityErr = resolveNetworkEntity(runtimeNetId)
      if entity then
        logServiceState('entity_fallback', ('runtime_id=%s plate=%s payload_net_id=%s runtime_net_id=%s'):format(
          tostring(runtime.runtime_id or ''),
          tostring(runtime.plate or ''),
          tostring(netId),
          tostring(runtimeNetId)
        ))
      end
    end
  elseif runtimeNetId > 0 and netId ~= runtimeNetId then
    logServiceState('entity_migrated', ('runtime_id=%s plate=%s runtime_net_id=%s payload_net_id=%s'):format(
      tostring(runtime.runtime_id or ''),
      tostring(runtime.plate or ''),
      tostring(runtimeNetId),
      tostring(netId)
    ))
  end

  if not entity then
    return false, entityErr
  end

  if type(GetVehicleNumberPlateText) == 'function' then
    local entityPlate = normalizePlate(GetVehicleNumberPlateText(entity))
    if entityPlate ~= normalizePlate(runtime.plate) then
      return false, 'service_vehicle_plate_mismatch'
    end
  end

  local model = tostring(runtime.model or ''):lower()
  if model ~= '' and type(GetEntityModel) == 'function' and type(GetHashKey) == 'function' then
    if tonumber(GetEntityModel(entity)) ~= tonumber(GetHashKey(model)) then
      return false, 'service_vehicle_model_mismatch'
    end
  end

  if type(GetEntityRoutingBucket) == 'function' and type(GetPlayerRoutingBucket) == 'function' then
    if tonumber(GetEntityRoutingBucket(entity)) ~= tonumber(GetPlayerRoutingBucket(source)) then
      return false, 'service_vehicle_routing_bucket_mismatch'
    end
  end

  return true
end

function MZGaragemService.getActiveRuntimeFor(source, garageId)
  local normalizedGarageId = tostring(garageId or '')

  for _, runtime in pairs(runtimeState.by_id) do
    if runtime.status == 'active'
      and tonumber(runtime.source) == tonumber(source)
      and tostring(runtime.garage_id) == normalizedGarageId then
      return pruneRuntime(runtime)
    end
  end

  return nil
end

function MZGaragemService.store(source, access, payload)
  payload = type(payload) == 'table' and payload or {}
  rememberSourceCitizen(source, access and access.citizenid)
  local runtime = nil
  local runtimeId = tostring(payload.runtime_id or '')
  local plate = normalizePlate(payload.plate)

  if runtimeId ~= '' then
    runtime = pruneRuntime(getRuntime(runtimeId))
  end

  if not runtime and plate ~= '' then
    runtime = pruneRuntime(getRuntime(runtimeState.by_plate[plate]))
  end

  if not runtime then
    if plate ~= '' then
      local ok, persistent = pcall(function()
        return exports['mz_vehicles']:GetVehicleByPlate(plate)
      end)
      if ok and persistent == true then
        return false, 'vehicle_not_service'
      end
    end

    return false, 'runtime_not_found'
  end

  if tonumber(runtime.source) ~= tonumber(source) then
    return false, 'runtime_access_denied'
  end

  if tostring(runtime.citizenid) ~= tostring(access.citizenid) then
    return false, 'runtime_access_denied'
  end

  if tostring(runtime.garage_id) ~= tostring(access.garage.id) then
    return false, 'runtime_wrong_garage'
  end

  if runtime.status ~= 'active' then
    return false, 'service_vehicle_not_active'
  end

  if plate ~= '' and plate ~= normalizePlate(runtime.plate) then
    return false, 'service_vehicle_plate_mismatch'
  end

  local entityOk, entityErr = validateStoreEntity(source, runtime, payload)
  if not entityOk then
    return false, entityErr
  end

  saveState(runtime, payload)
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

  local normalizedSource = tonumber(source)
  local citizenid = normalizedSource and sourceCitizen[normalizedSource] or nil
  if citizenid then
    stateCache[citizenid] = nil
    sourceCitizen[normalizedSource] = nil
  end
end

function MZGaragemService.PrepareState()
  if not statePersistenceEnabled() then
    return true, 'service_state_persistence_disabled'
  end

  local repository = getStateRepository()
  if not repository or type(repository.prepare) ~= 'function' then
    return false, 'service_state_repository_unavailable'
  end

  local ok, err = pcall(repository.prepare)
  if not ok then
    print(('[mz_garagem] falha ao preparar estado da frota de servico: %s'):format(tostring(err)))
    return false, tostring(err)
  end

  return true
end

function MZGaragemService.resetAll()
  runtimeState.by_id = {}
  runtimeState.by_plate = {}
  runtimeState.by_player_garage = {}
  runtimeSequence = 0
  stateCache = {}
  sourceCitizen = {}
end
