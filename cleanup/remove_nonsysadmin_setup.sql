-- =============================================================================
-- remove_nonsysadmin_setup.sql
-- Removes all non-sysadmin DMS objects from SQL Server.
-- Run on each replica independently for AG environments.
--
-- Usage:
--   sqlcmd -S <server> -i remove_nonsysadmin_setup.sql -v DMS_USER="dmsnosysadmin"
-- =============================================================================

USE master;
GO

PRINT 'Starting cleanup of DMS non-sysadmin objects...';
GO

-- 1. Drop certificate signatures
IF EXISTS (
    SELECT 1 FROM sys.crypt_properties cp
    JOIN sys.certificates c ON cp.thumbprint = c.thumbprint
    WHERE c.name = 'cert_rtm_dump_dblog'
      AND cp.major_id = OBJECT_ID('awsdms.rtm_dump_dblog')
)
BEGIN
    DROP SIGNATURE FROM awsdms.rtm_dump_dblog BY CERTIFICATE cert_rtm_dump_dblog;
    PRINT 'Dropped signature from rtm_dump_dblog.';
END
GO

IF EXISTS (
    SELECT 1 FROM sys.crypt_properties cp
    JOIN sys.certificates c ON cp.thumbprint = c.thumbprint
    WHERE c.name = 'cert_rtm_position'
      AND cp.major_id = OBJECT_ID('awsdms.rtm_position_1st_timestamp')
)
BEGIN
    DROP SIGNATURE FROM awsdms.rtm_position_1st_timestamp BY CERTIFICATE cert_rtm_position;
    PRINT 'Dropped signature from rtm_position_1st_timestamp.';
END
GO

-- 2. Remove certificate logins from sysadmin and drop them
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_cert_rtm_dump_dblog')
BEGIN
    EXEC sp_dropsrvrolemember 'login_cert_rtm_dump_dblog', 'sysadmin';
    DROP LOGIN login_cert_rtm_dump_dblog;
    PRINT 'Dropped login_cert_rtm_dump_dblog.';
END
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_cert_rtm_position')
BEGIN
    EXEC sp_dropsrvrolemember 'login_cert_rtm_position', 'sysadmin';
    DROP LOGIN login_cert_rtm_position;
    PRINT 'Dropped login_cert_rtm_position.';
END
GO

-- 3. Drop certificates
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'cert_rtm_dump_dblog')
BEGIN
    DROP CERTIFICATE cert_rtm_dump_dblog;
    PRINT 'Dropped cert_rtm_dump_dblog.';
END
GO

IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'cert_rtm_position')
BEGIN
    DROP CERTIFICATE cert_rtm_position;
    PRINT 'Dropped cert_rtm_position.';
END
GO

-- 4. Drop stored procedures
IF OBJECT_ID('awsdms.rtm_dump_dblog', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE awsdms.rtm_dump_dblog;
    PRINT 'Dropped awsdms.rtm_dump_dblog.';
END
GO

IF OBJECT_ID('awsdms.rtm_position_1st_timestamp', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE awsdms.rtm_position_1st_timestamp;
    PRINT 'Dropped awsdms.rtm_position_1st_timestamp.';
END
GO

-- 5. Drop helper function
IF OBJECT_ID('awsdms.rtm_heartbeat_function', 'FN') IS NOT NULL
BEGIN
    DROP FUNCTION awsdms.rtm_heartbeat_function;
    PRINT 'Dropped awsdms.rtm_heartbeat_function.';
END
GO

-- 6. Drop schema
IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'awsdms')
BEGIN
    DROP SCHEMA awsdms;
    PRINT 'Dropped awsdms schema.';
END
GO

-- 7. Optionally drop the DMS login (uncomment if desired)
-- WARNING: This will remove the DMS user entirely.
-- IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$(DMS_USER)')
-- BEGIN
--     DROP LOGIN [$(DMS_USER)];
--     PRINT 'Dropped login $(DMS_USER).';
-- END
-- GO

PRINT 'Cleanup complete.';
GO
