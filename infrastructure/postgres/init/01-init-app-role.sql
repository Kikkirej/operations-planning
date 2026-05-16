-- Bootstrap script for the application PostgreSQL instance.
-- Runs once on first container start (docker-entrypoint-initdb.d mechanism).
-- Services create their own schemas and roles on startup; this script only
-- establishes the shared baseline role and security defaults.

-- Shared login role. All service-specific roles are created as members of this role.
CREATE ROLE app WITH LOGIN NOINHERIT;

-- Remove the default ability for any authenticated user to create objects in public.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- Allow the app role to connect to the application database.
GRANT CONNECT ON DATABASE app_db TO app;
