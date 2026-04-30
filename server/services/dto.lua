MZGaragemDTO = MZGaragemDTO or {}

local STATE_ORDER = {
  active = 1,
  available = 2,
  stored = 3,
  impounded = 4,
  out = 5
}

local function cloneTable(value)
  if type(value) ~= 'table' then
    return value
  end

  local out = {}
  for key, item in pairs(value) do
    out[key] = type(item) == 'table' and cloneTable(item) or item
  end

  return out
end

local function trimScalarString(value)
  local valueType = type(value)
  if valueType == 'string' or valueType == 'number' or valueType == 'boolean' then
    return tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  end

  return ''
end

local function safeString(value, fallback)
  local text = trimScalarString(value)
  if text ~= '' then
    return text
  end

  return trimScalarString(fallback)
end

local function normalizeVehicleModel(value)
  return safeString(value, ''):lower()
end

local function getValidLabel(value, fallback1, fallback2)
  local normalized = safeString(value, '')
  if normalized ~= '' then
    return normalized
  end

  normalized = safeString(fallback1, '')
  if normalized ~= '' then
    return normalized
  end

  normalized = safeString(fallback2, '')
  if normalized ~= '' then
    return normalized
  end

  return 'Vehicle'
end

local function getValidImageKey(value, vehicleModel)
  local normalized = safeString(value, '')
  if normalized ~= '' then
    return normalized
  end

  return safeString(vehicleModel, '')
end

local function getGarageLabel(garageId)
  local garage = MZGaragemGarages and MZGaragemGarages[garageId] or nil
  if not garage then
    return tostring(garageId or '-')
  end

  return tostring(garage.label or garageId)
end

local function makeCommon(garage, kind, data)
  local model = normalizeVehicleModel(data.vehicle_model)
  local vehicleLabel = getValidLabel(data.vehicle_label, model, 'Vehicle')
  local brand = safeString(data.brand, '')
  local category = safeString(data.category, '')
  local imageKey = getValidImageKey(data.image_key, model)

  return {
    entry_id = safeString(data.entry_id, ''),
    kind = safeString(kind, ''),
    garage_id = safeString(garage.id, ''),
    garage_label = safeString(garage.label, safeString(garage.id, '')),
    org_code = data.org_code and safeString(data.org_code, nil) or nil,
    vehicle_model = model,
    vehicle_label = vehicleLabel,
    brand = brand,
    category = category,
    plate = safeString(data.plate, ''),
    state = tostring(data.state or 'stored'),
    fuel = tonumber(data.fuel) or 100,
    engine = tonumber(data.engine) or 1000,
    body = tonumber(data.body) or 1000,
    image_key = imageKey,
    location_label = safeString(data.location_label, safeString(garage.label, '')),
    actions = cloneTable(data.actions or {
      withdraw = false,
      store = false,
      track = false,
      release_impound = false
    }),
    flags = cloneTable(data.flags or {
      strict_garage = garage.rules and garage.rules.strict_garage == true or false,
      shared_pool = garage.rules and garage.rules.shared_pool == true or false,
      impounded = false
    }),
    runtime_id = data.runtime_id and tostring(data.runtime_id) or nil,
    service_meta = cloneTable(data.service_meta)
  }
end

local function applyCatalogDefaults(model, fallback)
  fallback = type(fallback) == 'table' and fallback or {}

  local normalizedModel = normalizeVehicleModel(model)
  local resolved = nil
  if MZGaragemVehicleDomain and type(MZGaragemVehicleDomain.resolveCatalog) == 'function' then
    resolved = MZGaragemVehicleDomain.resolveCatalog(normalizedModel, {
      label = fallback.vehicle_label,
      brand = fallback.brand,
      category = fallback.category,
      image_key = fallback.image_key
    })
  end

  resolved = type(resolved) == 'table' and resolved or {}

  local resolvedImageKey = ''
  if MZGaragemVehicleDomain and type(MZGaragemVehicleDomain.resolveImageKey) == 'function' then
    resolvedImageKey = MZGaragemVehicleDomain.resolveImageKey(normalizedModel, resolved.image_key or fallback.image_key)
  else
    resolvedImageKey = getValidImageKey(resolved.image_key or fallback.image_key, normalizedModel)
  end

  return {
    vehicle_model = normalizedModel,
    vehicle_label = getValidLabel(resolved.label, normalizedModel, 'Vehicle'),
    brand = safeString(resolved.brand, fallback.brand),
    category = safeString(resolved.category, fallback.category),
    image_key = getValidImageKey(resolvedImageKey, normalizedModel)
  }
end

local function resolveDisplayCategory(vehicleCategory, catalogCategory)
  local dbCategory = safeString(vehicleCategory, '')
  local resolvedCategory = safeString(catalogCategory, '')

  if dbCategory ~= '' and (resolvedCategory == '' or resolvedCategory == 'car') then
    return dbCategory
  end

  if resolvedCategory ~= '' then
    return resolvedCategory
  end

  return dbCategory
end

function MZGaragemDTO.buildGaragePayload(garage)
  return {
    id = tostring(garage.id or ''),
    label = tostring(garage.label or garage.id or ''),
    kind = tostring(garage.kind or ''),
    org_code = garage.org_code and tostring(garage.org_code) or nil
  }
end

function MZGaragemDTO.sort(entries)
  table.sort(entries, function(a, b)
    local aState = STATE_ORDER[a.state] or 99
    local bState = STATE_ORDER[b.state] or 99

    if aState ~= bState then
      return aState < bState
    end

    return tostring(a.vehicle_label or '') < tostring(b.vehicle_label or '')
  end)

  return entries
end

function MZGaragemDTO.buildOwnedEntry(garage, vehicle)
  local catalogDefaults = applyCatalogDefaults(vehicle.model, {})
  local state = tostring(vehicle.state or 'stored')
  local actions = {
    withdraw = state == 'stored',
    store = false,
    track = false,
    release_impound = state == 'impounded' and garage.rules.allow_impounded == true
  }

  return makeCommon(garage, 'owned', {
    entry_id = tostring(vehicle.plate or ''),
    vehicle_model = catalogDefaults.vehicle_model ~= '' and catalogDefaults.vehicle_model or vehicle.model,
    vehicle_label = catalogDefaults.vehicle_label,
    brand = catalogDefaults.brand,
    category = resolveDisplayCategory(vehicle.category, catalogDefaults.category),
    plate = tostring(vehicle.plate or ''),
    state = state,
    fuel = tonumber(vehicle.fuel) or 100,
    engine = tonumber(vehicle.engine) or 1000,
    body = tonumber(vehicle.body) or 1000,
    image_key = catalogDefaults.image_key,
    location_label = state == 'impounded' and 'Impounded' or getGarageLabel(vehicle.garage),
    actions = actions,
    flags = {
      strict_garage = garage.rules.strict_garage == true,
      shared_pool = garage.rules.shared_pool == true,
      impounded = state == 'impounded'
    }
  })
end

function MZGaragemDTO.buildOrgEntry(garage, vehicle)
  local entry = MZGaragemDTO.buildOwnedEntry(garage, vehicle)
  entry.kind = 'org'
  entry.org_code = garage.org_code and tostring(garage.org_code) or nil
  return entry
end

function MZGaragemDTO.buildServiceEntry(garage, fleetEntry, runtime, lockedByLimit)
  local catalogDefaults = applyCatalogDefaults(fleetEntry.model, {
    vehicle_label = fleetEntry.label,
    brand = fleetEntry.brand,
    category = fleetEntry.category,
    image_key = fleetEntry.image_key
  })
  local serviceVehicleLabel = getValidLabel(fleetEntry.label, catalogDefaults.vehicle_label, fleetEntry.model)
  local serviceBrand = safeString(fleetEntry.brand, catalogDefaults.brand)
  local serviceCategory = safeString(fleetEntry.category, catalogDefaults.category)
  local serviceImageKey = getValidImageKey(
    fleetEntry.image_key,
    catalogDefaults.image_key ~= '' and catalogDefaults.image_key or catalogDefaults.vehicle_model
  )
  local isActive = runtime ~= nil
  local state = isActive and 'active' or 'available'
  local actions = {
    withdraw = not isActive and lockedByLimit ~= true,
    store = false,
    track = false,
    release_impound = false
  }

  return makeCommon(garage, 'service', {
    entry_id = tostring(fleetEntry.entry_id or fleetEntry.model or ''),
    org_code = garage.org_code and tostring(garage.org_code) or nil,
    vehicle_model = catalogDefaults.vehicle_model ~= '' and catalogDefaults.vehicle_model or fleetEntry.model,
    vehicle_label = serviceVehicleLabel,
    brand = serviceBrand,
    category = serviceCategory,
    plate = runtime and tostring(runtime.plate or '') or '',
    state = state,
    fuel = runtime and tonumber(runtime.fuel) or tonumber(fleetEntry.fuel) or 100,
    engine = runtime and tonumber(runtime.engine) or tonumber(fleetEntry.engine) or 1000,
    body = runtime and tonumber(runtime.body) or tonumber(fleetEntry.body) or 1000,
    image_key = serviceImageKey,
    location_label = tostring(garage.label or garage.id or ''),
    actions = actions,
    flags = {
      strict_garage = false,
      shared_pool = false,
      impounded = false,
      locked_by_limit = lockedByLimit == true,
      active_runtime = isActive
    },
    runtime_id = runtime and runtime.runtime_id or nil,
    service_meta = {
      fleet_id = tostring(garage.fleet_id or ''),
      entry_id = tostring(fleetEntry.entry_id or ''),
      limit_one_active = garage.service.limit_one_active == true
    }
  })
end
