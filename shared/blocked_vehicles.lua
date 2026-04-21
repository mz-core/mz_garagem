MZGaragemBlockedVehicles = MZGaragemBlockedVehicles or {
  hydra = { reason = 'military_aircraft' },
  rhino = { reason = 'military_vehicle' },
  lazer = { reason = 'military_aircraft' },
  apc = { reason = 'military_vehicle' }
}

MZGaragemBlocklist = MZGaragemBlocklist or {}

local function normalizeModel(model)
  return tostring(model or ''):lower()
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

function MZGaragemBlocklist.getRule(model)
  local ok, blocked, rule = callVehiclesExport('GetBlockedRule', model)
  if ok then
    if blocked == true then
      return true, type(rule) == 'table' and cloneTable(rule) or {}
    end

    return false, nil
  end

  local key = normalizeModel(model)
  if key == '' then
    return false, nil
  end

  local localRule = MZGaragemBlockedVehicles[key]
  if localRule == true then
    return true, {}
  end

  if type(localRule) == 'table' then
    return true, cloneTable(localRule)
  end

  return false, nil
end

function MZGaragemBlocklist.isBlocked(model)
  local ok, blocked, reason = callVehiclesExport('IsModelBlocked', model)
  if ok then
    return blocked == true, reason
  end

  local isBlocked, rule = MZGaragemBlocklist.getRule(model)
  if not isBlocked then
    return false, nil
  end

  local fallbackReason = type(rule) == 'table' and tostring(rule.reason or '') or ''
  if fallbackReason == '' then
    fallbackReason = nil
  end

  return true, fallbackReason
end
