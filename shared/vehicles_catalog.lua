MZGaragemVehiclesCatalog = MZGaragemVehiclesCatalog or {
  adder = {
    label = 'Adder',
    brand = 'Truffade',
    category = 'super',
    image_key = 'adder'
  },
  police = {
    label = 'Police Cruiser',
    brand = 'Vapid',
    category = 'car',
    image_key = 'police'
  },
  police2 = {
    label = 'Police Buffalo',
    brand = 'Bravado',
    category = 'car',
    image_key = 'police2'
  },
  police3 = {
    label = 'Police Interceptor',
    brand = 'Vapid',
    category = 'car',
    image_key = 'police3'
  },
  sultan = {
    label = 'Sultan',
    brand = 'Karin',
    category = 'car',
    image_key = 'sultan'
  }
}

MZGaragemVehicleCatalog = MZGaragemVehicleCatalog or {}

local function normalizeModel(model)
  return tostring(model or ''):lower()
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

local function canUseVehiclesExports()
  return IsDuplicityVersion() and GetResourceState('mz_vehicles') == 'started'
end

local function callVehiclesExport(exportName, ...)
  if not canUseVehiclesExports() then
    return false, nil
  end

  local ok, a, b = pcall(function(...)
    return exports['mz_vehicles'][exportName](...)
  end, ...)

  if not ok then
    return false, nil
  end

  return true, a, b
end

function MZGaragemVehicleCatalog.getEntry(model)
  local ok, entry = callVehiclesExport('GetCatalogEntry', model)
  if ok then
    if type(entry) ~= 'table' then
      return nil
    end

    return {
      label = safeString(entry.label, normalizeModel(model)),
      brand = safeString(entry.brand, ''),
      category = safeString(entry.category, 'car'),
      image_key = safeString(entry.image_key, normalizeModel(model))
    }
  end

  local localEntry = cloneTable(MZGaragemVehiclesCatalog[normalizeModel(model)])
  if type(localEntry) ~= 'table' then
    return nil
  end

  return {
    label = safeString(localEntry.label, normalizeModel(model)),
    brand = safeString(localEntry.brand, ''),
    category = safeString(localEntry.category, 'car'),
    image_key = safeString(localEntry.image_key, normalizeModel(model))
  }
end

function MZGaragemVehicleCatalog.resolve(model, overrides)
  local ok, resolved = callVehiclesExport('ResolveCatalogEntry', model, overrides)
  if ok and type(resolved) == 'table' then
    local key = normalizeModel(model)
    return {
      model = key,
      label = safeString(resolved.label, key ~= '' and key or 'Vehicle'),
      brand = safeString(resolved.brand, ''),
      category = safeString(resolved.category, 'car'),
      image_key = safeString(resolved.image_key, key)
    }
  end

  local key = normalizeModel(model)
  local entry = MZGaragemVehicleCatalog.getEntry(key) or {}
  local extra = type(overrides) == 'table' and overrides or {}
  local label = safeString(extra.label, safeString(entry.label, key))
  if label == '' then
    label = 'Vehicle'
  end

  local category = safeString(extra.category, safeString(entry.category, 'car'))
  if category == '' then
    category = 'car'
  end

  local imageKey = safeString(extra.image_key, safeString(entry.image_key, key))

  return {
    model = key,
    label = label,
    brand = safeString(extra.brand, safeString(entry.brand, '')),
    category = category,
    image_key = imageKey ~= '' and imageKey or key
  }
end

function MZGaragemVehicleCatalog.resolveImageKey(model, imageKey)
  local ok, resolved = callVehiclesExport('ResolveImageKey', model, imageKey)
  if ok and tostring(resolved or '') ~= '' then
    return tostring(resolved)
  end

  local override = tostring(imageKey or '')
  if override ~= '' then
    return override
  end

  local resolvedCatalog = MZGaragemVehicleCatalog.resolve(model, nil)
  return tostring(resolvedCatalog.image_key or '')
end
