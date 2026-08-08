MZGaragemManagedClient = MZGaragemManagedClient or {}

local managedIds = {}

local function asVector3(value)
  if type(value) == 'vector3' then return value end
  if type(value) ~= 'table' then return nil end
  local x = tonumber(value.x or value[1])
  local y = tonumber(value.y or value[2])
  local z = tonumber(value.z or value[3])
  return x and y and z and vector3(x, y, z) or nil
end

local function asVector4(value)
  if type(value) == 'vector4' then return value end
  if type(value) ~= 'table' then return nil end
  local x = tonumber(value.x or value[1])
  local y = tonumber(value.y or value[2])
  local z = tonumber(value.z or value[3])
  local w = tonumber(value.w or value.heading or value[4]) or 0.0
  return x and y and z and vector4(x, y, z, w) or nil
end

local function normalize(definition)
  if type(definition) ~= 'table' or tostring(definition.id or '') == '' then return nil end
  if type(definition.zone) == 'table' then
    definition.zone.coords = asVector3(definition.zone.coords)
  end
  if type(definition.store) == 'table' then
    definition.store.coords = asVector3(definition.store.coords)
    local marker = definition.store.interact
      and definition.store.interact.marker
      or nil
    if marker then marker.size = asVector3(marker.size) or marker.size end
  end
  for index, point in ipairs(definition.spawn_points or {}) do
    definition.spawn_points[index] = asVector4(point)
  end
  definition._managed = true
  return definition
end

local function upsert(definition, silent)
  definition = normalize(definition)
  if not definition then return false end
  MZGaragemGarages = MZGaragemGarages or {}
  MZGaragemGarages[definition.id] = definition
  managedIds[definition.id] = true
  if silent ~= true then TriggerEvent('mz_garagem:client:definitionsRefreshed') end
  return true
end

local function replace(rows)
  for code in pairs(managedIds) do
    if MZGaragemGarages and MZGaragemGarages[code] and MZGaragemGarages[code]._managed == true then
      MZGaragemGarages[code] = nil
    end
  end
  managedIds = {}

  for _, definition in ipairs(type(rows) == 'table' and rows or {}) do
    upsert(definition, true)
  end
  TriggerEvent('mz_garagem:client:definitionsRefreshed')
end

RegisterNetEvent('mz_garagem:client:managedGarageUpsert', function(definition)
  upsert(definition)
end)

RegisterNetEvent('mz_garagem:client:managedGarageRemove', function(code)
  code = tostring(code or '')
  if code == '' or managedIds[code] ~= true then return end
  if MZGaragemGarages and MZGaragemGarages[code] and MZGaragemGarages[code]._managed == true then
    MZGaragemGarages[code] = nil
  end
  managedIds[code] = nil
  TriggerEvent('mz_garagem:client:definitionsRefreshed')
end)

RegisterNetEvent('mz_garagem:client:managedGarageSnapshot', function(rows)
  replace(rows)
end)

CreateThread(function()
  Wait(500)
  local ok, response = pcall(lib.callback.await, 'mz_garagem:server:getManagedGarages', false)
  if ok and type(response) == 'table' and response.ok == true then
    replace(response.garages)
  end
end)
