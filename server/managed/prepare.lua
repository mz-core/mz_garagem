MZGaragemManagedPrepare = MZGaragemManagedPrepare or {}

function MZGaragemManagedPrepare.run()
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS mz_garage_definitions (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      garage_code VARCHAR(64) NOT NULL,
      label VARCHAR(120) NOT NULL,
      kind VARCHAR(16) NOT NULL,
      org_code VARCHAR(64) NULL,
      definition_json LONGTEXT NOT NULL,
      active TINYINT(1) NOT NULL DEFAULT 1,
      created_by_citizenid VARCHAR(64) NOT NULL,
      created_by_name VARCHAR(120) NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uq_mz_garage_definitions_code (garage_code),
      KEY idx_mz_garage_definitions_kind_active (kind, active),
      KEY idx_mz_garage_definitions_org_active (org_code, active)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  ]])

  return true
end
