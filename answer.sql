-- ============================================================
-- DATABASE ENGINEERING LAB
-- Complete PostgreSQL Setup
-- ============================================================
---------------------------------------------------------------

-- Includes:
-- 1. Students table
-- 2. Audit logging with JSONB
-- 3. Audit trigger for INSERT, UPDATE, DELETE
-- 4. Category hierarchy
-- 5. Recursive CTE
-- 6. Least-privilege roles
-- ============================================================

-- ============================================================
-- STEP 1: CORE STUDENTS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS students (
id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
name TEXT NOT NULL,
email TEXT UNIQUE,
enrolled_on DATE
);

-- ============================================================
-- STEP 2: AUDIT LOG TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS audit_log (
id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
tbl TEXT NOT NULL,
op TEXT NOT NULL,
old_row JSONB,
new_row JSONB,
changed_by TEXT NOT NULL DEFAULT current_user,
at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- STEP 3: AUDIT FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

```
INSERT INTO audit_log (
    tbl,
    op,
    old_row,
    new_row
)
VALUES (
    TG_TABLE_NAME,
    TG_OP,

    CASE
        WHEN TG_OP IN ('UPDATE', 'DELETE')
        THEN to_jsonb(OLD)
        ELSE NULL
    END,

    CASE
        WHEN TG_OP IN ('INSERT', 'UPDATE')
        THEN to_jsonb(NEW)
        ELSE NULL
    END
);

RETURN COALESCE(NEW, OLD);
```

END;

$$$;


-- ============================================================
-- STEP 4: AUDIT TRIGGER
-- ============================================================

DROP TRIGGER IF EXISTS trg_audit ON students;

CREATE TRIGGER trg_audit
AFTER INSERT OR UPDATE OR DELETE
ON students
FOR EACH ROW
EXECUTE FUNCTION audit();


-- ============================================================
-- STEP 5: INSERT TEST STUDENTS
-- ============================================================

INSERT INTO students (name, email, enrolled_on)
VALUES
    ('Kofi Mensah', 'kofi@example.com', CURRENT_DATE),
    ('Ama Boateng', 'ama@example.com', CURRENT_DATE),
    ('Yaw Asante', 'yaw@example.com', CURRENT_DATE)
ON CONFLICT (email) DO NOTHING;


-- ============================================================
-- STEP 6: TEST UPDATE
-- ============================================================

UPDATE students
SET name = 'Kofi M.'
WHERE email = 'kofi@example.com';


-- ============================================================
-- STEP 7: TEST DELETE
-- ============================================================

DELETE FROM students
WHERE email = 'yaw@example.com';


-- ============================================================
-- STEP 8: VIEW AUDIT LOG
-- ============================================================

SELECT
    tbl,
    op,
    old_row->>'name' AS was,
    new_row->>'name' AS now,
    changed_by,
    at
FROM audit_log
ORDER BY at DESC;


-- ============================================================
-- STEP 9: CATEGORY TREE
-- ============================================================

CREATE TABLE IF NOT EXISTS categories (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id BIGINT REFERENCES categories(id)
);


-- ============================================================
-- STEP 10: INSERT CATEGORY DATA
-- ============================================================

INSERT INTO categories (name, parent_id)
SELECT 'Electronics', NULL
WHERE NOT EXISTS (
    SELECT 1
    FROM categories
    WHERE name = 'Electronics'
      AND parent_id IS NULL
);


INSERT INTO categories (name, parent_id)
SELECT 'Computers', id
FROM categories
WHERE name = 'Electronics'
  AND parent_id IS NULL
  AND NOT EXISTS (
      SELECT 1
      FROM categories
      WHERE name = 'Computers'
  )
LIMIT 1;


INSERT INTO categories (name, parent_id)
SELECT 'Phones', id
FROM categories
WHERE name = 'Electronics'
  AND parent_id IS NULL
  AND NOT EXISTS (
      SELECT 1
      FROM categories
      WHERE name = 'Phones'
  )
LIMIT 1;


INSERT INTO categories (name, parent_id)
SELECT 'Laptops', id
FROM categories
WHERE name = 'Computers'
  AND NOT EXISTS (
      SELECT 1
      FROM categories
      WHERE name = 'Laptops'
  )
LIMIT 1;


-- ============================================================
-- STEP 11: RECURSIVE CATEGORY TREE
-- ============================================================

WITH RECURSIVE tree AS (

    -- Root categories
    SELECT
        id,
        name,
        parent_id,
        0 AS depth
    FROM categories
    WHERE parent_id IS NULL

    UNION ALL

    -- Child categories
    SELECT
        c.id,
        c.name,
        c.parent_id,
        t.depth + 1
    FROM categories c
    JOIN tree t
        ON c.parent_id = t.id
)

SELECT
    repeat('  ', depth) || name AS tree
FROM tree
ORDER BY depth, name;


-- ============================================================
-- STEP 12: LEAST-PRIVILEGE SECURITY
-- ============================================================

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'app_read'
    ) THEN
        CREATE ROLE app_read;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'app_write'
    ) THEN
        CREATE ROLE app_write;
    END IF;

END
$$;


-- ============================================================
-- STEP 13: DATABASE AND SCHEMA PERMISSIONS
-- ============================================================

GRANT CONNECT ON DATABASE bootcamp
TO app_read, app_write;

GRANT USAGE ON SCHEMA public
TO app_read, app_write;


-- ============================================================
-- STEP 14: READ-ONLY PERMISSIONS
-- ============================================================

GRANT SELECT
ON ALL TABLES IN SCHEMA public
TO app_read;


-- ============================================================
-- STEP 15: READ/WRITE PERMISSIONS
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA public
TO app_write;


-- ============================================================
-- STEP 16: SEQUENCE PERMISSIONS
-- Needed for identity/sequence-backed columns
-- ============================================================

GRANT USAGE, SELECT
ON ALL SEQUENCES IN SCHEMA public
TO app_write;


-- ============================================================
-- STEP 17: CREATE API USER
-- ============================================================

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'api'
    ) THEN

        CREATE ROLE api
        LOGIN
        PASSWORD 'strong-secret';

    END IF;

END
$$;


-- ============================================================
-- STEP 18: ASSIGN WRITE ROLE TO API USER
-- ============================================================

GRANT app_write TO api;


-- ============================================================
-- STEP 19: FINAL STUDENTS CHECK
-- ============================================================

SELECT *
FROM students
ORDER BY id;


-- ============================================================
-- STEP 20: FINAL AUDIT CHECK
-- ============================================================

SELECT
    id,
    tbl,
    op,
    old_row,
    new_row,
    changed_by,
    at
FROM audit_log
ORDER BY at DESC;


-- ============================================================
-- STEP 21: FINAL CATEGORY CHECK
-- ============================================================

SELECT
    id,
    name,
    parent_id
FROM categories
ORDER BY id;


-- ============================================================
-- END OF DATABASE SETUP
-- ============================================================
$$$
