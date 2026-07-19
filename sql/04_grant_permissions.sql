-- =============================================================================
-- 04_grant_permissions.sql
-- Grants all granular permissions to the DMS user account.
--
-- Usage:
--   sqlcmd -S <server> -i 04_grant_permissions.sql \
--     -v DMS_USER="dmsnosysadmin" DB_NAME="<your-database>"
--
-- SQLCMD Variables:
--   DMS_USER - The DMS login name
--   DB_NAME  - The source database name to replicate
-- =============================================================================

USE master;
GO

-- Create the DMS login if it does not exist
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$(DMS_USER)')
BEGIN
    PRINT 'ERROR: Login $(DMS_USER) does not exist. Create it first.';
    RAISERROR('Login $(DMS_USER) not found.', 16, 1);
    RETURN;
END
GO

-- Server-level permissions
GRANT VIEW SERVER STATE TO [$(DMS_USER)];
GO
GRANT VIEW ANY DEFINITION TO [$(DMS_USER)];
GO

-- master database permissions
GRANT SELECT ON awsdms.rtm_heartbeat_function TO [$(DMS_USER)];
GO
GRANT EXECUTE ON awsdms.rtm_dump_dblog TO [$(DMS_USER)];
GO
GRANT EXECUTE ON awsdms.rtm_position_1st_timestamp TO [$(DMS_USER)];
GO

-- Source database permissions
USE [$(DB_NAME)];
GO

-- Add DMS user as db_owner on the source database
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$(DMS_USER)')
BEGIN
    CREATE USER [$(DMS_USER)] FOR LOGIN [$(DMS_USER)];
END
GO

ALTER ROLE db_owner ADD MEMBER [$(DMS_USER)];
GO

-- msdb permissions (required for CDC position tracking)
USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$(DMS_USER)')
BEGIN
    CREATE USER [$(DMS_USER)] FOR LOGIN [$(DMS_USER)];
END
GO

GRANT SELECT ON dbo.sysjobs TO [$(DMS_USER)];
GO
GRANT SELECT ON dbo.sysjobactivity TO [$(DMS_USER)];
GO

-- Verify: DMS user should NOT be sysadmin
USE master;
GO
SELECT
    '$(DMS_USER)' AS login_name,
    IS_SRVROLEMEMBER('sysadmin', '$(DMS_USER)') AS is_sysadmin;
GO

PRINT '04 - Granular permissions granted successfully.';
GO
