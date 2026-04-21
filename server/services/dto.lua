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

local function safeString(value, fallback)
  local valueType = type(value)
  if valueType == 'string' or valueType == 'number' or valueType == 'boolean' then
    local text = tostring(value)
    if text ~= '' then
      return text
    end
  end

  local fallbackType = type(fallback)
  if fallbackType == 'string' or fallbackType == 'number' or fallbackType == 'boolean' then
    return tostring(fallback)
  end

  return ''
end

local function getCatalog(model)
  if MZGaragemVehicleCatalog and type(MZGaragemVehicleCatalog.getEntry) == 'function' then
    return MZGaragemVehicleCatalog.getEntry(model)
  end

  model = tostring(model or ''):lower()
  return MZGaragemVehiclesCatalog and MZGaragemVehiclesCatalog[model] or nil
end

local function getGarageLabel(garageId)
  local garage = MZGaragemGarages and MZGaragemGarages[garageId] or nil
  if not garage then
    return tostring(garageId or '-')
  end

  return tostring(garage.label or garageId)
end

local function makeCommon(garage, kind, data)
  local model = safeString(data.vehicle_model, '')
  local vehicleLabel = safeString(data.vehicle_label, model ~= '' and model or 'Vehicle')
  local category = safeString(data.category, 'car')
  local imageKey = safeString(data.image_key, model)

  return {
    entry_id = safeString(data.entry_id, ''),
    kind = safeString(kind, ''),
    garage_id = safeString(garage.id, ''),
    garage_label = safeString(garage.label, safeString(garage.id, '')),
    org_code = data.org_code and safeString(data.org_code, nil) or nil,
    vehicle_model = model,
    vehicle_label = vehicleLabel,
    brand = safeString(data.brand, ''),
    category = category ~= '' and category or 'car',
    plate = safeString(data.plate, ''),
    state = tostring(data.state or 'stored'),
    fuel = tonumber(data.fuel) or 100,
    engine = tonumber(data.engine) or 1000,
    body = tonumber(data.body) or 1000,
    image_key = imageKey ~= '' and imageKey or model,
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
  if MZGaragemVehicleCatalog and type(MZGaragemVehicleCatalog.resolve) == 'function' then
    local resolved = MZGaragemVehicleCatalog.resolve(model, {
      label = fallback.vehicle_label,
      brand = fallback.brand,
      category = fallback.category,
      image_key = fallback.image_key
    })

    return {
      vehicle_label = safeString(resolved.label, safeString(model, 'Vehicle')),
      brand = safeString(resolved.brand, ''),
      category = safeString(resolved.category, 'car'),
      image_key = safeString(resolved.image_key, safeString(model, ''))
    }
  end

  local catalog = getCatalog(model) or {}

  return {
    vehicle_label = safeString(fallback.vehicle_label, safeString(catalog.label, safeString(model, 'Vehicle'))),
    brand = safeString(fallback.brand, safeString(catalog.brand, '')),
    category = safeString(fallback.category, safeString(catalog.category, 'car')),
    image_key = safeString(fallback.image_key, safeString(catalog.image_key, safeString(model, '')))
  }
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
    vehicle_model = tostring(vehicle.model or ''),
    vehicle_label = catalogDefaults.vehicle_label,
    brand = catalogDefaults.brand,
    category = tostring(vehicle.category or catalogDefaults.category),
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
    vehicle_model = tostring(fleetEntry.model or ''),
    vehicle_label = catalogDefaults.vehicle_label,
    brand = catalogDefaults.brand,
    category = catalogDefaults.category,
    plate = runtime and tostring(runtime.plate or '') or '',
    state = state,
    fuel = runtime and tonumber(runtime.fuel) or tonumber(fleetEntry.fuel) or 100,
    engine = runtime and tonumber(runtime.engine) or tonumber(fleetEntry.engine) or 1000,
    body = runtime and tonumber(runtime.body) or tonumber(fleetEntry.body) or 1000,
    image_key = catalogDefaults.image_key,
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
