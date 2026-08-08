MZGaragemVehicleDomain = MZGaragemVehicleDomain or {}

local function trimScalarString(value)
  local valueType = type(value)
  if valueType == 'string' or valueType == 'number' or valueType == 'boolean' then
    return tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  end

  return ''
end

local function normalizeModel(model)
  return trimScalarString(model):lower()
end

local function safeString(value, fallback)
  local text = trimScalarString(value)
  if text ~= '' then
    return text
  end

  return trimScalarString(fallback)
end

local function canUseVehiclesExports()
  return GetResourceState('mz_vehicles') == 'started'
end

local function logVehiclesBridgeError(exportName, err)
  print(('[mz_garagem][vehicle_domain] export "%s" failed: %s'):format(
    tostring(exportName or 'unknown'),
    tostring(err or 'unknown_error')
  ))
end

local function callVehiclesExport(exportName, ...)
  if not canUseVehiclesExports() then
    return false, nil, nil, 'mz_vehicles_unavailable'
  end

  local ok, a, b = pcall(function(...)
    local vehicleExports = exports['mz_vehicles']
    return vehicleExports[exportName](vehicleExports, ...)
  end, ...)

  if not ok then
    logVehiclesBridgeError(exportName, a)
    return false, nil, nil, 'mz_vehicles_export_failed'
  end

  return true, a, b, nil
end

local function sanitizeResolvedCatalog(model, entry, overrides)
  local key = normalizeModel(model)
  local data = type(entry) == 'table' and entry or {}
  local extra = type(overrides) == 'table' and overrides or {}

  local label = safeString(data.label, safeString(extra.label, key))
  if label == '' then
    label = 'Vehicle'
  end

  local category = safeString(data.category, safeString(extra.category, ''))
  local imageKey = safeString(data.image_key, safeString(extra.image_key, key))

  return {
    model = key,
    label = label,
    brand = safeString(data.brand, safeString(extra.brand, '')),
    category = category,
    image_key = imageKey ~= '' and imageKey or key
  }
end

function MZGaragemVehicleDomain.resolveCatalog(model, overrides)
  local key = normalizeModel(model)
  local safeOverrides = type(overrides) == 'table' and {
    label = safeString(overrides.label, ''),
    brand = safeString(overrides.brand, ''),
    category = safeString(overrides.category, ''),
    image_key = safeString(overrides.image_key, '')
  } or nil
  local ok, resolved = callVehiclesExport('ResolveCatalogEntry', key, safeOverrides)
  if ok and type(resolved) == 'table' then
    return sanitizeResolvedCatalog(key, resolved, safeOverrides)
  end

  return sanitizeResolvedCatalog(key, nil, safeOverrides)
end

function MZGaragemVehicleDomain.resolveImageKey(model, imageKey)
  local key = normalizeModel(model)
  local override = safeString(imageKey, '')
  local ok, resolved = callVehiclesExport('ResolveImageKey', key, override)
  if ok then
    local resolvedKey = safeString(resolved, '')
    if resolvedKey ~= '' then
      return resolvedKey
    end
  end

  if override ~= '' then
    return override
  end

  return key
end

function MZGaragemVehicleDomain.isBlocked(model)
  local ok, blocked, reason = callVehiclesExport('IsModelBlocked', model)
  if not ok then
    return false, nil
  end

  return blocked == true, reason
end
