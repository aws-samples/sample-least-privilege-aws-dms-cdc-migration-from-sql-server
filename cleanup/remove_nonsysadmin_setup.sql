-- =============================================================================
-- remove_nonsysadmin_setup.sql
-- Removes every wrapper-owned object created by the canonical setup and revokes
-- the permissions it grants. It never drops the pre-existing DMS server login.
--
-- Run from the repository root:
--   sqlcmd -S <server> -i cleanup/remove_nonsysadmin_setup.sql \
--     -v DMS_USER="dmsnosysadmin" DB_NAME="<source-database>" \
--        REMOVE_DMS_USERS="1" CLEAN_SOURCE_DATABASE="1" \
--        REMOVE_PUBLICATION="1"
--
-- CLEAN_SOURCE_DATABASE=1 removes source db_owner membership on the primary.
-- Use 0 when running instance-local cleanup on a read-only AG secondary.
-- REMOVE_PUBLICATION=1 drops the sample AR_PUBLICATION_* publication and its
-- articles on the primary. It never removes distribution because distribution
-- can be shared by other publications.
-- =============================================================================

USE master;
GO

DECLARE @dms_user SYSNAME = N'$(DMS_USER)';
DECLARE @source_database SYSNAME = N'$(DB_NAME)';
DECLARE @remove_users BIT = TRY_CONVERT(BIT, '$(REMOVE_DMS_USERS)');
DECLARE @clean_source_database BIT = TRY_CONVERT(BIT, '$(CLEAN_SOURCE_DATABASE)');
DECLARE @remove_publication BIT = TRY_CONVERT(BIT, '$(REMOVE_PUBLICATION)');
DECLARE @quoted_user NVARCHAR(258) = QUOTENAME(@dms_user);
DECLARE @quoted_database NVARCHAR(258) = QUOTENAME(@source_database);
DECLARE @sql NVARCHAR(MAX);

IF @remove_users IS NULL OR @clean_source_database IS NULL OR @remove_publication IS NULL
    THROW 51040, 'REMOVE_DMS_USERS, CLEAN_SOURCE_DATABASE, and REMOVE_PUBLICATION must be 0 or 1.', 1;
IF DB_ID(@source_database) IS NULL
    THROW 51041, 'The specified source database does not exist.', 1;

-- Revoke server- and master-level grants while the objects still exist.
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @dms_user)
BEGIN
    SET @sql = N'REVOKE VIEW SERVER STATE FROM ' + @quoted_user + N';'
      + N'REVOKE VIEW ANY DEFINITION FROM ' + @quoted_user + N';';
    EXEC sys.sp_executesql @sql;
END

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @dms_user)
BEGIN
    SET @sql = N'REVOKE SELECT ON sys.fn_dblog FROM ' + @quoted_user + N';'
      + N'REVOKE EXECUTE ON sys.sp_repldone FROM ' + @quoted_user + N';'
      + N'REVOKE EXECUTE ON sys.sp_replincrementlsn FROM ' + @quoted_user + N';'
      + N'REVOKE EXECUTE ON sys.sp_addpublication FROM ' + @quoted_user + N';'
      + N'REVOKE EXECUTE ON sys.sp_addarticle FROM ' + @quoted_user + N';'
      + N'REVOKE EXECUTE ON sys.sp_articlefilter FROM ' + @quoted_user + N';';
    IF OBJECT_ID(N'awsdms.split_partition_list', N'TF') IS NOT NULL
        SET @sql += N'REVOKE SELECT ON awsdms.split_partition_list FROM ' + @quoted_user + N';';
    IF OBJECT_ID(N'awsdms.rtm_dump_dblog', N'P') IS NOT NULL
        SET @sql += N'REVOKE EXECUTE ON awsdms.rtm_dump_dblog FROM ' + @quoted_user + N';';
    IF OBJECT_ID(N'awsdms.rtm_position_1st_timestamp', N'P') IS NOT NULL
        SET @sql += N'REVOKE EXECUTE ON awsdms.rtm_position_1st_timestamp FROM ' + @quoted_user + N';';
    EXEC sys.sp_executesql @sql;
END

-- Drop signatures before their certificates.
IF OBJECT_ID(N'awsdms.rtm_dump_dblog', N'P') IS NOT NULL
   AND EXISTS (
       SELECT 1 FROM sys.crypt_properties AS cp
       JOIN sys.certificates AS c ON c.thumbprint = cp.thumbprint
       WHERE c.name = N'awsdms_rtm_dump_dblog_cert'
         AND cp.major_id = OBJECT_ID(N'awsdms.rtm_dump_dblog')
   )
    DROP SIGNATURE FROM awsdms.rtm_dump_dblog BY CERTIFICATE awsdms_rtm_dump_dblog_cert;

IF OBJECT_ID(N'awsdms.rtm_position_1st_timestamp', N'P') IS NOT NULL
   AND EXISTS (
       SELECT 1 FROM sys.crypt_properties AS cp
       JOIN sys.certificates AS c ON c.thumbprint = cp.thumbprint
       WHERE c.name = N'awsdms_rtm_position_1st_timestamp_cert'
         AND cp.major_id = OBJECT_ID(N'awsdms.rtm_position_1st_timestamp')
   )
    DROP SIGNATURE FROM awsdms.rtm_position_1st_timestamp
        BY CERTIFICATE awsdms_rtm_position_1st_timestamp_cert;

-- Remove both non-interactive certificate logins from sysadmin and drop them.
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'awsdms_rtm_dump_dblog_login')
BEGIN
    ALTER SERVER ROLE sysadmin DROP MEMBER awsdms_rtm_dump_dblog_login;
    DROP LOGIN awsdms_rtm_dump_dblog_login;
END

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'awsdms_rtm_position_1st_timestamp_login')
BEGIN
    ALTER SERVER ROLE sysadmin DROP MEMBER awsdms_rtm_position_1st_timestamp_login;
    DROP LOGIN awsdms_rtm_position_1st_timestamp_login;
END

IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'awsdms_rtm_dump_dblog_cert')
    DROP CERTIFICATE awsdms_rtm_dump_dblog_cert;
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'awsdms_rtm_position_1st_timestamp_cert')
    DROP CERTIFICATE awsdms_rtm_position_1st_timestamp_cert;

IF OBJECT_ID(N'awsdms.rtm_dump_dblog', N'P') IS NOT NULL
    DROP PROCEDURE awsdms.rtm_dump_dblog;
IF OBJECT_ID(N'awsdms.rtm_position_1st_timestamp', N'P') IS NOT NULL
    DROP PROCEDURE awsdms.rtm_position_1st_timestamp;
IF OBJECT_ID(N'awsdms.split_partition_list', N'TF') IS NOT NULL
    DROP FUNCTION awsdms.split_partition_list;
IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'awsdms')
    DROP SCHEMA awsdms;

-- Undo source-database grants and optionally remove the sample publication on
-- the primary. Skip this block on a read-only AG secondary.
IF @clean_source_database = 1
BEGIN
    SET @sql = N'USE ' + @quoted_database + N';'
      + CASE WHEN @remove_publication = 1 THEN
          N'DECLARE @publication SYSNAME = N''AR_PUBLICATION_'' + RIGHT(''00000'' + CAST(DB_ID() AS VARCHAR(10)), 5);'
          + N'IF EXISTS (SELECT 1 FROM dbo.syspublications WHERE name = @publication) '
          + N'EXEC sys.sp_droppublication @publication = @publication;'
        ELSE N'' END
      + N'IF IS_ROLEMEMBER(N''db_owner'', ' + QUOTENAME(@dms_user, '''') + N') = 1 '
      + N'ALTER ROLE db_owner DROP MEMBER ' + @quoted_user + N';'
      + CASE WHEN @remove_users = 1 THEN
          N'IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '
          + QUOTENAME(@dms_user, '''') + N') DROP USER ' + @quoted_user + N';'
        ELSE N'' END;
    EXEC sys.sp_executesql @sql;
END

-- Undo local msdb grants on every replica.
SET @sql = N'USE msdb;'
  + N'IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '
  + QUOTENAME(@dms_user, '''') + N') BEGIN '
  + N'REVOKE SELECT ON dbo.backupset FROM ' + @quoted_user + N';'
  + N'REVOKE SELECT ON dbo.backupmediafamily FROM ' + @quoted_user + N';'
  + N'REVOKE SELECT ON dbo.backupfile FROM ' + @quoted_user + N';'
  + CASE WHEN @remove_users = 1 THEN N'DROP USER ' + @quoted_user + N';' ELSE N'' END
  + N' END;';
EXEC sys.sp_executesql @sql;

IF @remove_users = 1 AND EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @dms_user)
BEGIN
    SET @sql = N'DROP USER ' + @quoted_user + N';';
    EXEC sys.sp_executesql @sql;
END

PRINT 'Cleanup complete: canonical certificates, sysadmin certificate logins, wrappers, helper, and grants removed.';
PRINT 'The pre-existing DMS server login was not dropped.';
GO
