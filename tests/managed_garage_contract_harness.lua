local callbacks = {}
local exported = {}
local clientEvents = {}
local grants = {}
local orgs = {
  mafia = { code = 'mafia', name = 'Mafia', type = 'gang', active = true },
  arquivo = { code = 'arquivo', name = 'Arquivo', type = 'job', active = false }
}
local rows = {}
local encodedValues = {}
local encodedSequence = 0

local function expect(condition, message)
  if not condition then error(message, 2) end
end

json = {
  encode = function(value)
    encodedSequence = encodedSequence + 1
    local token = ('encoded:%d'):format(encodedSequence)
    encodedValues[token] = value
    return token
  end,
  decode = function(value) return encodedValues[value] end
}

lib = {
  callback = {
    register = function(name, handler) callbacks[name] = handler end
  }
}

exports = setmetatable({
  mz_core = {
    HasGlobalPermission = function(_, sourceId, permission)
      return sourceId == 1 and grants[permission] == true
    end,
    GetPlayerSnapshot = function(_, sourceId)
      return sourceId == 1 and { citizenid = 'TEST001' } or nil
    end,
    GetOrgByCode = function(_, code)
      return orgs[code]
    end,
    CreateDetailedLog = function()
      return true
    end
  }
}, {
  __call = function(_, name, handler) exported[name] = handler end
})

function GetPlayerName(sourceId)
  return sourceId == 1 and 'Staff Test' or nil
end

function TriggerClientEvent(name, target, ...)
  clientEvents[#clientEvents + 1] = { name = name, target = target, args = { ... } }
end

MZGaragemGarages = {
  static_public = { id = 'static_public', kind = 'public' }
}

MZGaragemAccess = {
  validateGarageDefinition = function(_, garage)
    if type(garage) ~= 'table' or not garage.zone or not garage.zone.coords then
      return false, 'missing_zone'
    end
    if type(garage.spawn_points) ~= 'table' or #garage.spawn_points == 0 then
      return false, 'missing_spawn_points'
    end
    return true
  end
}

MZGaragemManagedPrepare = {
  run = function() return true end
}

MZGaragemManagedRepository = {
  listActive = function() return {} end,
  listAll = function()
    local out = {}
    for _, row in pairs(rows) do out[#out + 1] = row end
    return out
  end,
  getByCode = function(code) return rows[code] end,
  create = function(data)
    if rows[data.code] then error('duplicate') end
    rows[data.code] = {
      id = 1,
      garage_code = data.code,
      label = data.label,
      kind = data.kind,
      org_code = data.org_code,
      definition_json = data.definition_json,
      active = 1,
      created_by_citizenid = data.created_by_citizenid,
      created_by_name = data.created_by_name
    }
    return 1
  end,
  updateDefinition = function(code, data)
    local row = rows[code]
    row.label = data.label
    row.kind = data.kind
    row.org_code = data.org_code
    row.definition_json = data.definition_json
    return 1
  end,
  setActive = function(code, active)
    rows[code].active = active and 1 or 0
    return 1
  end
}

dofile('mz_garagem/server/managed/service.lua')

local ready = MZGaragemManaged.Initialize()
expect(ready == true, 'repositorio simulado nao iniciou')
expect(type(callbacks['mz_garagem:server:getManagedGarages']) == 'function', 'callback de snapshot ausente')
expect(type(exported.CreateManagedGarage) == 'function', 'export de criacao ausente')
expect(type(exported.ListManagedGarages) == 'function', 'export de listagem ausente')
expect(type(exported.ListManagedGaragesForAdmin) == 'function', 'export administrativo de listagem ausente')
expect(type(exported.UpdateManagedGarage) == 'function', 'export de edicao ausente')
expect(type(exported.SetManagedGarageActive) == 'function', 'export de ciclo de vida ausente')

local base = {
  code = 'central_test',
  label = 'Central Test',
  kind = 'public',
  entry = { x = 10, y = 20, z = 30 },
  spawn = { x = 12, y = 20, z = 30, w = 90 },
  store = { x = 8, y = 20, z = 30 },
  settings = {
    categoryMode = 'car',
    strictGarage = true,
    blipEnabled = true,
    allowImpounded = true
  }
}

local ok, err = MZGaragemManaged.Create(1, base)
expect(ok == false and err == 'permission_denied', 'criacao sem permissao nao falhou fechada')

grants['staff.garages.create'] = true
local injected = {}
for key, value in pairs(base) do injected[key] = value end
injected.hidden = true
ok, err = MZGaragemManaged.Create(1, injected)
expect(ok == false and err == 'invalid_payload', 'chave nao autorizada foi aceita')

local colliding = {}
for key, value in pairs(base) do colliding[key] = value end
colliding.code = 'static_public'
ok, err = MZGaragemManaged.Create(1, colliding)
expect(ok == false and err == 'garage_code_exists', 'colisao com garagem estatica foi aceita')

local archived = {}
for key, value in pairs(base) do archived[key] = value end
archived.code = 'arquivo_sede'
archived.kind = 'org'
archived.orgCode = 'arquivo'
ok, err = MZGaragemManaged.Create(1, archived)
expect(ok == false and err == 'org_archived', 'organizacao arquivada recebeu garagem')

ok, err = MZGaragemManaged.Create(1, base)
expect(ok == true and type(err) == 'table' and err.id == 'central_test', 'garagem publica valida nao foi criada')
expect(MZGaragemGarages.central_test ~= nil, 'runtime do servidor nao recebeu a garagem')
expect(#clientEvents == 1 and clientEvents[1].target == -1, 'garagem nao foi sincronizada com os clients')

local snapshot = callbacks['mz_garagem:server:getManagedGarages']()
expect(snapshot.ok == true and #snapshot.garages == 1, 'snapshot nao refletiu a garagem criada')

local defaultName = {}
for key, value in pairs(base) do defaultName[key] = value end
defaultName.code = 'default_name'
defaultName.label = ''
ok, err = MZGaragemManaged.Create(1, defaultName)
expect(ok == true and err.label == 'Garagem Pública', 'nome padrao publico nao foi aplicado ao label/blip')

grants['staff.garages.view'] = true
local listed, managed = MZGaragemManaged.ListForAdmin(1)
expect(listed == true and #managed == 2, 'listagem administrativa nao retornou ativos')

grants['staff.garages.manage'] = true
local edited = {}
for key, value in pairs(base) do edited[key] = value end
edited.label = 'Central Editada'
ok, err = MZGaragemManaged.Update(1, 'central_test', edited)
expect(ok == true and err.label == 'Central Editada', 'edicao valida nao atualizou label')

ok, err = MZGaragemManaged.SetActive(1, 'central_test', false)
expect(ok == true and err.active == false, 'arquivamento nao alterou estado')
expect(MZGaragemGarages.central_test == nil, 'arquivamento manteve runtime ativo')
expect(clientEvents[#clientEvents].name == 'mz_garagem:client:managedGarageRemove', 'arquivamento nao removeu client runtime')

print('mz_garagem managed garage contract harness: PASS')
