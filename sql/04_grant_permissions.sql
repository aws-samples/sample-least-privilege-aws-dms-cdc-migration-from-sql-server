-- =============================================================================
-- 04_grant_permissions.sql
-- Applies the verified minimum working permissions for a non-sysadmin AWS DMS
-- endpoint login.
--
-- Run from the repository root:
--   sqlcmd -S <server> -i sql/04_grant_permissions.sql \
--     -v DMS_USER="dmsnosysadmin" DB_NAME="<source-database>"
-- =============================================================================

USE master;
GO

DECLARE @dms_user SYSNAME = N'$(DMS_USER)';
DECLARE @source_database SYSNAME = N'$(DB_NAME)';
DECLARE @quoted_user NVARCHAR(258) = QUOTENAME(@dms_user);
DECLARE @quoted_database NVARCHAR(258) = QUOTENAME(@source_database);
DECLARE @sql NVARCHAR(MAX);

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @dms_user)
    THROW 51020, 'The DMS server login does not exist. Create it before running this script.', 1;

IF DB_ID(@source_database) IS NULL
    THROW 51021, 'The specified source database does not exist.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @dms_user)
BEGIN
    SET @sql = N'CREATE USER ' + @quoted_user + N' FOR LOGIN ' + @quoted_user + N';';
    EXEC sys.sp_executesql @sql;
END

SET @sql =
    N'GRANT VIEW SERVER STATE TO ' + @quoted_user + N';'
  + N'GRANT VIEW ANY DEFINITION TO ' + @quoted_user + N';'
  + N'GRANT SELECT ON sys.fn_dblog TO ' + @quoted_user + N';'
  + N'GRANT EXECUTE ON sys.sp_repldone TO ' + @quoted_user + N';'
  + N'GRANT EXECUTE ON sys.sp_replincrementlsn TO ' + @quoted_user + N';'
  + N'GRANT EXECUTE ON sys.sp_addpublication TO ' + @quoted_user + N';'
  + N'GRANT EXECUTE ON sys.sp_addarticle TO ' + @quoted_user + N';'
  + N'GRANT EXECUTE ON sys.sp_articlefilter TO ' + @quoted_user + N';'
  + N'GRANT SELECT ON awsdms.split_partition_list TO ' + @quoted_user + N';'
  + N'GRANT EXECUTE ON awsdms.rtm_dump_dblog TO ' + @quoted_user + N';'
  + N'GRANT EXECUTE ON awsdms.rtm_position_1st_timestamp TO ' + @quoted_user + N';';
EXEC sys.sp_executesql @sql;

SET @sql = N'USE ' + @quoted_database + N';'
  + N'IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '
  + QUOTENAME(@dms_user, '''') + N') '
  + N'CREATE USER ' + @quoted_user + N' FOR LOGIN ' + @quoted_user + N';'
  + N'IF IS_ROLEMEMBER(N''db_owner'', ' + QUOTENAME(@dms_user, '''') + N') <> 1 '
  + N'ALTER ROLE db_owner ADD MEMBER ' + @quoted_user + N';';
EXEC sys.sp_executesql @sql;

SET @sql = N'USE msdb;'
  + N'IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '
  + QUOTENAME(@dms_user, '''') + N') '
  + N'CREATE USER ' + @quoted_user + N' FOR LOGIN ' + @quoted_user + N';'
  + N'GRANT SELECT ON dbo.backupset TO ' + @quoted_user + N';'
  + N'GRANT SELECT ON dbo.backupmediafamily TO ' + @quoted_user + N';'
  + N'GRANT SELECT ON dbo.backupfile TO ' + @quoted_user + N';';
EXEC sys.sp_executesql @sql;

SELECT
    @dms_user AS login_name,
    IS_SRVROLEMEMBER(N'sysadmin', @dms_user) AS is_sysadmin;

PRINT '04 - Verified non-sysadmin permissions granted.';
GO
