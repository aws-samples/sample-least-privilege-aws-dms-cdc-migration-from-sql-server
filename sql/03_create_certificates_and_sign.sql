-- =============================================================================
-- 03_create_certificates_and_sign.sql
-- Creates canonical certificate-based logins, grants their narrowly activated
-- sysadmin membership, and signs both wrapper procedures.
--
-- Run from the repository root:
--   sqlcmd -S <server> -i sql/03_create_certificates_and_sign.sql \
--     -v CERT_PASSWORD="<password-from-secrets-manager>"
-- =============================================================================

USE master;
GO

DECLARE @certificate_password NVARCHAR(128) = N'$(CERT_PASSWORD)';
IF NULLIF(@certificate_password, N'') IS NULL OR @certificate_password = N'CHANGE_ME'
    THROW 51010, 'Set CERT_PASSWORD to the certificate password retrieved from Secrets Manager.', 1;

IF OBJECT_ID('tempdb..#CertificateConfig') IS NOT NULL DROP TABLE #CertificateConfig;
CREATE TABLE #CertificateConfig (certificate_password NVARCHAR(128) NOT NULL);
INSERT INTO #CertificateConfig VALUES (@certificate_password);
GO

-- Remove prior canonical signing identities before recreating them.
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'awsdms_rtm_dump_dblog_cert')
BEGIN
    IF OBJECT_ID(N'awsdms.rtm_dump_dblog', N'P') IS NOT NULL
       AND EXISTS (
           SELECT 1 FROM sys.crypt_properties AS cp
           JOIN sys.certificates AS c ON c.thumbprint = cp.thumbprint
           WHERE c.name = N'awsdms_rtm_dump_dblog_cert'
             AND cp.major_id = OBJECT_ID(N'awsdms.rtm_dump_dblog')
       )
        DROP SIGNATURE FROM awsdms.rtm_dump_dblog BY CERTIFICATE awsdms_rtm_dump_dblog_cert;
END
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'awsdms_rtm_dump_dblog_login')
BEGIN
    ALTER SERVER ROLE sysadmin DROP MEMBER awsdms_rtm_dump_dblog_login;
    DROP LOGIN awsdms_rtm_dump_dblog_login;
END
GO

IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'awsdms_rtm_dump_dblog_cert')
    DROP CERTIFICATE awsdms_rtm_dump_dblog_cert;
GO

DECLARE @password NVARCHAR(128) = (SELECT certificate_password FROM #CertificateConfig);
DECLARE @quoted_password NVARCHAR(300) = QUOTENAME(@password, '''');
EXEC(N'CREATE CERTIFICATE awsdms_rtm_dump_dblog_cert '
    + N'ENCRYPTION BY PASSWORD = N' + @quoted_password + N' '
    + N'WITH SUBJECT = N''Certificate for FN_DUMP_DBLOG permissions'';');
GO

CREATE LOGIN awsdms_rtm_dump_dblog_login
    FROM CERTIFICATE awsdms_rtm_dump_dblog_cert;
ALTER SERVER ROLE sysadmin ADD MEMBER awsdms_rtm_dump_dblog_login;
GO

DECLARE @password NVARCHAR(128) = (SELECT certificate_password FROM #CertificateConfig);
DECLARE @quoted_password NVARCHAR(300) = QUOTENAME(@password, '''');
EXEC(N'ADD SIGNATURE TO awsdms.rtm_dump_dblog '
    + N'BY CERTIFICATE awsdms_rtm_dump_dblog_cert '
    + N'WITH PASSWORD = N' + @quoted_password + N';');
GO

IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'awsdms_rtm_position_1st_timestamp_cert')
BEGIN
    IF OBJECT_ID(N'awsdms.rtm_position_1st_timestamp', N'P') IS NOT NULL
       AND EXISTS (
           SELECT 1 FROM sys.crypt_properties AS cp
           JOIN sys.certificates AS c ON c.thumbprint = cp.thumbprint
           WHERE c.name = N'awsdms_rtm_position_1st_timestamp_cert'
             AND cp.major_id = OBJECT_ID(N'awsdms.rtm_position_1st_timestamp')
       )
        DROP SIGNATURE FROM awsdms.rtm_position_1st_timestamp
            BY CERTIFICATE awsdms_rtm_position_1st_timestamp_cert;
END
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'awsdms_rtm_position_1st_timestamp_login')
BEGIN
    ALTER SERVER ROLE sysadmin DROP MEMBER awsdms_rtm_position_1st_timestamp_login;
    DROP LOGIN awsdms_rtm_position_1st_timestamp_login;
END
GO

IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'awsdms_rtm_position_1st_timestamp_cert')
    DROP CERTIFICATE awsdms_rtm_position_1st_timestamp_cert;
GO

DECLARE @password NVARCHAR(128) = (SELECT certificate_password FROM #CertificateConfig);
DECLARE @quoted_password NVARCHAR(300) = QUOTENAME(@password, '''');
EXEC(N'CREATE CERTIFICATE awsdms_rtm_position_1st_timestamp_cert '
    + N'ENCRYPTION BY PASSWORD = N' + @quoted_password + N' '
    + N'WITH SUBJECT = N''Certificate for first timestamp positioning permissions'';');
GO

CREATE LOGIN awsdms_rtm_position_1st_timestamp_login
    FROM CERTIFICATE awsdms_rtm_position_1st_timestamp_cert;
ALTER SERVER ROLE sysadmin ADD MEMBER awsdms_rtm_position_1st_timestamp_login;
GO

DECLARE @password NVARCHAR(128) = (SELECT certificate_password FROM #CertificateConfig);
DECLARE @quoted_password NVARCHAR(300) = QUOTENAME(@password, '''');
EXEC(N'ADD SIGNATURE TO awsdms.rtm_position_1st_timestamp '
    + N'BY CERTIFICATE awsdms_rtm_position_1st_timestamp_cert '
    + N'WITH PASSWORD = N' + @quoted_password + N';');
GO

DROP TABLE #CertificateConfig;
GO

SELECT
    OBJECT_SCHEMA_NAME(cp.major_id) + N'.' + OBJECT_NAME(cp.major_id) AS signed_procedure,
    c.name AS certificate_name,
    cp.crypt_type_desc
FROM sys.crypt_properties AS cp
JOIN sys.certificates AS c ON c.thumbprint = cp.thumbprint
WHERE cp.major_id IN (
    OBJECT_ID(N'awsdms.rtm_dump_dblog'),
    OBJECT_ID(N'awsdms.rtm_position_1st_timestamp')
);
GO

PRINT '03 - Canonical certificates created and procedures signed.';
GO
