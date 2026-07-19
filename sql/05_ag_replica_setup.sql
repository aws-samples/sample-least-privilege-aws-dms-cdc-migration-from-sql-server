-- =============================================================================
-- 05_ag_replica_setup.sql
-- Always On AG: Creates the DMS login with matching SID, certificates,
-- certificate-based logins, and signs procedures on a secondary replica.
--
-- Run this script on EACH AG replica independently.
--
-- Usage:
--   sqlcmd -S <replica-server> -i 05_ag_replica_setup.sql \
--     -v DMS_USER="dmsnosysadmin" \
--        DMS_PASSWORD="<password>" \
--        PRIMARY_SID="<hex-sid-from-primary>" \
--        CERT_PASSWORD_1="<cert-password-1>" \
--        CERT_PASSWORD_2="<cert-password-2>"
--
-- To get PRIMARY_SID, run on the primary:
--   SELECT CONVERT(VARCHAR(100), sid, 1) FROM sys.server_principals
--   WHERE name = 'dmsnosysadmin';
-- =============================================================================

USE master;
GO

-- Step 1: Create login with matching SID (skip if exists)
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$(DMS_USER)')
BEGIN
    CREATE LOGIN [$(DMS_USER)]
        WITH PASSWORD = '$(DMS_PASSWORD)',
             SID = $(PRIMARY_SID),
             CHECK_POLICY = OFF;
    PRINT 'Login $(DMS_USER) created with matching SID.';
END
ELSE
BEGIN
    -- Verify SID matches
    DECLARE @current_sid VARBINARY(85);
    SELECT @current_sid = sid FROM sys.server_principals
    WHERE name = '$(DMS_USER)';

    PRINT 'Login $(DMS_USER) already exists.';
    PRINT 'Current SID: ' + CONVERT(VARCHAR(200), @current_sid, 1);
    PRINT 'Verify this matches the primary replica SID: $(PRIMARY_SID)';
END
GO

-- Step 2: Create schema and functions (same as script 01)
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'awsdms')
BEGIN
    EXEC('CREATE SCHEMA [awsdms] AUTHORIZATION [dbo]');
END
GO

IF OBJECT_ID('awsdms.rtm_heartbeat_function', 'FN') IS NOT NULL
    DROP FUNCTION awsdms.rtm_heartbeat_function;
GO

CREATE FUNCTION awsdms.rtm_heartbeat_function()
RETURNS DATETIME
AS
BEGIN
    RETURN GETUTCDATE();
END
GO

-- Step 3: Create stored procedures (same as script 02)
IF OBJECT_ID('awsdms.rtm_dump_dblog', 'P') IS NOT NULL
    DROP PROCEDURE awsdms.rtm_dump_dblog;
GO

IF OBJECT_ID('awsdms.rtm_position_1st_timestamp', 'P') IS NOT NULL
    DROP PROCEDURE awsdms.rtm_position_1st_timestamp;
GO

CREATE PROCEDURE awsdms.rtm_dump_dblog
    @start_lsn VARCHAR(32) = NULL, @end_lsn VARCHAR(32) = NULL,
    @device_type VARCHAR(260) = 'DISK',
    @file_name_1 VARCHAR(260)=NULL, @file_name_2 VARCHAR(260)=NULL,
    @file_name_3 VARCHAR(260)=NULL, @file_name_4 VARCHAR(260)=NULL,
    @file_name_5 VARCHAR(260)=NULL, @file_name_6 VARCHAR(260)=NULL,
    @file_name_7 VARCHAR(260)=NULL, @file_name_8 VARCHAR(260)=NULL,
    @file_name_9 VARCHAR(260)=NULL, @file_name_10 VARCHAR(260)=NULL,
    @file_name_11 VARCHAR(260)=NULL, @file_name_12 VARCHAR(260)=NULL,
    @file_name_13 VARCHAR(260)=NULL, @file_name_14 VARCHAR(260)=NULL,
    @file_name_15 VARCHAR(260)=NULL, @file_name_16 VARCHAR(260)=NULL,
    @file_name_17 VARCHAR(260)=NULL, @file_name_18 VARCHAR(260)=NULL,
    @file_name_19 VARCHAR(260)=NULL, @file_name_20 VARCHAR(260)=NULL,
    @file_name_21 VARCHAR(260)=NULL, @file_name_22 VARCHAR(260)=NULL,
    @file_name_23 VARCHAR(260)=NULL, @file_name_24 VARCHAR(260)=NULL,
    @file_name_25 VARCHAR(260)=NULL, @file_name_26 VARCHAR(260)=NULL,
    @file_name_27 VARCHAR(260)=NULL, @file_name_28 VARCHAR(260)=NULL,
    @file_name_29 VARCHAR(260)=NULL, @file_name_30 VARCHAR(260)=NULL,
    @file_name_31 VARCHAR(260)=NULL, @file_name_32 VARCHAR(260)=NULL,
    @file_name_33 VARCHAR(260)=NULL, @file_name_34 VARCHAR(260)=NULL,
    @file_name_35 VARCHAR(260)=NULL, @file_name_36 VARCHAR(260)=NULL,
    @file_name_37 VARCHAR(260)=NULL, @file_name_38 VARCHAR(260)=NULL,
    @file_name_39 VARCHAR(260)=NULL, @file_name_40 VARCHAR(260)=NULL,
    @file_name_41 VARCHAR(260)=NULL, @file_name_42 VARCHAR(260)=NULL,
    @file_name_43 VARCHAR(260)=NULL, @file_name_44 VARCHAR(260)=NULL,
    @file_name_45 VARCHAR(260)=NULL, @file_name_46 VARCHAR(260)=NULL,
    @file_name_47 VARCHAR(260)=NULL, @file_name_48 VARCHAR(260)=NULL,
    @file_name_49 VARCHAR(260)=NULL, @file_name_50 VARCHAR(260)=NULL,
    @file_name_51 VARCHAR(260)=NULL, @file_name_52 VARCHAR(260)=NULL,
    @file_name_53 VARCHAR(260)=NULL, @file_name_54 VARCHAR(260)=NULL,
    @file_name_55 VARCHAR(260)=NULL, @file_name_56 VARCHAR(260)=NULL,
    @file_name_57 VARCHAR(260)=NULL, @file_name_58 VARCHAR(260)=NULL,
    @file_name_59 VARCHAR(260)=NULL, @file_name_60 VARCHAR(260)=NULL,
    @file_name_61 VARCHAR(260)=NULL, @file_name_62 VARCHAR(260)=NULL,
    @file_name_63 VARCHAR(260)=NULL, @file_name_64 VARCHAR(260)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM fn_dump_dblog(
        @start_lsn, @end_lsn, @device_type,
        @file_name_1, @file_name_2, @file_name_3, @file_name_4,
        @file_name_5, @file_name_6, @file_name_7, @file_name_8,
        @file_name_9, @file_name_10, @file_name_11, @file_name_12,
        @file_name_13, @file_name_14, @file_name_15, @file_name_16,
        @file_name_17, @file_name_18, @file_name_19, @file_name_20,
        @file_name_21, @file_name_22, @file_name_23, @file_name_24,
        @file_name_25, @file_name_26, @file_name_27, @file_name_28,
        @file_name_29, @file_name_30, @file_name_31, @file_name_32,
        @file_name_33, @file_name_34, @file_name_35, @file_name_36,
        @file_name_37, @file_name_38, @file_name_39, @file_name_40,
        @file_name_41, @file_name_42, @file_name_43, @file_name_44,
        @file_name_45, @file_name_46, @file_name_47, @file_name_48,
        @file_name_49, @file_name_50, @file_name_51, @file_name_52,
        @file_name_53, @file_name_54, @file_name_55, @file_name_56,
        @file_name_57, @file_name_58, @file_name_59, @file_name_60,
        @file_name_61, @file_name_62, @file_name_63, @file_name_64
    );
END
GO

CREATE PROCEDURE awsdms.rtm_position_1st_timestamp
    @db_name SYSNAME, @timestamp DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    SELECT fn_position_1st_timestamp(@db_name, @timestamp);
END
GO

-- Step 4: Create certificates and sign (same as script 03)
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'cert_rtm_dump_dblog')
BEGIN
    EXEC('DROP SIGNATURE FROM awsdms.rtm_dump_dblog BY CERTIFICATE cert_rtm_dump_dblog');
    IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_cert_rtm_dump_dblog')
    BEGIN
        EXEC sp_dropsrvrolemember 'login_cert_rtm_dump_dblog', 'sysadmin';
        DROP LOGIN login_cert_rtm_dump_dblog;
    END
    DROP CERTIFICATE cert_rtm_dump_dblog;
END
GO

CREATE CERTIFICATE cert_rtm_dump_dblog
    ENCRYPTION BY PASSWORD = '$(CERT_PASSWORD_1)'
    WITH SUBJECT = 'Certificate for signing awsdms.rtm_dump_dblog';
GO
CREATE LOGIN login_cert_rtm_dump_dblog FROM CERTIFICATE cert_rtm_dump_dblog;
GO
ALTER SERVER ROLE sysadmin ADD MEMBER login_cert_rtm_dump_dblog;
GO
ADD SIGNATURE TO awsdms.rtm_dump_dblog
    BY CERTIFICATE cert_rtm_dump_dblog WITH PASSWORD = '$(CERT_PASSWORD_1)';
GO

IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'cert_rtm_position')
BEGIN
    EXEC('DROP SIGNATURE FROM awsdms.rtm_position_1st_timestamp BY CERTIFICATE cert_rtm_position');
    IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_cert_rtm_position')
    BEGIN
        EXEC sp_dropsrvrolemember 'login_cert_rtm_position', 'sysadmin';
        DROP LOGIN login_cert_rtm_position;
    END
    DROP CERTIFICATE cert_rtm_position;
END
GO

CREATE CERTIFICATE cert_rtm_position
    ENCRYPTION BY PASSWORD = '$(CERT_PASSWORD_2)'
    WITH SUBJECT = 'Certificate for signing awsdms.rtm_position_1st_timestamp';
GO
CREATE LOGIN login_cert_rtm_position FROM CERTIFICATE cert_rtm_position;
GO
ALTER SERVER ROLE sysadmin ADD MEMBER login_cert_rtm_position;
GO
ADD SIGNATURE TO awsdms.rtm_position_1st_timestamp
    BY CERTIFICATE cert_rtm_position WITH PASSWORD = '$(CERT_PASSWORD_2)';
GO

-- Step 5: Grant permissions
GRANT VIEW SERVER STATE TO [$(DMS_USER)];
GRANT VIEW ANY DEFINITION TO [$(DMS_USER)];
GRANT SELECT ON awsdms.rtm_heartbeat_function TO [$(DMS_USER)];
GRANT EXECUTE ON awsdms.rtm_dump_dblog TO [$(DMS_USER)];
GRANT EXECUTE ON awsdms.rtm_position_1st_timestamp TO [$(DMS_USER)];
GO

-- Verify
SELECT
    OBJECT_NAME(cp.major_id) AS signed_procedure,
    c.name AS certificate_name
FROM sys.crypt_properties cp
JOIN sys.certificates c ON cp.thumbprint = c.thumbprint
WHERE cp.major_id IN (
    OBJECT_ID('awsdms.rtm_dump_dblog'),
    OBJECT_ID('awsdms.rtm_position_1st_timestamp')
);
GO

PRINT '05 - AG replica setup completed successfully.';
GO
