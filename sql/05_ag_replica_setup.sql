-- =============================================================================
-- 05_ag_replica_setup.sql
-- Validates or creates the DMS login with the primary replica SID, then reuses
-- the canonical modular setup on an Always On Availability Group replica.
--
-- IMPORTANT: Run this command from the repository root so the :r paths resolve:
--   sqlcmd -S <replica-server> -i sql/05_ag_replica_setup.sql \
--     -v DMS_USER="dmsnosysadmin" DMS_PASSWORD="<endpoint-password>" \
--        PRIMARY_SID="0x..." CERT_PASSWORD="<certificate-password>" \
--        DB_NAME="<source-database>" \
--        REPLDATA_DIR="C:\\Program Files\\Microsoft SQL Server\\MSSQL\\ReplData"
-- =============================================================================

USE master;
GO

DECLARE @dms_user SYSNAME = N'$(DMS_USER)';
DECLARE @dms_password NVARCHAR(128) = N'$(DMS_PASSWORD)';
DECLARE @expected_sid VARBINARY(85) = CONVERT(VARBINARY(85), '$(PRIMARY_SID)', 1);
DECLARE @current_sid VARBINARY(85);
DECLARE @sql NVARCHAR(MAX);

IF NULLIF(@dms_password, N'') IS NULL
    THROW 51030, 'Set DMS_PASSWORD before running this script.', 1;

IF @expected_sid IS NULL
    THROW 51031, 'Set PRIMARY_SID to the hexadecimal SID from the primary replica.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @dms_user)
BEGIN
    SET @sql = N'CREATE LOGIN ' + QUOTENAME(@dms_user)
      + N' WITH PASSWORD = N''' + REPLACE(@dms_password, N'''', N'''''')
      + N''', SID = ' + CONVERT(NVARCHAR(200), @expected_sid, 1)
      + N', CHECK_POLICY = ON;';
    EXEC sys.sp_executesql @sql;
END

SELECT @current_sid = sid FROM sys.server_principals WHERE name = @dms_user;
IF @current_sid <> @expected_sid
    THROW 51032, 'The DMS login SID does not match the primary replica SID.', 1;

PRINT 'DMS login SID matches the primary replica.';
GO

-- Configure this replica as a distributor. Publication and articles exist only
-- on the primary and are configured by running script 00 there with
-- CREATE_PUBLICATION=1.
:setvar CREATE_PUBLICATION "0"
USE [$(DB_NAME)];
GO
:r sql/00_configure_replication.sql
USE master;
GO

:r sql/01_create_schema_and_functions.sql
:r sql/02_create_stored_procedures.sql
:r sql/03_create_certificates_and_sign.sql
:r sql/04_grant_permissions.sql

PRINT '05 - AG replica setup completed with the canonical objects and grants.';
GO
