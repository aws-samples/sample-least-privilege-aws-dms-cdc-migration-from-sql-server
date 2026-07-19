-- =============================================================================
-- 03_create_certificates_and_sign.sql
-- Creates certificates, certificate-based logins, adds them to sysadmin,
-- and signs the wrapper stored procedures.
--
-- IMPORTANT: Certificate passwords must NOT be hardcoded. Retrieve them
-- from AWS Secrets Manager and pass via SQLCMD variables.
--
-- Usage:
--   sqlcmd -S <server> -i 03_create_certificates_and_sign.sql \
--     -v CERT_PASSWORD_1="<password-from-secrets-manager>" \
--        CERT_PASSWORD_2="<password-from-secrets-manager>"
--
-- SQLCMD Variables:
--   CERT_PASSWORD_1 - Encryption password for rtm_dump_dblog certificate
--   CERT_PASSWORD_2 - Encryption password for rtm_position certificate
-- =============================================================================

USE master;
GO

-- ---- Certificate for rtm_dump_dblog ----

-- Drop existing objects if they exist (idempotent)
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'cert_rtm_dump_dblog')
BEGIN
    -- Remove signature first
    IF EXISTS (
        SELECT 1 FROM sys.crypt_properties cp
        JOIN sys.certificates c ON cp.thumbprint = c.thumbprint
        WHERE c.name = 'cert_rtm_dump_dblog'
          AND cp.major_id = OBJECT_ID('awsdms.rtm_dump_dblog')
    )
    BEGIN
        EXEC('DROP SIGNATURE FROM awsdms.rtm_dump_dblog BY CERTIFICATE cert_rtm_dump_dblog');
    END

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
    BY CERTIFICATE cert_rtm_dump_dblog
    WITH PASSWORD = '$(CERT_PASSWORD_1)';
GO

-- ---- Certificate for rtm_position_1st_timestamp ----

IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'cert_rtm_position')
BEGIN
    IF EXISTS (
        SELECT 1 FROM sys.crypt_properties cp
        JOIN sys.certificates c ON cp.thumbprint = c.thumbprint
        WHERE c.name = 'cert_rtm_position'
          AND cp.major_id = OBJECT_ID('awsdms.rtm_position_1st_timestamp')
    )
    BEGIN
        EXEC('DROP SIGNATURE FROM awsdms.rtm_position_1st_timestamp BY CERTIFICATE cert_rtm_position');
    END

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
    BY CERTIFICATE cert_rtm_position
    WITH PASSWORD = '$(CERT_PASSWORD_2)';
GO

-- ---- Verify signatures ----
SELECT
    OBJECT_NAME(cp.major_id) AS signed_procedure,
    c.name AS certificate_name,
    cp.crypt_type_desc
FROM sys.crypt_properties cp
JOIN sys.certificates c ON cp.thumbprint = c.thumbprint
WHERE cp.major_id IN (
    OBJECT_ID('awsdms.rtm_dump_dblog'),
    OBJECT_ID('awsdms.rtm_position_1st_timestamp')
);
GO

PRINT '03 - Certificates created and procedures signed successfully.';
GO
