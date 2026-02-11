-- esquema+tuplas.sql
-- ------------------------------
-- Esquema MySQL para "Control de Acceso Militar"
-- Engine: InnoDB, charset=utf8mb4
-- ------------------------------

DROP DATABASE IF EXISTS sistema_acceso_militar;
CREATE DATABASE sistema_acceso_militar;
USE sistema_acceso_militar;


/* Tabla: ranks
   Descripción: lista de rangos militares. `level` es un valor numérico para comparaciones (mayor = rango más alto). */
CREATE TABLE IF NOT EXISTS ranks (
  id INT AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(16) NOT NULL UNIQUE,       -- p.ej. 'CPT', 'SFC'
  name VARCHAR(64) NOT NULL,               -- p.ej. 'Capitán'
  level TINYINT NOT NULL,                  -- valor numérico de comparación
  description TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;







-- tuplas ranks
-- Script: Insertar filas de ejemplo en la tabla `ranks`
-- Uso: pegar y ejecutar en tu cliente MySQL (asegúrate de que la tabla `ranks` ya exista).
-- Este script usa ON DUPLICATE KEY UPDATE para poder ejecutarlo varias veces sin insertar duplicados.

START TRANSACTION;

INSERT INTO ranks (code, name, level, description)
VALUES
  ('PVT', 'Soldado', 1, 'Rango inicial; nivel bajo'),
  ('LCPL', 'Cabo Segundo', 2, 'Rango subalterno'),
  ('CPL', 'Cabo', 3, 'Rango no comisionado'),
  ('SGT', 'Sargento', 4, 'Mando suboficial'),
  ('SSG', 'Sargento Primero', 5, 'Sargento con más experiencia'),
  ('WO', 'Warrant Officer', 6, 'Oficial técnico especializado'),
  ('2LT', 'Subteniente', 7, 'Oficial subalterno (2º)'),
  ('1LT', 'Teniente', 8, 'Oficial subalterno (1º)'),
  ('CPT', 'Capitán', 9, 'Oficial de nivel medio'),
  ('MAJ', 'Mayor', 10, 'Oficial superior/jefe de sección'),
  ('LTC', 'Teniente Coronel', 11, 'Oficial de alto rango'),
  ('COL', 'Coronel', 12, 'Comando de unidad grande'),
  ('BG', 'General de Brigada', 13, 'Estado mayor - general menor'),
  ('MG', 'General de División', 14, 'General de nivel medio'),
  ('LTG', 'Teniente General', 15, 'General de alto nivel'),
  ('GEN', 'General', 16, 'Máximo rango operacional');

-- Evita duplicados: actualiza nombre/level/description si ya existe el code
-- (requiere que exista índice UNIQUE sobre `code`)
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  level = VALUES(level),
  description = VALUES(description);

COMMIT;

-- Verifica los datos insertados (ordenados por nivel)
SELECT id, code, name, level, description, created_at
FROM ranks
ORDER BY level ASC;







-- Clearance / niveles de autorización
CREATE TABLE IF NOT EXISTS clearance_levels (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL UNIQUE,        -- 'CONFIDENTIAL','SECRET','TOP_SECRET'
  level_value TINYINT NOT NULL,            -- orden para comparaciones
  description TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;






-- tupla clearance_levels
-- Script: Insertar filas de ejemplo en la tabla `clearance_levels`
-- Uso: pegar y ejecutar en tu cliente MySQL. Asegúrate de que la tabla exista.
-- Permite re-ejecución segura gracias a ON DUPLICATE KEY UPDATE.

START TRANSACTION;

INSERT INTO clearance_levels (name, level_value, description)
VALUES
  ('UNCLASSIFIED', 0, 'Sin clasificación; acceso público limitado'),
  ('CONFIDENTIAL', 1, 'Información sensible de bajo nivel'),
  ('SECRET', 2, 'Información sensible que requiere control riguroso'),
  ('TOP_SECRET', 3, 'Acceso limitado a personal altamente autorizado'),
  ('COSMIC_TOP_SECRET', 4, 'Nivel extraordinario — uso en casos muy restringidos')
ON DUPLICATE KEY UPDATE
  level_value = VALUES(level_value),
  description = VALUES(description);

COMMIT;

-- Verificar contenido (ordenado por nivel_value asc)
SELECT id, name, level_value, description, created_at
FROM clearance_levels
ORDER BY level_value ASC;







/* Unidades / dependencias (jerárquica opcional) */
CREATE TABLE IF NOT EXISTS units (
  id INT AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(20) NOT NULL UNIQUE,        -- 'U-005'
  name VARCHAR(128) NOT NULL,
  parent_unit_id INT NULL,
  location VARCHAR(128) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_units_parent FOREIGN KEY (parent_unit_id) REFERENCES units(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;






-- tuplas units
-- ------------------------------------------------------------
-- Inserción corregida para subunidades (dos fases) evitando ERROR 1093
-- Asegúrate de que las unidades padre ('1DIV','2DIV','LOG','TRAIN','INTEL') ya existan.
-- ------------------------------------------------------------

-- FASE 1: obtener ids de padres ya existentes
SET @id_1DIV  = (SELECT id FROM units WHERE code = '1DIV');
SET @id_2DIV  = (SELECT id FROM units WHERE code = '2DIV');
SET @id_LOG   = (SELECT id FROM units WHERE code = 'LOG');
SET @id_TRAIN = (SELECT id FROM units WHERE code = 'TRAIN');
SET @id_INTEL = (SELECT id FROM units WHERE code = 'INTEL');

-- Inserta brigadas / unidades que dependen de los padres anteriores
START TRANSACTION;

INSERT INTO units (code, name, parent_unit_id, location, created_at)
VALUES
  ('1DIV-BDE1', '1st Brigade',    @id_1DIV,  'Garrison A', NOW()),
  ('1DIV-BDE2', '2nd Brigade',    @id_1DIV,  'Garrison B', NOW()),
  ('2DIV-BDE1', '3rd Brigade',    @id_2DIV,  'Garrison C', NOW()),
  ('LOG-TRANSPORT','Transport Unit', @id_LOG,'Central Depot', NOW()),
  ('TRAIN-ACAD', 'Training Academy', @id_TRAIN,'Base Z', NOW()),
  ('INTEL-HUMINT','Human Intelligence', @id_INTEL, 'Secure Lab', NOW())
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  location = VALUES(location),
  parent_unit_id = COALESCE(VALUES(parent_unit_id), parent_unit_id);

COMMIT;

-- FASE 2: ahora que '1DIV-BDE1' existe, capturamos su id y añadimos las compañías que la referencian
SET @id_1DIV_BDE1 = (SELECT id FROM units WHERE code = '1DIV-BDE1');

START TRANSACTION;

INSERT INTO units (code, name, parent_unit_id, location, created_at)
VALUES
  ('1DIV-COMP-ENG', 'Engineering Company', @id_1DIV_BDE1, 'Garrison A', NOW()),
  ('1DIV-COMP-MED', 'Medical Company',     @id_1DIV_BDE1, 'Field Hospital', NOW())
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  location = VALUES(location),
  parent_unit_id = COALESCE(VALUES(parent_unit_id), parent_unit_id);

COMMIT;

-- VERIFICACIÓN: mostrar jerarquía (padre.code)
SELECT
  u.id,
  u.code,
  u.name,
  u.location,
  p.code AS parent_code,
  u.created_at
FROM units u
LEFT JOIN units p ON u.parent_unit_id = p.id
ORDER BY COALESCE(p.code, u.code), u.code;







/* Personal militar (usuarios). service_number y badge_id deben ser únicos. */
CREATE TABLE IF NOT EXISTS personnel (
  id INT AUTO_INCREMENT PRIMARY KEY,
  service_number VARCHAR(32) NOT NULL UNIQUE,  -- ID militar
  badge_id VARCHAR(64) UNIQUE NULL,             -- identificador físico/QR
  first_name VARCHAR(80) NOT NULL,
  last_name VARCHAR(80) NOT NULL,
  dob DATE NULL,
  rank_id INT NOT NULL,
  unit_id INT NULL,
  clearance_id INT NULL,
  email VARCHAR(120) UNIQUE NULL,
  phone VARCHAR(30) NULL,
  status ENUM('active','suspended','retired','terminated') NOT NULL DEFAULT 'active',
  enlisted_date DATE NULL,
  discharge_date DATE NULL,
  photo_url VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_personnel_rank FOREIGN KEY (rank_id) REFERENCES ranks(id) ON DELETE RESTRICT,
  CONSTRAINT fk_personnel_unit FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE SET NULL,
  CONSTRAINT fk_personnel_clearance FOREIGN KEY (clearance_id) REFERENCES clearance_levels(id) ON DELETE SET NULL,
  INDEX idx_personnel_rank (rank_id),
  INDEX idx_personnel_unit (unit_id),
  INDEX idx_personnel_clearance (clearance_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;








-- tuplas personnel
-- Script: Generador aleatorio de filas para `personnel`
-- Requisitos: tablas `ranks`, `units`, `clearance_levels`, `personnel` creadas previamente.
-- Uso: ejecutar todo en un cliente MySQL. Luego llamar al procedimiento:
-- CALL seed_personnel_random(100); -- para generar 100 filas

-- 1) Crear tablas temporales con listas de nombres/apellidos (edítalas si quieres más)
DROP TEMPORARY TABLE IF EXISTS tmp_first_names;
CREATE TEMPORARY TABLE tmp_first_names (name VARCHAR(80) NOT NULL);
INSERT INTO tmp_first_names (name) VALUES
('Juan'),('María'),('Carlos'),('Ana'),('Luis'),('Sofía'),('Miguel'),('Laura'),
('Pedro'),('Rosa'),('Diego'),('Elena'),('Javier'),('Natalia'),('Andrés'),('Camila'),
('Óscar'),('Verónica'),('Héctor'),('Marta');

DROP TEMPORARY TABLE IF EXISTS tmp_last_names;
CREATE TEMPORARY TABLE tmp_last_names (name VARCHAR(80) NOT NULL);
INSERT INTO tmp_last_names (name) VALUES
('Pérez'),('Gómez'),('Ruiz'),('Martínez'),('Fernández'),('López'),('Santos'),('Vargas'),
('Alvarado'),('García'),('Cruz'),('Ramos'),('Ortiz'),('Silva'),('Méndez'),('Torres'),
('Núñez'),('Paz'),('Salinas'),('Silvestre');

-- 2) Cambiar delimitador para crear procedimiento
DELIMITER $$

DROP PROCEDURE IF EXISTS seed_personnel_random $$
CREATE PROCEDURE seed_personnel_random(IN p_count INT)
BEGIN
  DECLARE i INT DEFAULT 0;
  DECLARE v_first VARCHAR(80);
  DECLARE v_last VARCHAR(80);
  DECLARE v_rank_id INT;
  DECLARE v_rank_level INT;
  DECLARE v_unit_id INT;
  DECLARE v_clearance_id INT;
  DECLARE v_service_number VARCHAR(64);
  DECLARE v_badge VARCHAR(64);
  DECLARE v_email VARCHAR(160);
  DECLARE v_phone VARCHAR(32);
  DECLARE v_dob DATE;
  DECLARE v_enlisted DATE;
  DECLARE v_status ENUM('active','suspended','retired','terminated') DEFAULT 'active';

  -- seguridad: si las tablas maestras están vacías, salimos
  IF (SELECT COUNT(*) FROM ranks) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla ranks vacía. Inserta rangos antes de ejecutar el seed.';
  END IF;

  IF (SELECT COUNT(*) FROM units) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla units vacía. Inserta unidades antes de ejecutar el seed.';
  END IF;

  IF (SELECT COUNT(*) FROM clearance_levels) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla clearance_levels vacía. Inserta clearances antes de ejecutar el seed.';
  END IF;

  simple_loop: WHILE i < p_count DO
    -- elegir nombre y apellido aleatorio
    SELECT name INTO v_first FROM tmp_first_names ORDER BY RAND() LIMIT 1;
    SELECT name INTO v_last  FROM tmp_last_names ORDER BY RAND() LIMIT 1;

    -- elegir rango aleatorio
    SELECT id, level INTO v_rank_id, v_rank_level
      FROM ranks
      ORDER BY RAND()
      LIMIT 1;

    -- asignar unidad en función del nivel del rango
    SET v_unit_id = NULL;

    IF v_rank_level >= 11 THEN
      -- altos mandos: preferir HQ, INTEL, LOG si existen
      SELECT id INTO v_unit_id FROM units
      WHERE code IN ('HQ','INTEL','LOG')
      ORDER BY RAND() LIMIT 1;
    ELSEIF v_rank_level >= 7 THEN
      -- oficiales medios: preferir divisiones / brigadas / logistics
      SELECT id INTO v_unit_id FROM units
      WHERE code LIKE '1DIV%' OR code LIKE '2DIV%' OR code LIKE '%BDE%' OR code LIKE 'LOG%'
      ORDER BY RAND() LIMIT 1;
    ELSE
      -- suboficiales / tropa: preferir compañías, brigadas, training
      SELECT id INTO v_unit_id FROM units
      WHERE code LIKE '%COMP%' OR code LIKE '%BDE%' OR code LIKE 'TRAIN%' OR code LIKE '%COMP%'
      ORDER BY RAND() LIMIT 1;
    END IF;

    -- si no se encontró unidad específica, elegir cualquier unidad aleatoria
    IF v_unit_id IS NULL THEN
      SELECT id INTO v_unit_id FROM units ORDER BY RAND() LIMIT 1;
    END IF;

    -- asignar clearance según rank.level (mapeo configurable)
    -- Ajusta los nombres aquí si tu tabla clearance_levels tiene otros nombres
    IF v_rank_level >= 11 THEN
      SELECT id INTO v_clearance_id FROM clearance_levels WHERE name = 'COSMIC_TOP_SECRET' LIMIT 1;
    ELSEIF v_rank_level >= 8 THEN
      SELECT id INTO v_clearance_id FROM clearance_levels WHERE name = 'TOP_SECRET' LIMIT 1;
    ELSEIF v_rank_level >= 5 THEN
      SELECT id INTO v_clearance_id FROM clearance_levels WHERE name = 'SECRET' LIMIT 1;
    ELSE
      SELECT id INTO v_clearance_id FROM clearance_levels WHERE name = 'CONFIDENTIAL' LIMIT 1;
      -- si no existe CONFIDENTIAL, fallback a UNCLASSIFIED
      IF v_clearance_id IS NULL THEN
        SELECT id INTO v_clearance_id FROM clearance_levels WHERE name = 'UNCLASSIFIED' LIMIT 1;
      END IF;
    END IF;

    -- Si no hay clearance (por nombres distintos), tomar el clearance de menor nivel_value disponible
    IF v_clearance_id IS NULL THEN
      SELECT id INTO v_clearance_id FROM clearance_levels ORDER BY level_value ASC LIMIT 1;
    END IF;

    -- generar service_number y badge (no garantizan 100% unicidad, pero es suficiente para seed)
    SET v_service_number = CONCAT('SN-', DATE_FORMAT(CURDATE(), '%Y'), '-', LPAD(FLOOR(RAND()*1000000),6,'0'));
    SET v_badge = CONCAT('B-', LPAD(FLOOR(RAND()*99999999),8,'0'));

    -- generar email y phone
    SET v_email = LOWER(CONCAT(REPLACE(v_first,' ','') , '.', REPLACE(v_last,' ','') , '@mil.local'));
    SET v_phone = CONCAT('+5936', LPAD(FLOOR(RAND()*10000000),7,'0'));

    -- generar dob aleatorio entre (hoy - 55 años) y (hoy - 20 años)
    SELECT DATE_ADD(DATE_SUB(CURDATE(), INTERVAL (FLOOR(RAND()*35) + 20) YEAR),
                    INTERVAL FLOOR(RAND()*365) DAY)
      INTO v_dob;

    -- enlisted_date entre dob+18 años y hoy
    SELECT DATE_ADD(DATE_ADD(v_dob, INTERVAL 18 YEAR), INTERVAL FLOOR(RAND()*((DATEDIFF(CURDATE(), DATE_ADD(v_dob, INTERVAL 18 YEAR))))) DAY)
      INTO v_enlisted;

    -- insertar (ON DUPLICATE KEY UPDATE para poder re-ejecutar)
    INSERT INTO personnel
      (service_number, badge_id, first_name, last_name, dob, rank_id, unit_id, clearance_id,
       email, phone, status, enlisted_date, created_at)
    VALUES
      (v_service_number, v_badge, v_first, v_last, v_dob, v_rank_id, v_unit_id, v_clearance_id,
       v_email, v_phone, v_status, v_enlisted, NOW())
    ON DUPLICATE KEY UPDATE
      badge_id = VALUES(badge_id),
      first_name = VALUES(first_name),
      last_name = VALUES(last_name),
      dob = VALUES(dob),
      rank_id = VALUES(rank_id),
      unit_id = VALUES(unit_id),
      clearance_id = VALUES(clearance_id),
      email = VALUES(email),
      phone = VALUES(phone),
      status = VALUES(status),
      enlisted_date = VALUES(enlisted_date),
      updated_at = NOW();

    SET i = i + 1;
  END WHILE simple_loop;

END $$
DELIMITER ;

-- EJEMPLO de uso:
-- Generar 100 registros de personal
CALL seed_personnel_random(100);

-- Verificar algunas filas insertadas
SELECT id, service_number, badge_id, first_name, last_name, rank_id, unit_id, clearance_id, status
FROM personnel
ORDER BY id DESC
LIMIT 50;









/* Permisos especiales (discrecionales) */
CREATE TABLE IF NOT EXISTS permissions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(50) NOT NULL UNIQUE,      -- 'ACCESS_SENSITIVE_SITE'
  name VARCHAR(100) NOT NULL,
  description TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;








-- tuplas permissions
-- ------------------------------------------------------------
-- Script: Insertar filas de ejemplo en la tabla `permissions`
-- Uso: pegar y ejecutar en tu cliente MySQL. Tabla `permissions` debe existir.
-- ------------------------------------------------------------

START TRANSACTION;

INSERT INTO permissions (code, name, description, created_at)
VALUES
  ('ACCESS_SENSITIVE_SITE', 'Acceso Sitio Sensible', 'Permite entrada a áreas con restricción adicional (requiere validación extra).', NOW()),
  ('NIGHT_SHIFT', 'Turno Nocturno', 'Permiso para realizar tareas y accesos durante horas nocturnas fuera del horario normal.', NOW()),
  ('MAINTENANCE_ACCESS', 'Acceso Mantenimiento', 'Permite acceso a áreas técnicas para personal de mantenimiento.', NOW()),
  ('TEMPORARY_VISIT', 'Visita Temporal', 'Permiso temporal otorgado a visitantes o contratistas por un periodo limitado.', NOW()),
  ('VEHICLE_ENTRY', 'Entrada Vehicular', 'Permite el ingreso y circulación de vehículos en áreas controladas.', NOW()),
  ('INTEL_OVERRIDE', 'Override Inteligencia', 'Permiso especial para personal de inteligencia con privilegios adicionales.', NOW()),
  ('BIOMETRIC_BYPASS', 'Bypass Biométrico', 'Permiso para exenciones temporales en sistemas biométricos (uso restringido y auditado).', NOW()),
  ('EMERGENCY_RESPONSE', 'Respuesta de Emergencia', 'Permiso para personal de respuesta rápida que debe acceder en situaciones de emergencia.', NOW()),
  ('VISITOR_ESCORT', 'Acompañamiento de Visitantes', 'Autoriza a personal a escoltar visitantes dentro de zonas restringidas.', NOW()),
  ('REMOTE_ACCESS', 'Acceso Remoto', 'Permite operaciones desde terminales/estaciones remotas con autenticación adicional.', NOW())
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  description = VALUES(description);

COMMIT;

-- Verificar permisos insertados
SELECT id, code, name, description, created_at
FROM permissions
ORDER BY id;








/* Tabla puente: permisos asignados a personal */
CREATE TABLE IF NOT EXISTS personnel_permissions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  personnel_id INT NOT NULL,
  permission_id INT NOT NULL,
  granted_by INT NULL,                   -- quien concedió (referencia a personnel.id)
  granted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NULL,
  reason VARCHAR(255) NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT fk_pp_personnel FOREIGN KEY (personnel_id) REFERENCES personnel(id) ON DELETE CASCADE,
  CONSTRAINT fk_pp_permission FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE,
  CONSTRAINT fk_pp_granted_by FOREIGN KEY (granted_by) REFERENCES personnel(id) ON DELETE SET NULL,
  UNIQUE KEY uk_person_perm (personnel_id, permission_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;









-- tuplas personnel_permissions
-- ------------------------------------------------------------
-- Script: Población automática de `personnel_permissions`
-- Descripción:
--   Procedimiento almacenado que recorre todos los personnel existentes
--   y asigna permisos en base a reglas heurísticas (rango, clearance, unidad)
--   y cierta aleatoriedad. Usa ON DUPLICATE KEY UPDATE para poder re-ejecutarse.
--
-- Requisitos previos:
--   - Tablas: personnel, ranks, clearance_levels, units, permissions, personnel_permissions
--   - Los códigos de permisos están presentes en la tabla `permissions`.
--
-- Uso:
--   Ejecutar todo el script. Luego:
--     CALL seed_personnel_permissions();
--   Para verificar:
--     SELECT * FROM personnel_permissions ORDER BY personnel_id LIMIT 200;
-- ------------------------------------------------------------

-- Cambiar delimitador para crear el procedimiento
DELIMITER $$

DROP PROCEDURE IF EXISTS seed_personnel_permissions $$
CREATE PROCEDURE seed_personnel_permissions()
BEGIN
  DECLARE done INT DEFAULT 0;

  -- Variables para cursor de personnel
  DECLARE v_pid INT;
  DECLARE v_rank_level INT;
  DECLARE v_clearance_level_value INT;
  DECLARE v_unit_code VARCHAR(64);

  -- Variables para permisos (ids)
  DECLARE p_access_sensitive INT;
  DECLARE p_night_shift INT;
  DECLARE p_maintenance INT;
  DECLARE p_temporary_visit INT;
  DECLARE p_vehicle_entry INT;
  DECLARE p_intel_override INT;
  DECLARE p_biometric_bypass INT;
  DECLARE p_emergency INT;
  DECLARE p_visitor_escort INT;
  DECLARE p_remote_access INT;

  -- Variables auxiliares
  DECLARE v_granted_by INT;
  DECLARE v_expires DATETIME;
  DECLARE v_reason VARCHAR(255);
  DECLARE v_rand DOUBLE;

  -- Cursor para recorrer personnel con datos necesarios
  DECLARE cur_person CURSOR FOR
    SELECT p.id,
           COALESCE(r.level, 0) AS rank_level,
           COALESCE(c.level_value, 0) AS clearance_level_value,
           COALESCE(u.code, '') AS unit_code
    FROM personnel p
    LEFT JOIN ranks r ON p.rank_id = r.id
    LEFT JOIN clearance_levels c ON p.clearance_id = c.id
    LEFT JOIN units u ON p.unit_id = u.id;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  -- 1) Obtener ids de permisos por código. Si falta alguno, lanzar error.
  SELECT id INTO p_access_sensitive FROM permissions WHERE code = 'ACCESS_SENSITIVE_SITE' LIMIT 1;
  IF p_access_sensitive IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso ACCESS_SENSITIVE_SITE'; END IF;

  SELECT id INTO p_night_shift FROM permissions WHERE code = 'NIGHT_SHIFT' LIMIT 1;
  IF p_night_shift IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso NIGHT_SHIFT'; END IF;

  SELECT id INTO p_maintenance FROM permissions WHERE code = 'MAINTENANCE_ACCESS' LIMIT 1;
  IF p_maintenance IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso MAINTENANCE_ACCESS'; END IF;

  SELECT id INTO p_temporary_visit FROM permissions WHERE code = 'TEMPORARY_VISIT' LIMIT 1;
  IF p_temporary_visit IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso TEMPORARY_VISIT'; END IF;

  SELECT id INTO p_vehicle_entry FROM permissions WHERE code = 'VEHICLE_ENTRY' LIMIT 1;
  IF p_vehicle_entry IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso VEHICLE_ENTRY'; END IF;

  SELECT id INTO p_intel_override FROM permissions WHERE code = 'INTEL_OVERRIDE' LIMIT 1;
  IF p_intel_override IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso INTEL_OVERRIDE'; END IF;

  SELECT id INTO p_biometric_bypass FROM permissions WHERE code = 'BIOMETRIC_BYPASS' LIMIT 1;
  IF p_biometric_bypass IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso BIOMETRIC_BYPASS'; END IF;

  SELECT id INTO p_emergency FROM permissions WHERE code = 'EMERGENCY_RESPONSE' LIMIT 1;
  IF p_emergency IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso EMERGENCY_RESPONSE'; END IF;

  SELECT id INTO p_visitor_escort FROM permissions WHERE code = 'VISITOR_ESCORT' LIMIT 1;
  IF p_visitor_escort IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso VISITOR_ESCORT'; END IF;

  SELECT id INTO p_remote_access FROM permissions WHERE code = 'REMOTE_ACCESS' LIMIT 1;
  IF p_remote_access IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso REMOTE_ACCESS'; END IF;

  -- 2) Abrir cursor y procesar personal uno por uno
  OPEN cur_person;
  read_loop: LOOP
    FETCH cur_person INTO v_pid, v_rank_level, v_clearance_level_value, v_unit_code;
    IF done = 1 THEN
      LEAVE read_loop;
    END IF;

    -- Inicializar
    SET v_granted_by = NULL;
    SET v_expires = NULL;
    SET v_reason = NULL;

    -- Función auxiliar simulada: elegir granted_by como una persona con rango >= v_rank_level + 2 (si existe)
    -- Si no existe, dejar NULL.
    SELECT p2.id INTO v_granted_by
    FROM personnel p2
    JOIN ranks r2 ON p2.rank_id = r2.id
    WHERE r2.level >= v_rank_level + 2
    ORDER BY RAND() LIMIT 1;

    -- Si no existe, intentar con rango >= 8 (oficiales superiores)
    IF v_granted_by IS NULL THEN
      SELECT p2.id INTO v_granted_by
      FROM personnel p2
      JOIN ranks r2 ON p2.rank_id = r2.id
      WHERE r2.level >= 8
      ORDER BY RAND() LIMIT 1;
    END IF;

    -- Helper rand value once per personnel
    SET v_rand = RAND();

    -- -------------------------
    -- REGLA: ACCESS_SENSITIVE_SITE
    -- -------------------------
    -- Grant if: rank_level >=5 OR clearance_level_value >=2 OR random < 0.25
    IF v_rank_level >= 5 OR v_clearance_level_value >= 2 OR v_rand < 0.25 THEN
      SET v_expires = DATE_ADD(NOW(), INTERVAL FLOOR(RAND()*365) + 30 DAY); -- 30..395 days
      SET v_reason = 'auto_by_rank_or_clearance_or_random';
      INSERT INTO personnel_permissions
        (personnel_id, permission_id, granted_by, granted_at, expires_at, reason, active)
      VALUES
        (v_pid, p_access_sensitive, v_granted_by, NOW(), v_expires, v_reason, TRUE)
      ON DUPLICATE KEY UPDATE
        granted_by = VALUES(granted_by),
        granted_at = VALUES(granted_at),
        expires_at = VALUES(expires_at),
        reason = VALUES(reason),
        active = VALUES(active);
    END IF;

    -- -------------------------
    -- REGLA: INTEL_OVERRIDE
    -- -------------------------
    -- Grant if: clearance is the highest (level_value very high) OR rank_level >=11
    IF v_rank_level >= 11 OR v_clearance_level_value >= 4 THEN
      SET v_expires = NULL; -- normalmente permanente hasta revocación
      SET v_reason = 'intel_override_by_rank_or_clearance';
      INSERT INTO personnel_permissions
        (personnel_id, permission_id, granted_by, granted_at, expires_at, reason, active)
      VALUES
        (v_pid, p_intel_override, v_granted_by, NOW(), v_expires, v_reason, TRUE)
      ON DUPLICATE KEY UPDATE
        granted_by = VALUES(granted_by),
        granted_at = VALUES(granted_at),
        expires_at = VALUES(expires_at),
        reason = VALUES(reason),
        active = VALUES(active);
    END IF;

    -- -------------------------
    -- REGLA: EMERGENCY_RESPONSE
    -- -------------------------
    -- Grant if: rank_level >=7 OR unit_code LIKE 'LOG%' OR random < 0.10
    IF v_rank_level >= 7 OR v_unit_code LIKE 'LOG%' OR v_rand < 0.10 THEN
      SET v_expires = NULL;
      SET v_reason = 'emergency_by_rank_unit_or_random';
      INSERT INTO personnel_permissions
        (personnel_id, permission_id, granted_by, granted_at, expires_at, reason, active)
      VALUES
        (v_pid, p_emergency, v_granted_by, NOW(), v_expires, v_reason, TRUE)
      ON DUPLICATE KEY UPDATE
        granted_by = VALUES(granted_by),
        granted_at = VALUES(granted_at),
        expires_at = VALUES(expires_at),
        reason = VALUES(reason),
        active = VALUES(active);
    END IF;

    -- -------------------------
    -- REGLA: MAINTENANCE_ACCESS
    -- -------------------------
    -- Grant if: unit_code LIKE '%COMP%' OR unit_code LIKE 'LOG%' OR random < 0.20
    IF v_unit_code LIKE '%COMP%' OR v_unit_code LIKE 'LOG%' OR v_rand < 0.20 THEN
      SET v_expires = DATE_ADD(NOW(), INTERVAL FLOOR(RAND()*365) + 30 DAY);
      SET v_reason = 'maintenance_by_unit_or_random';
      INSERT INTO personnel_permissions
        (personnel_id, permission_id, granted_by, granted_at, expires_at, reason, active)
      VALUES
        (v_pid, p_maintenance, v_granted_by, NOW(), v_expires, v_reason, TRUE)
      ON DUPLICATE KEY UPDATE
        granted_by = VALUES(granted_by),
        granted_at = VALUES(granted_at),
        expires_at = VALUES(expires_at),
        reason = VALUES(reason),
        active = VALUES(active);
    END IF;

    -- -------------------------
    -- REGLA: NIGHT_SHIFT
    -- -------------------------
    -- Grant random ~20% or if unit is training
    IF v_unit_code LIKE 'TRAIN%' OR v_rand < 0.20 THEN
      SET v_expires = NULL;
      SET v_reason = 'night_shift_auto';
      INSERT INTO personnel_permissions
        (personnel_id, permission_id, granted_by, granted_at, expires_at, reason, active)
      VALUES
        (v_pid, p_night_shift, v_granted_by, NOW(), v_expires, v_reason, TRUE)
      ON DUPLICATE KEY UPDATE
        granted_by = VALUES(granted_by),
        granted_at = VALUES(granted_at),
        expires_at = VALUES(expires_at),
        reason = VALUES(reason),
        active = VALUES(active);
    END IF;

    -- -------------------------
    -- REGLA: VEHICLE_ENTRY
    -- -------------------------
    -- Grant if unit is logistics or random < 0.15
    IF v_unit_code LIKE 'LOG%' OR v_rand < 0.15 THEN
      SET v_expires = NULL;
      SET v_reason = 'vehicle_entry_auto';
      INSERT INTO personnel_permissions
        (personnel_id, permission_id, granted_by, granted_at, expires_at, reason, active)
      VALUES
        (v_pid, p_vehicle_entry, v_granted_by, NOW(), v_expires, v_reason, TRUE)
      ON DUPLICATE KEY UPDATE
        granted_by = VALUES(granted_by),
        granted_at = VALUES(granted_at),
        expires_at = VALUES(expires_at),
        reason = VALUES(reason),
        active = VALUES(active);
    END IF;

    -- -------------------------
    -- REGLA: BIOMETRIC_BYPASS
    -- -------------------------
    -- Very restricted: rank_level >=10 and random < 0.10
    IF v_rank_level >= 10 AND RAND() < 0.10 THEN
      SET v_expires = DATE_ADD(NOW(), INTERVAL FLOOR(RAND()*90)+1 DAY); -- short window 1..90 days
      SET v_reason = 'biometric_bypass_restricted';
      INSERT INTO personnel_permissions
        (personnel_id, permission_id, granted_by, granted_at, expires_at, reason, active)
      VALUES
        (v_pid, p_biometric_bypass, v_granted_by, NOW(), v_expires, v_reason, TRUE)
      ON DUPLICATE KEY UPDATE
        granted_by = VALUES(granted_by),
        granted_at = VALUES(granted_at),
        expires_at = VALUES(expires_at),
        reason = VALUES(reason),
        active = VALUES(active);
    END IF;

    -- -------------------------
    -- REGLA: VISITOR_ESCORT
    -- -------------------------
    -- Grant if rank_level >=4 OR random < 0.10
    IF v_rank_level >= 4 OR v_rand < 0.10 THEN
      SET v_expires = NULL;
      SET v_reason = 'visitor_escort_auto';
      INSERT INTO personnel_permissions
        (personnel_id, permission_id, granted_by, granted_at, expires_at, reason, active)
      VALUES
        (v_pid, p_visitor_escort, v_granted_by, NOW(), v_expires, v_reason, TRUE)
      ON DUPLICATE KEY UPDATE
        granted_by = VALUES(granted_by),
        granted_at = VALUES(granted_at),
        expires_at = VALUES(expires_at),
        reason = VALUES(reason),
        active = VALUES(active);
    END IF;

    -- -------------------------
    -- REGLA: REMOTE_ACCESS
    -- -------------------------
    -- Grant if clearance >= SECRET (level_value >=2) OR random < 0.10
    IF v_clearance_level_value >= 2 OR v_rand < 0.10 THEN
      SET v_expires = DATE_ADD(NOW(), INTERVAL FLOOR(RAND()*365) + 30 DAY);
      SET v_reason = 'remote_access_auto';
      INSERT INTO personnel_permissions
        (personnel_id, permission_id, granted_by, granted_at, expires_at, reason, active)
      VALUES
        (v_pid, p_remote_access, v_granted_by, NOW(), v_expires, v_reason, TRUE)
      ON DUPLICATE KEY UPDATE
        granted_by = VALUES(granted_by),
        granted_at = VALUES(granted_at),
        expires_at = VALUES(expires_at),
        reason = VALUES(reason),
        active = VALUES(active);
    END IF;

    -- NOTA: temporalidad/expires y reason son heurísticos; puedes cambiarlos si quieres.

  END LOOP read_loop;

  CLOSE cur_person;

  -- Commit explícito por si se requiere (estado por defecto es autocommit, pero mantenemos coherencia)
  COMMIT;
END $$
DELIMITER ;

-- EJECUTAR el procedimiento para asignar permisos automáticamente
CALL seed_personnel_permissions();

-- Verificación: mostrar algunos resultados junto al rango/clearance para entender asignaciones
SELECT pp.personnel_id, p.service_number, p.first_name, p.last_name,
       r.code AS rank_code, r.level AS rank_level,
       cl.name AS clearance, per.code AS unit_code,
       perm.code AS permission_code, pp.granted_at, pp.expires_at, pp.reason, pp.active
FROM personnel_permissions pp
JOIN permissions perm ON pp.permission_id = perm.id
JOIN personnel p ON pp.personnel_id = p.id
LEFT JOIN ranks r ON p.rank_id = r.id
LEFT JOIN clearance_levels cl ON p.clearance_id = cl.id
LEFT JOIN units per ON p.unit_id = per.id
ORDER BY pp.personnel_id, perm.code
LIMIT 200;










/* Zonas restringidas. Las reglas pueden combinar min_rank_level, required_clearance_id y permisos. */
CREATE TABLE IF NOT EXISTS restricted_zones (
  id INT AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(32) NOT NULL UNIQUE,     -- 'CZ-01'
  name VARCHAR(120) NOT NULL,
  location_description VARCHAR(255) NULL,
  min_rank_level TINYINT NULL,          -- compara con ranks.level (si NULL, no aplica)
  required_clearance_id INT NULL,       -- FK a clearance_levels (si NULL, no aplica)
  requires_special_permission BOOLEAN NOT NULL DEFAULT FALSE,
  capacity INT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  notes TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_zone_clearance FOREIGN KEY (required_clearance_id) REFERENCES clearance_levels(id) ON DELETE SET NULL,
  INDEX idx_zone_minrank (min_rank_level),
  INDEX idx_zone_clearance (required_clearance_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;










-- tuplas restricted_zoness
-- ------------------------------------------------------------
-- Script: Insertar filas de ejemplo en `restricted_zones`
-- Requisitos: tabla clearance_levels y permissions deben existir.
-- ------------------------------------------------------------

START TRANSACTION;

INSERT INTO restricted_zones
  (code, name, location_description, min_rank_level, required_clearance_id, requires_special_permission, capacity, active, notes, created_at)
VALUES
  ('CZ-HQ', 'Zona Headquarters', 'Área central de mando — alta seguridad',
    11, (SELECT id FROM clearance_levels WHERE name = 'COSMIC_TOP_SECRET'), TRUE, 50, TRUE,
    'Acceso extremadamente restringido; normalmente solo altos mandos', NOW()),

  ('CZ-CONTROL', 'Centro de Control', 'Sala de control de operaciones críticas',
    7, (SELECT id FROM clearance_levels WHERE name = 'TOP_SECRET'), TRUE, 20, TRUE,
    'Requiere rango medio/alto o permiso especial', NOW()),

  ('CZ-INTEL', 'Área Inteligencia', 'Sección de inteligencia y análisis',
    9, (SELECT id FROM clearance_levels WHERE name = 'COSMIC_TOP_SECRET'), TRUE, 15, TRUE,
    'Acceso con clearance alto; adicionalmente puede requerir permiso INTEL_OVERRIDE', NOW()),

  ('CZ-MAINT', 'Área Mantenimiento', 'Talleres y salas técnicas (mantenimiento)',
    NULL, (SELECT id FROM clearance_levels WHERE name = 'CONFIDENTIAL'), TRUE, 30, TRUE,
    'Personal de mantenimiento y logística; usualmente requiere permiso MAINTENANCE_ACCESS', NOW()),

  ('CZ-LOGISTICS', 'Depósito Logístico', 'Zona de almacenamiento y vehículos',
    4, (SELECT id FROM clearance_levels WHERE name = 'CONFIDENTIAL'), FALSE, 200, TRUE,
    'Acceso a personal logístico; vehículo permitido con permiso VEHICLE_ENTRY', NOW()),

  ('CZ-TRAIN', 'Academia / Entrenamiento', 'Zona de adiestramiento y simuladores',
    NULL, (SELECT id FROM clearance_levels WHERE name = 'UNCLASSIFIED'), FALSE, 150, TRUE,
    'Área menos restringida; muchos permisos temporales (TEMPORARY_VISIT)', NOW()),

  ('CZ-VISITOR', 'Punto de Visitantes', 'Área controlada para visitantes y escoltas',
    NULL, (SELECT id FROM clearance_levels WHERE name = 'UNCLASSIFIED'), TRUE, 40, TRUE,
    'Requiere escolta (VISITOR_ESCORT) o permiso temporal', NOW()),

  ('CZ-EH', 'Entrada Emergencias', 'Acceso rápido para respuesta de emergencias',
    5, (SELECT id FROM clearance_levels WHERE name = 'CONFIDENTIAL'), TRUE, 10, TRUE,
    'Permisos de EMERGENCY_RESPONSE deberían permitir acceso inmediato', NOW())
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  location_description = VALUES(location_description),
  min_rank_level = VALUES(min_rank_level),
  required_clearance_id = VALUES(required_clearance_id),
  requires_special_permission = VALUES(requires_special_permission),
  capacity = VALUES(capacity),
  active = VALUES(active),
  notes = VALUES(notes);

COMMIT;

-- Verificación: mostrar zonas con nombre del clearance (si existe)
SELECT z.id, z.code, z.name, z.min_rank_level,
       cl.name AS required_clearance,
       z.requires_special_permission, z.capacity, z.active, z.notes, z.created_at
FROM restricted_zones z
LEFT JOIN clearance_levels cl ON z.required_clearance_id = cl.id
ORDER BY z.code;

-- ------------------------------------------------------------
-- (OPCIONAL) Mapeo zona ↔ permiso (zone_permission_requirements)
-- Descomenta y ejecuta si quieres crear reglas que asocien zonas a permisos ya definidos.
-- ------------------------------------------------------------
/*
START TRANSACTION;

INSERT INTO zone_permission_requirements (zone_id, permission_id, required, notes)
VALUES
  ((SELECT id FROM restricted_zones WHERE code='CZ-INTEL'),
   (SELECT id FROM permissions WHERE code='INTEL_OVERRIDE'), TRUE, 'INTEL area: override required'),
  ((SELECT id FROM restricted_zones WHERE code='CZ-CONTROL'),
   (SELECT id FROM permissions WHERE code='ACCESS_SENSITIVE_SITE'), TRUE, 'Centro de control requiere permiso sensible'),
  ((SELECT id FROM restricted_zones WHERE code='CZ-MAINT'),
   (SELECT id FROM permissions WHERE code='MAINTENANCE_ACCESS'), TRUE, 'Mantenimiento requiere permiso de mantenimiento'),
  ((SELECT id FROM restricted_zones WHERE code='CZ-LOGISTICS'),
   (SELECT id FROM permissions WHERE code='VEHICLE_ENTRY'), FALSE, 'Depósito: vehicular si aplica'),
  ((SELECT id FROM restricted_zones WHERE code='CZ-VISITOR'),
   (SELECT id FROM permissions WHERE code='TEMPORARY_VISIT'), TRUE, 'Zona de visitantes requiere permiso temporal o escolta')
ON DUPLICATE KEY UPDATE
  required = VALUES(required),
  notes = VALUES(notes);

COMMIT;
*/

-- NOTA:
-- - Si alguna subconsulta (SELECT id FROM clearance_levels WHERE name='...') devuelve NULL,
--   el campo required_clearance_id quedará NULL. Asegúrate de que los nombres de clearance_levels coincidan.
-- - Ajusta códigos de zona, min_rank_level y nombres de clearance si usas una convención distinta.









/* Mapping zona ↔ permiso (reglas específicas requeridas por zona) */
CREATE TABLE IF NOT EXISTS zone_permission_requirements (
  id INT AUTO_INCREMENT PRIMARY KEY,
  zone_id INT NOT NULL,
  permission_id INT NOT NULL,
  required BOOLEAN NOT NULL DEFAULT TRUE,
  notes VARCHAR(255) NULL,
  CONSTRAINT fk_zpr_zone FOREIGN KEY (zone_id) REFERENCES restricted_zones(id) ON DELETE CASCADE,
  CONSTRAINT fk_zpr_permission FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE,
  UNIQUE KEY uk_zone_perm (zone_id, permission_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;











-- tuplas zone_permission_requirements
-- ------------------------------------------------------------
-- Procedimiento: seed_zone_permission_requirements
-- Inserta/actualiza reglas que mapean zonas a permisos (zone_permission_requirements)
-- Requisitos: tablas restricted_zones y permissions deben contener los códigos usados abajo.
-- Uso:
--   1) Ejecutar todo el bloque (cambia DELIMITER si tu cliente lo requiere).
--   2) CALL seed_zone_permission_requirements();
-- ------------------------------------------------------------

DELIMITER $$

DROP PROCEDURE IF EXISTS seed_zone_permission_requirements $$
CREATE PROCEDURE seed_zone_permission_requirements()
BEGIN
  DECLARE missing_msg VARCHAR(255);

  -- Variables para zonas
  DECLARE z_cz_intel INT;
  DECLARE z_cz_control INT;
  DECLARE z_cz_maint INT;
  DECLARE z_cz_logistics INT;
  DECLARE z_cz_visitor INT;
  DECLARE z_cz_eh INT;
  DECLARE z_cz_train INT;
  DECLARE z_cz_hq INT;

  -- Variables para permisos
  DECLARE p_intel_override INT;
  DECLARE p_access_sensitive INT;
  DECLARE p_maintenance INT;
  DECLARE p_vehicle_entry INT;
  DECLARE p_temporary_visit INT;
  DECLARE p_emergency INT;
  DECLARE p_remote_access INT;

  -- Obtener ids de zonas
  SELECT id INTO z_cz_intel     FROM restricted_zones WHERE code = 'CZ-INTEL'     LIMIT 1;
  SELECT id INTO z_cz_control   FROM restricted_zones WHERE code = 'CZ-CONTROL'   LIMIT 1;
  SELECT id INTO z_cz_maint     FROM restricted_zones WHERE code = 'CZ-MAINT'     LIMIT 1;
  SELECT id INTO z_cz_logistics FROM restricted_zones WHERE code = 'CZ-LOGISTICS' LIMIT 1;
  SELECT id INTO z_cz_visitor   FROM restricted_zones WHERE code = 'CZ-VISITOR'   LIMIT 1;
  SELECT id INTO z_cz_eh        FROM restricted_zones WHERE code = 'CZ-EH'        LIMIT 1;
  SELECT id INTO z_cz_train     FROM restricted_zones WHERE code = 'CZ-TRAIN'     LIMIT 1;
  SELECT id INTO z_cz_hq        FROM restricted_zones WHERE code = 'CZ-HQ'        LIMIT 1;

  -- Obtener ids de permisos
  SELECT id INTO p_intel_override FROM permissions WHERE code = 'INTEL_OVERRIDE' LIMIT 1;
  SELECT id INTO p_access_sensitive FROM permissions WHERE code = 'ACCESS_SENSITIVE_SITE' LIMIT 1;
  SELECT id INTO p_maintenance     FROM permissions WHERE code = 'MAINTENANCE_ACCESS' LIMIT 1;
  SELECT id INTO p_vehicle_entry   FROM permissions WHERE code = 'VEHICLE_ENTRY' LIMIT 1;
  SELECT id INTO p_temporary_visit FROM permissions WHERE code = 'TEMPORARY_VISIT' LIMIT 1;
  SELECT id INTO p_emergency       FROM permissions WHERE code = 'EMERGENCY_RESPONSE' LIMIT 1;
  SELECT id INTO p_remote_access   FROM permissions WHERE code = 'REMOTE_ACCESS' LIMIT 1;

  -- Chequeos de existencia: si falta alguno, lanzar error con mensaje claro
  IF z_cz_intel IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta zona CZ-INTEL en restricted_zones'; END IF;
  IF z_cz_control IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta zona CZ-CONTROL en restricted_zones'; END IF;
  IF z_cz_maint IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta zona CZ-MAINT en restricted_zones'; END IF;
  IF z_cz_logistics IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta zona CZ-LOGISTICS en restricted_zones'; END IF;
  IF z_cz_visitor IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta zona CZ-VISITOR en restricted_zones'; END IF;
  IF z_cz_eh IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta zona CZ-EH en restricted_zones'; END IF;
  IF z_cz_train IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta zona CZ-TRAIN en restricted_zones'; END IF;
  IF z_cz_hq IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta zona CZ-HQ en restricted_zones'; END IF;

  IF p_intel_override IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso INTEL_OVERRIDE en permissions'; END IF;
  IF p_access_sensitive IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso ACCESS_SENSITIVE_SITE en permissions'; END IF;
  IF p_maintenance IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso MAINTENANCE_ACCESS en permissions'; END IF;
  IF p_vehicle_entry IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso VEHICLE_ENTRY en permissions'; END IF;
  IF p_temporary_visit IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso TEMPORARY_VISIT en permissions'; END IF;
  IF p_emergency IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso EMERGENCY_RESPONSE en permissions'; END IF;
  IF p_remote_access IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta permiso REMOTE_ACCESS en permissions'; END IF;

  -- Insertar / actualizar mapeos zona ↔ permiso
  START TRANSACTION;

  INSERT INTO zone_permission_requirements (zone_id, permission_id, required, notes)
  VALUES
    (z_cz_intel,     p_intel_override,    TRUE,  'INTEL area: requiere INTEL_OVERRIDE'),
    (z_cz_control,   p_access_sensitive,  TRUE,  'Centro de Control: requiere permiso sensible'),
    (z_cz_maint,     p_maintenance,       TRUE,  'Área Mantenimiento: requiere MAINTENANCE_ACCESS'),
    (z_cz_logistics, p_vehicle_entry,     FALSE, 'Depósito Logístico: vehículo permitido si aplica'),
    (z_cz_visitor,   p_temporary_visit,   TRUE,  'Zona Visitantes: requiere TEMPORARY_VISIT o escolta'),
    (z_cz_eh,        p_emergency,         TRUE,  'Entrada Emergencias: EMERGENCY_RESPONSE permite acceso inmediato'),
    (z_cz_train,     p_temporary_visit,   FALSE, 'Academia: admite permisos temporales pero no siempre obligatorios'),
    (z_cz_hq,        p_access_sensitive,  TRUE,  'Headquarters: acceso sensible y posible requerimiento adicional')
  ON DUPLICATE KEY UPDATE
    required = VALUES(required),
    notes = VALUES(notes);

  COMMIT;

  -- Mostrar resultado: zonas y permisos mapeados
  SELECT z.code AS zone_code, z.name AS zone_name,
         perm.code AS permission_code, perm.name AS permission_name,
         zpr.required, zpr.notes
  FROM zone_permission_requirements zpr
  JOIN restricted_zones z ON zpr.zone_id = z.id
  JOIN permissions perm ON zpr.permission_id = perm.id
  ORDER BY z.code, perm.code;

END $$
DELIMITER ;

-- EJECUCIÓN del procedimiento
CALL seed_zone_permission_requirements();














/* Excepciones / permisos temporales por persona y zona */
CREATE TABLE IF NOT EXISTS special_access_grants (
  id INT AUTO_INCREMENT PRIMARY KEY,
  zone_id INT NOT NULL,
  personnel_id INT NOT NULL,
  granted_by INT NULL,
  granted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NULL,
  reason VARCHAR(255) NULL,
  status ENUM('active','revoked','expired') NOT NULL DEFAULT 'active',
  CONSTRAINT fk_sag_zone FOREIGN KEY (zone_id) REFERENCES restricted_zones(id) ON DELETE CASCADE,
  CONSTRAINT fk_sag_personnel FOREIGN KEY (personnel_id) REFERENCES personnel(id) ON DELETE CASCADE,
  CONSTRAINT fk_sag_granted_by FOREIGN KEY (granted_by) REFERENCES personnel(id) ON DELETE SET NULL,
  INDEX idx_sag_zone_personnel (zone_id, personnel_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;











-- tuplas special_access_grants
-- ------------------------------------------------------------
-- Procedimiento: seed_special_access_grants
-- Genera concesiones temporales en special_access_grants para un porcentaje del personal.
-- Requisitos previos: tablas personnel, restricted_zones, special_access_grants, ranks existan.
-- Uso: CALL seed_special_access_grants(0.02); -- 2% del personal activo
-- ------------------------------------------------------------

DELIMITER $$

DROP PROCEDURE IF EXISTS seed_special_access_grants $$
CREATE PROCEDURE seed_special_access_grants(IN p_percent DOUBLE)
main_block: BEGIN

  DECLARE v_total INT DEFAULT 0;
  DECLARE v_target INT DEFAULT 0;
  DECLARE v_inserted INT DEFAULT 0;
  DECLARE v_attempts INT DEFAULT 0;
  DECLARE v_max_attempts INT DEFAULT 10000;

  DECLARE v_pid INT;
  DECLARE v_zone_id INT;
  DECLARE v_exists INT;
  DECLARE v_granted_by INT;
  DECLARE v_person_rank_level INT;
  DECLARE v_rand DOUBLE;
  DECLARE v_expires DATETIME;
  DECLARE v_reason VARCHAR(255);

  /* ---------------- VALIDACIONES ---------------- */

  IF (SELECT COUNT(*) FROM personnel WHERE status = 'active') = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'No hay personnel activo para otorgar grants.';
  END IF;

  IF (SELECT COUNT(*) FROM restricted_zones) = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'No hay restricted_zones para asignar grants.';
  END IF;

  /* ---------------- CÁLCULO OBJETIVO ---------------- */

  SELECT COUNT(*) INTO v_total
  FROM personnel
  WHERE status = 'active';

  SET v_target = CEIL(v_total * p_percent);

  IF v_target <= 0 THEN
    SELECT CONCAT(
      'Nada que hacer: total=', v_total,
      ', percent=', p_percent
    ) AS info;
    LEAVE main_block;
  END IF;

  /* ---------------- INSERCIONES ---------------- */

  START TRANSACTION;

  simple_loop: WHILE v_inserted < v_target
               AND v_attempts < v_max_attempts DO

    SET v_attempts = v_attempts + 1;

    /* Personnel activo aleatorio */
    SELECT id INTO v_pid
    FROM personnel
    WHERE status = 'active'
    ORDER BY RAND()
    LIMIT 1;

    IF v_pid IS NULL THEN
      LEAVE simple_loop;
    END IF;

    /* Zona preferente con permiso especial */
    SELECT id INTO v_zone_id
    FROM restricted_zones
    WHERE requires_special_permission = TRUE
    ORDER BY RAND()
    LIMIT 1;

    IF v_zone_id IS NULL THEN
      SELECT id INTO v_zone_id
      FROM restricted_zones
      ORDER BY RAND()
      LIMIT 1;
    END IF;

    IF v_zone_id IS NULL THEN
      LEAVE simple_loop;
    END IF;

    /* Evitar duplicados activos */
    SELECT id INTO v_exists
    FROM special_access_grants
    WHERE personnel_id = v_pid
      AND zone_id = v_zone_id
      AND status = 'active'
    LIMIT 1;

    IF v_exists IS NOT NULL THEN
      ITERATE simple_loop;
    END IF;

    /* Nivel de rango */
    SELECT COALESCE(r.level, 0)
    INTO v_person_rank_level
    FROM personnel p
    LEFT JOIN ranks r ON p.rank_id = r.id
    WHERE p.id = v_pid
    LIMIT 1;

    /* granted_by: rango superior */
    SELECT p2.id INTO v_granted_by
    FROM personnel p2
    JOIN ranks r2 ON p2.rank_id = r2.id
    WHERE r2.level >= v_person_rank_level + 2
    ORDER BY RAND()
    LIMIT 1;

    /* Fallback */
    IF v_granted_by IS NULL THEN
      SELECT p2.id INTO v_granted_by
      FROM personnel p2
      JOIN ranks r2 ON p2.rank_id = r2.id
      WHERE r2.level >= 8
      ORDER BY RAND()
      LIMIT 1;
    END IF;

    /* Expiración */
    SET v_rand = RAND();

    IF v_rand < 0.6 THEN
      SET v_expires = DATE_ADD(
        NOW(),
        INTERVAL (FLOOR(RAND()*71) + 2) HOUR
      );
    ELSE
      SET v_expires = DATE_ADD(
        NOW(),
        INTERVAL (FLOOR(RAND()*14) + 1) DAY
      );
    END IF;

    SET v_reason = CONCAT(
      'auto_grant_pct_', ROUND(p_percent * 100, 2)
    );

    /* INSERT */
    INSERT INTO special_access_grants
      (zone_id, personnel_id, granted_by,
       granted_at, expires_at, reason, status)
    VALUES
      (v_zone_id, v_pid, v_granted_by,
       NOW(), v_expires, v_reason, 'active');

    SET v_inserted = v_inserted + 1;

  END WHILE simple_loop;

  COMMIT;

  /* ---------------- RESULTADOS ---------------- */

  SELECT CONCAT(
    'target=', v_target,
    ', inserted=', v_inserted,
    ', attempts=', v_attempts
  ) AS summary;

END $$
DELIMITER ;


-- EJEMPLO de ejecución: otorgar concesiones al 2% del personal activo
CALL seed_special_access_grants(0.02);

-- Verificación general
SELECT sag.id, rz.code AS zone_code, p.service_number, p.first_name, p.last_name,
       sag.granted_at, sag.expires_at, sag.status, sag.reason
FROM special_access_grants sag
JOIN personnel p ON sag.personnel_id = p.id
LEFT JOIN restricted_zones rz ON sag.zone_id = rz.id
ORDER BY sag.granted_at DESC
LIMIT 200;













/* Badges físicos / historial (opcional) */
CREATE TABLE IF NOT EXISTS badges (
  id INT AUTO_INCREMENT PRIMARY KEY,
  badge_code VARCHAR(64) NOT NULL UNIQUE,
  personnel_id INT NULL,
  issued_at DATETIME NULL,
  revoked_at DATETIME NULL,
  status ENUM('issued','revoked','lost') NOT NULL DEFAULT 'issued',
  CONSTRAINT fk_badge_personnel FOREIGN KEY (personnel_id) REFERENCES personnel(id) ON DELETE SET NULL,
  INDEX idx_badge_personnel (personnel_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;











-- tuplas badges
-- ================================================================
-- Script único: sincronizar / rellenar badges desde personnel
-- - Inserta en badges los badge_code que ya existen en personnel.
-- - Crea nuevos badges para personnel sin badge_id.
-- - Resuelve duplicados en badges.personnel_id manteniendo el más reciente.
-- - Sincroniza personnel.badge_id con badges.badge_code.
-- ================================================================

START TRANSACTION;

-- -------------------------
-- 0) Seguridad: verificar existencia mínima de tablas
-- -------------------------
-- (Si alguna de estas queries falla, corrige esquema antes de continuar)
SELECT
  (SELECT COUNT(*) FROM information_schema.tables
     WHERE table_schema = DATABASE() AND table_name = 'personnel') AS has_personnel,
  (SELECT COUNT(*) FROM information_schema.tables
     WHERE table_schema = DATABASE() AND table_name = 'badges') AS has_badges\G

-- -------------------------
-- 1) Resolver duplicados: si un mismo personnel_id aparece en >1 badges,
--    mantenemos el badge más reciente (max issued_at) y desvinculamos los demás.
-- -------------------------
DROP TEMPORARY TABLE IF EXISTS tmp_badge_to_unlink;
CREATE TEMPORARY TABLE tmp_badge_to_unlink AS
SELECT b.id AS badge_id
FROM badges b
JOIN (
  SELECT personnel_id, MAX(issued_at) AS max_issued
  FROM badges
  WHERE personnel_id IS NOT NULL
  GROUP BY personnel_id
  HAVING COUNT(*) > 1
) t ON b.personnel_id = t.personnel_id
WHERE b.issued_at <> t.max_issued;

-- Desvincular y marcar como 'revoked' (mantener histórico)
UPDATE badges b
JOIN tmp_badge_to_unlink t ON b.id = t.badge_id
SET b.personnel_id = NULL,
    b.revoked_at = COALESCE(b.revoked_at, NOW()),
    b.status = 'revoked';

DROP TEMPORARY TABLE IF EXISTS tmp_badge_to_unlink;

-- -------------------------
-- 2) INSERTAR badges que faltan cuando personnel ya tiene badge_id
--    (personnel.badge_id no vacío pero no existe en badges)
-- -------------------------
INSERT INTO badges (badge_code, personnel_id, issued_at, status)
SELECT p.badge_id, p.id, NOW(), 'issued'
FROM personnel p
LEFT JOIN badges b ON b.badge_code = p.badge_id
WHERE COALESCE(p.badge_id,'') <> ''
  AND b.id IS NULL;

-- número insertados en paso 2
SET @inserted_from_personnel_codes = ROW_COUNT();

-- -------------------------
-- 3) CREAR badges para personnel que NO tienen badge_id y tampoco tienen badge en badges
--    (generamos badge_code con UUID_SHORT para unicidad práctica)
-- -------------------------
INSERT INTO badges (badge_code, personnel_id, issued_at, status)
SELECT CONCAT('B-', UUID_SHORT()), p.id, NOW(), 'issued'
FROM personnel p
LEFT JOIN badges b ON b.personnel_id = p.id
WHERE (COALESCE(p.badge_id,'') = '' OR p.badge_id IS NULL)
  AND b.id IS NULL;

-- número insertados en paso 3
SET @inserted_new_badges_for_unassigned = ROW_COUNT();

-- -------------------------
-- 4) Sincronizar personnel.badge_id con badges.badge_code (poner valores correctos)
--    - Si personnel.badge_id está vacío pero existe badges.personnel_id -> actualizar.
--    - Si personnel.badge_id difiere del badge existente -> sincronizar.
-- -------------------------
UPDATE personnel p
JOIN badges b ON b.personnel_id = p.id
SET p.badge_id = b.badge_code,
    p.updated_at = NOW()
WHERE COALESCE(p.badge_id,'') <> b.badge_code;

SET @updated_personnel = ROW_COUNT();

-- -------------------------
-- 5) (Opcional) Insertar en badges los badge_code que estaban en personnel pero con
--    personnel_id apuntando a otra fila en badges (caso raro). Sincronizamos esos también.
-- -------------------------
-- Si existe un badge con badge_code = p.badge_id but personnel_id IS NULL then attach it
UPDATE badges b
JOIN personnel p ON b.badge_code = p.badge_id
SET b.personnel_id = p.id
WHERE b.personnel_id IS NULL;

SET @attached_or_relinked_badges = ROW_COUNT();

-- -------------------------
-- 6) Resumen: mostrar conteos y comprobaciones
-- -------------------------
COMMIT;

-- Mostrar resumen legible
SELECT
  @inserted_from_personnel_codes  AS inserted_from_existing_personnel_badgecodes,
  @inserted_new_badges_for_unassigned AS inserted_new_badges_for_personnel_without_badgeid,
  @updated_personnel AS personnel_rows_updated_with_badgeid,
  @attached_or_relinked_badges AS badges_attached_to_personnel_by_code;

-- Comprobaciones finales útiles
-- a) ¿Quedan personas sin badge_id?
SELECT COUNT(*) AS personnel_without_badge_id
FROM personnel
WHERE COALESCE(badge_id,'') = '';

-- b) ¿Cuántos badges totales?
SELECT COUNT(*) AS total_badges FROM badges;

-- c)listar algunos badges recientes para inspección
SELECT id, badge_code, personnel_id, issued_at, revoked_at, status
FROM badges
ORDER BY issued_at DESC
LIMIT 100;












-- /* Historial de cambios en políticas/reglas (opcional, útil para auditoría) */
-- CREATE TABLE IF NOT EXISTS audit_policy_changes (
--   id INT AUTO_INCREMENT PRIMARY KEY,
--   changed_by INT NULL,                -- quién hizo el cambio (personnel.id)
--   changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
--   entity VARCHAR(64) NOT NULL,        -- p.ej. 'restricted_zones'
--   entity_id INT NULL,
--   action VARCHAR(32) NOT NULL,        -- 'create'|'update'|'delete'
--   diff TEXT NULL,                     -- JSON con cambios (guardar como texto)
--   CONSTRAINT fk_audit_changed_by FOREIGN KEY (changed_by) REFERENCES personnel(id) ON DELETE SET NULL,
--   INDEX idx_audit_entity (entity, entity_id)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -- Índices adicionales recomendados (si los quieres crear explícitamente):
-- CREATE INDEX IF NOT EXISTS idx_person_service_number ON personnel (service_number);
-- CREATE INDEX IF NOT EXISTS idx_person_badge_id ON personnel (badge_id);
-- CREATE INDEX IF NOT EXISTS idx_pp_personnel_id ON personnel_permissions (personnel_id);
-- CREATE INDEX IF NOT EXISTS idx_pp_permission_id ON personnel_permissions (permission_id);
-- CREATE INDEX IF NOT EXISTS idx_zone_active ON restricted_zones (active);

-- -- FIN del esquema
