MZGaragemManagedRepository = MZGaragemManagedRepository or {}

function MZGaragemManagedRepository.listActive()
  return MySQL.query.await([[
    SELECT id, garage_code, label, kind, org_code, definition_json,
           created_by_citizenid, created_by_name, created_at, updated_at
    FROM mz_garage_definitions
    WHERE active = 1
    ORDER BY id ASC
  ]]) or {}
end

function MZGaragemManagedRepository.listAll()
  return MySQL.query.await([[
    SELECT id, garage_code, label, kind, org_code, definition_json,
           active, created_by_citizenid, created_by_name, created_at, updated_at
    FROM mz_garage_definitions
    ORDER BY active DESC, kind ASC, label ASC, id ASC
  ]]) or {}
end

function MZGaragemManagedRepository.getByCode(code)
  return MySQL.single.await([[
    SELECT id, garage_code, label, kind, org_code, definition_json,
           active, created_by_citizenid, created_by_name, created_at, updated_at
    FROM mz_garage_definitions
    WHERE garage_code = ?
    LIMIT 1
  ]], { code })
end

function MZGaragemManagedRepository.create(data)
  return MySQL.insert.await([[
    INSERT INTO mz_garage_definitions (
      garage_code, label, kind, org_code, definition_json,
      active, created_by_citizenid, created_by_name
    ) VALUES (?, ?, ?, ?, ?, 1, ?, ?)
  ]], {
    data.code,
    data.label,
    data.kind,
    data.org_code,
    data.definition_json,
    data.created_by_citizenid,
    data.created_by_name
  })
end

function MZGaragemManagedRepository.updateDefinition(code, data)
  return MySQL.update.await([[
    UPDATE mz_garage_definitions
    SET label = ?,
        kind = ?,
        org_code = ?,
        definition_json = ?,
        updated_at = CURRENT_TIMESTAMP
    WHERE garage_code = ?
  ]], {
    data.label,
    data.kind,
    data.org_code,
    data.definition_json,
    code
  })
end

function MZGaragemManagedRepository.setActive(code, active)
  return MySQL.update.await([[
    UPDATE mz_garage_definitions
    SET active = ?, updated_at = CURRENT_TIMESTAMP
    WHERE garage_code = ?
  ]], { active and 1 or 0, code })
end
