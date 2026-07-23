/*
================================================================================
  AWS DMS - Setup Ongoing Replication on Standalone SQL Server: Without Sysadmin Role
  
  Compatible with: SQL Server 2016, 2017, 2019, 2022+
  
  Source: https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.SQLServer.CDC.html
  Section: Setting up ongoing replication on a standalone SQL Server: Without sysadmin role
  
  PREREQUISITES:
  1. SQL Server is configured for full backups (full recovery mode or bulk-logged mode)
  2. MS-REPLICATION is enabled on the source database
     (Run task once as sysadmin OR configure distribution manually)
  3. Run this script as SYSADMIN
  
  PARAMETERS TO CHANGE (search for "CHANGE ME"):
  - @DMS_User       : The DMS endpoint user (login name)
  - @SourceDB       : The source database name to replicate
  - @CertPassword   : Password for certificate encryption (change for production!)
  
  VERSION COMPATIBILITY:
  - SQL Server 2016/2017: fn_dump_dblog has 63 params (5 named + 58 defaults)
  - SQL Server 2019:      fn_dump_dblog has 65 params (5 named + 60 defaults)  
  - SQL Server 2022:      fn_dump_dblog has 68 params (5 named + 63 defaults)
  - This script auto-detects and generates the correct procedure.
  
  After running this script, add the following ECA to the DMS source endpoint:
      enableNonSysadminWrapper=true;
================================================================================
*/

-- ============================================================================
-- CONFIGURATION - CHANGE ME
-- ============================================================================
DECLARE @DMS_User NVARCHAR(128) = N'dms_user';            -- CHANGE ME: DMS endpoint login
DECLARE @SourceDB NVARCHAR(128) = N'SourceDB';            -- CHANGE ME: Source database name
DECLARE @CertPassword NVARCHAR(128) = N'@5trongpassword'; -- CHANGE ME: Certificate password
-- ============================================================================

-- Store config in temp table so it persists across GO batches
IF OBJECT_ID('tempdb..#DMS_Config') IS NOT NULL DROP TABLE #DMS_Config;
CREATE TABLE #DMS_Config (DMS_User NVARCHAR(128), SourceDB NVARCHAR(128), CertPassword NVARCHAR(128));
INSERT INTO #DMS_Config VALUES (@DMS_User, @SourceDB, @CertPassword);
GO

-- ============================================================================
-- STEP 1: Create [awsdms] schema on Master database
-- ============================================================================
PRINT '=== STEP 1: Creating [awsdms] schema on Master database ===';
USE [master]
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'awsdms')
BEGIN
    EXEC('CREATE SCHEMA awsdms');
    PRINT '  Schema [awsdms] created.';
END
ELSE
    PRINT '  Schema [awsdms] already exists. Skipping.';
GO

-- ============================================================================
-- STEP 2: Create table-valued function [awsdms].[split_partition_list]
-- ============================================================================
PRINT '=== STEP 2: Creating [awsdms].[split_partition_list] function ===';
USE [master]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF (OBJECT_ID('[awsdms].[split_partition_list]','TF')) IS NOT NULL
    DROP FUNCTION [awsdms].[split_partition_list];
GO

CREATE FUNCTION [awsdms].[split_partition_list]
(
    @plist VARCHAR(8000),
    @dlm NVARCHAR(1)
)
RETURNS @partitionsTable TABLE
(
    pid BIGINT PRIMARY KEY
)
AS
BEGIN
    DECLARE @partition_id BIGINT;
    DECLARE @dlm_pos INTEGER;
    DECLARE @dlm_len INTEGER;
    SET @dlm_len = LEN(@dlm);

    WHILE (CHARINDEX(@dlm, @plist) > 0)
    BEGIN
        SET @dlm_pos = CHARINDEX(@dlm, @plist);
        SET @partition_id = CAST(LTRIM(RTRIM(SUBSTRING(@plist, 1, @dlm_pos - 1))) AS BIGINT);
        INSERT INTO @partitionsTable (pid) VALUES (@partition_id);
        SET @plist = SUBSTRING(@plist, @dlm_pos + @dlm_len, LEN(@plist));
    END

    SET @partition_id = CAST(LTRIM(RTRIM(@plist)) AS BIGINT);
    INSERT INTO @partitionsTable (pid) VALUES (@partition_id);
    RETURN
END
GO

PRINT '  Function [awsdms].[split_partition_list] created.';
GO

-- ============================================================================
-- STEP 3: Create procedure [awsdms].[rtm_dump_dblog] (VERSION-AWARE)
-- ============================================================================
PRINT '=== STEP 3: Creating [awsdms].[rtm_dump_dblog] (auto-detecting fn_dump_dblog params) ===';
USE [master]
GO

IF (OBJECT_ID('[awsdms].[rtm_dump_dblog]','P')) IS NOT NULL
    DROP PROCEDURE [awsdms].[rtm_dump_dblog];
GO

-- Dynamically build the procedure based on fn_dump_dblog parameter count
DECLARE @param_count INT;
DECLARE @default_count INT;
DECLARE @defaults NVARCHAR(MAX) = '';
DECLARE @i INT = 1;
DECLARE @sql NVARCHAR(MAX);

-- Get the actual parameter count for fn_dump_dblog on this SQL Server version
SELECT @param_count = COUNT(*) 
FROM sys.all_parameters 
WHERE object_id = OBJECT_ID('sys.fn_dump_dblog');

SET @default_count = @param_count - 5; -- 5 named params: @start_lsn, NULL, N'DISK', @seqno, @filename

PRINT '  Detected fn_dump_dblog parameter count: ' + CAST(@param_count AS VARCHAR(10));
PRINT '  Default parameters needed: ' + CAST(@default_count AS VARCHAR(10));

-- Build the defaults string
WHILE @i <= @default_count
BEGIN
    SET @defaults = @defaults + 'default';
    IF @i < @default_count SET @defaults = @defaults + ',';
    SET @i = @i + 1;
END

-- Build the CREATE PROCEDURE statement dynamically
SET @sql = '
CREATE PROCEDURE [awsdms].[rtm_dump_dblog]
(
    @start_lsn VARCHAR(32),
    @seqno INTEGER,
    @filename VARCHAR(260),
    @partition_list VARCHAR(8000),
    @programmed_filtering INTEGER,
    @minPartition BIGINT,
    @maxPartition BIGINT
)
AS
BEGIN
    DECLARE @start_lsn_cmp VARCHAR(32);
    SET NOCOUNT ON;

    SET @start_lsn_cmp = @start_lsn;

    IF (@start_lsn_cmp) IS NULL
        SET @start_lsn_cmp = ''00000000:00000000:0000'';

    IF (@partition_list IS NULL)
    BEGIN
        RAISERROR (''Null partition list was passed'', 16, 1);
        RETURN;
    END

    IF (@start_lsn) IS NOT NULL
        SET @start_lsn = ''0x'' + @start_lsn;

    IF (@programmed_filtering = 0)
    BEGIN
        SELECT
            [Current LSN],[operation],[Context],[Transaction ID],[Transaction Name],
            [Begin Time],[End Time],[Flag Bits],[PartitionID],[Page ID],[Slot ID],
            [RowLog Contents 0],[Log Record],[RowLog Contents 1]
        FROM fn_dump_dblog (
            @start_lsn, NULL, N''DISK'', @seqno, @filename,
            ' + @defaults + ')
        WHERE [Current LSN] COLLATE SQL_Latin1_General_CP1_CI_AS > @start_lsn_cmp COLLATE SQL_Latin1_General_CP1_CI_AS
        AND (
            ([operation] IN (''LOP_BEGIN_XACT'',''LOP_COMMIT_XACT'',''LOP_ABORT_XACT''))
            OR
            ([operation] IN (''LOP_INSERT_ROWS'',''LOP_DELETE_ROWS'',''LOP_MODIFY_ROW'')
                AND (([context] IN (''LCX_HEAP'',''LCX_CLUSTERED'',''LCX_MARK_AS_GHOST''))
                     OR ([context] = ''LCX_TEXT_MIX'' AND (DATALENGTH([RowLog Contents 0]) IN (0,1))))
                AND [PartitionID] IN (SELECT * FROM master.awsdms.split_partition_list(@partition_list, '',''))
            )
            OR ([operation] = ''LOP_HOBT_DDL'')
        );
    END
    ELSE
    BEGIN
        SELECT
            [Current LSN],[operation],[Context],[Transaction ID],[Transaction Name],
            [Begin Time],[End Time],[Flag Bits],[PartitionID],[Page ID],[Slot ID],
            [RowLog Contents 0],[Log Record],[RowLog Contents 1]
        FROM fn_dump_dblog (
            @start_lsn, NULL, N''DISK'', @seqno, @filename,
            ' + @defaults + ')
        WHERE [Current LSN] COLLATE SQL_Latin1_General_CP1_CI_AS > @start_lsn_cmp COLLATE SQL_Latin1_General_CP1_CI_AS
        AND (
            ([operation] IN (''LOP_BEGIN_XACT'',''LOP_COMMIT_XACT'',''LOP_ABORT_XACT''))
            OR
            ([operation] IN (''LOP_INSERT_ROWS'',''LOP_DELETE_ROWS'',''LOP_MODIFY_ROW'')
                AND (([context] IN (''LCX_HEAP'',''LCX_CLUSTERED'',''LCX_MARK_AS_GHOST''))
                     OR ([context] = ''LCX_TEXT_MIX'' AND (DATALENGTH([RowLog Contents 0]) IN (0,1))))
                AND ([PartitionID] IS NOT NULL)
                AND ([PartitionID] >= @minPartition AND [PartitionID] <= @maxPartition)
            )
            OR ([operation] = ''LOP_HOBT_DDL'')
        );
    END

    SET NOCOUNT OFF;
END';

EXEC sp_executesql @sql;
PRINT '  Procedure [awsdms].[rtm_dump_dblog] created successfully.';
GO

-- ============================================================================
-- STEP 4-7: Certificate, login, sysadmin, and signature for rtm_dump_dblog
-- ============================================================================
PRINT '=== STEP 4-7: Certificate + signature for rtm_dump_dblog ===';
USE [master]
GO

DECLARE @CertPassword NVARCHAR(128);
SELECT @CertPassword = CertPassword FROM #DMS_Config;

IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'awsdms_rtm_dump_dblog_login')
    DROP LOGIN [awsdms_rtm_dump_dblog_login];
IF EXISTS (SELECT * FROM sys.certificates WHERE name = 'awsdms_rtm_dump_dblog_cert')
    DROP CERTIFICATE [awsdms_rtm_dump_dblog_cert];

DECLARE @sql NVARCHAR(MAX);
SET @sql = 'CREATE CERTIFICATE [awsdms_rtm_dump_dblog_cert] ENCRYPTION BY PASSWORD = N''' + @CertPassword + ''' WITH SUBJECT = N''Certificate for FN_DUMP_DBLOG Permissions''';
EXEC sp_executesql @sql;

CREATE LOGIN [awsdms_rtm_dump_dblog_login] FROM CERTIFICATE [awsdms_rtm_dump_dblog_cert];
ALTER SERVER ROLE [sysadmin] ADD MEMBER [awsdms_rtm_dump_dblog_login];

SET @sql = 'ADD SIGNATURE TO [master].[awsdms].[rtm_dump_dblog] BY CERTIFICATE [awsdms_rtm_dump_dblog_cert] WITH PASSWORD = ''' + @CertPassword + '''';
EXEC sp_executesql @sql;

PRINT '  Certificate, login, sysadmin role, and signature applied.';
GO

-- ============================================================================
-- STEP 8: Create procedure [awsdms].[rtm_position_1st_timestamp] (VERSION-AWARE)
-- ============================================================================
PRINT '=== STEP 8: Creating [awsdms].[rtm_position_1st_timestamp] (auto-detecting params) ===';
USE [master]
GO

IF OBJECT_ID('[awsdms].[rtm_position_1st_timestamp]','P') IS NOT NULL
    DROP PROCEDURE [awsdms].[rtm_position_1st_timestamp];
GO

DECLARE @param_count INT;
DECLARE @default_count INT;
DECLARE @defaults NVARCHAR(MAX) = '';
DECLARE @i INT = 1;
DECLARE @sql NVARCHAR(MAX);

-- fn_dump_dblog params: first 4 are named (NULL, NULL, NULL, @seqno, @filename = 5 total but for this proc we use NULL,NULL,NULL,seqno,filename)
SELECT @param_count = COUNT(*) 
FROM sys.all_parameters 
WHERE object_id = OBJECT_ID('sys.fn_dump_dblog');

SET @default_count = @param_count - 5;

WHILE @i <= @default_count
BEGIN
    SET @defaults = @defaults + 'default';
    IF @i < @default_count SET @defaults = @defaults + ',';
    SET @i = @i + 1;
END

SET @sql = '
CREATE PROCEDURE [awsdms].[rtm_position_1st_timestamp]
(
    @dbname SYSNAME,
    @seqno INTEGER,
    @filename VARCHAR(260),
    @1stTimeStamp VARCHAR(40)
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @firstMatching TABLE (cLsn VARCHAR(32), bTim DATETIME);
    DECLARE @sql NVARCHAR(4000);
    DECLARE @nl CHAR(2);
    DECLARE @tb CHAR(2);
    DECLARE @fnameVar NVARCHAR(254) = ''NULL'';

    SET @nl = CHAR(10);
    SET @tb = CHAR(9);

    IF (@filename IS NOT NULL)
        SET @fnameVar = '''''''' + @filename + '''''''';

    SET @sql = ''use ['' + @dbname + ''];'' + @nl +
        ''select top 1 [Current LSN],[Begin Time]'' + @nl +
        ''FROM fn_dump_dblog (NULL, NULL, NULL, '' + CAST(@seqno AS VARCHAR(10)) + '','' + @fnameVar + '','' + @nl +
        @tb + ''' + @defaults + ')'' + @nl +
        ''where operation=''''LOP_BEGIN_XACT'''''' + @nl +
        ''and [Begin Time]>= cast('' + '''''''' + @1stTimeStamp + '''''''' + '' as datetime)'' + @nl;

    DELETE FROM @firstMatching;
    INSERT INTO @firstMatching EXEC sp_executesql @sql;

    SELECT TOP 1 cLsn AS [matching LSN], CONVERT(VARCHAR, bTim, 121) AS [matching Timestamp]
    FROM @firstMatching;

    SET NOCOUNT OFF;
END';

EXEC sp_executesql @sql;
PRINT '  Procedure [awsdms].[rtm_position_1st_timestamp] created successfully.';
GO

-- ============================================================================
-- STEP 9-12: Certificate, login, sysadmin, and signature for rtm_position_1st_timestamp
-- ============================================================================
PRINT '=== STEP 9-12: Certificate + signature for rtm_position_1st_timestamp ===';
USE [master]
GO

DECLARE @CertPassword NVARCHAR(128);
SELECT @CertPassword = CertPassword FROM #DMS_Config;

IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'awsdms_rtm_position_1st_timestamp_login')
    DROP LOGIN [awsdms_rtm_position_1st_timestamp_login];
IF EXISTS (SELECT * FROM sys.certificates WHERE name = 'awsdms_rtm_position_1st_timestamp_cert')
    DROP CERTIFICATE [awsdms_rtm_position_1st_timestamp_cert];

DECLARE @sql NVARCHAR(MAX);
SET @sql = 'CREATE CERTIFICATE [awsdms_rtm_position_1st_timestamp_cert] ENCRYPTION BY PASSWORD = ''' + @CertPassword + ''' WITH SUBJECT = N''Certificate for FN_POSITION_1st_TIMESTAMP Permissions''';
EXEC sp_executesql @sql;

CREATE LOGIN [awsdms_rtm_position_1st_timestamp_login] FROM CERTIFICATE [awsdms_rtm_position_1st_timestamp_cert];
ALTER SERVER ROLE [sysadmin] ADD MEMBER [awsdms_rtm_position_1st_timestamp_login];

SET @sql = 'ADD SIGNATURE TO [master].[awsdms].[rtm_position_1st_timestamp] BY CERTIFICATE [awsdms_rtm_position_1st_timestamp_cert] WITH PASSWORD = ''' + @CertPassword + '''';
EXEC sp_executesql @sql;

PRINT '  Certificate, login, sysadmin role, and signature applied.';
GO

-- ============================================================================
-- STEP 13: Grant permissions to DMS user on Master database
-- ============================================================================
PRINT '=== STEP 13: Granting permissions to DMS user on Master database ===';
USE [master]
GO

DECLARE @DMS_User NVARCHAR(128);
SELECT @DMS_User = DMS_User FROM #DMS_Config;
DECLARE @sql NVARCHAR(MAX);

-- Create user in master if not exists
SET @sql = 'IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = ''' + @DMS_User + ''') CREATE USER [' + @DMS_User + '] FOR LOGIN [' + @DMS_User + ']';
EXEC sp_executesql @sql;

-- Grant permissions
SET @sql = '
GRANT SELECT ON sys.fn_dblog TO [' + @DMS_User + '];
GRANT VIEW ANY DEFINITION TO [' + @DMS_User + '];
GRANT VIEW SERVER STATE TO [' + @DMS_User + '];
GRANT EXECUTE ON sp_repldone TO [' + @DMS_User + '];
GRANT EXECUTE ON sp_replincrementlsn TO [' + @DMS_User + '];
GRANT EXECUTE ON sp_addpublication TO [' + @DMS_User + '];
GRANT EXECUTE ON sp_addarticle TO [' + @DMS_User + '];
GRANT EXECUTE ON sp_articlefilter TO [' + @DMS_User + '];
GRANT SELECT ON [awsdms].[split_partition_list] TO [' + @DMS_User + '];
GRANT EXECUTE ON [awsdms].[rtm_dump_dblog] TO [' + @DMS_User + '];
GRANT EXECUTE ON [awsdms].[rtm_position_1st_timestamp] TO [' + @DMS_User + '];';
EXEC sp_executesql @sql;

PRINT '  Master database permissions granted.';
GO

-- ============================================================================
-- STEP 14: Grant permissions on MSDB database
-- ============================================================================
PRINT '=== STEP 14: Granting permissions to DMS user on MSDB database ===';
USE [msdb]
GO

DECLARE @DMS_User NVARCHAR(128);
SELECT @DMS_User = DMS_User FROM #DMS_Config;
DECLARE @sql NVARCHAR(MAX);

-- Create user in msdb if not exists
SET @sql = 'IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = ''' + @DMS_User + ''') CREATE USER [' + @DMS_User + '] FOR LOGIN [' + @DMS_User + ']';
EXEC sp_executesql @sql;

SET @sql = '
GRANT SELECT ON msdb.dbo.backupset TO [' + @DMS_User + '];
GRANT SELECT ON msdb.dbo.backupmediafamily TO [' + @DMS_User + '];
GRANT SELECT ON msdb.dbo.backupfile TO [' + @DMS_User + '];';
EXEC sp_executesql @sql;

PRINT '  MSDB permissions granted.';
GO

-- ============================================================================
-- STEP 15: Grant db_owner on source database
-- ============================================================================
PRINT '=== STEP 15: Granting db_owner to DMS user on source database ===';

DECLARE @DMS_User NVARCHAR(128), @SourceDB NVARCHAR(128);
SELECT @DMS_User = DMS_User, @SourceDB = SourceDB FROM #DMS_Config;
DECLARE @sql NVARCHAR(MAX);

SET @sql = 'USE [' + @SourceDB + ']; ' +
    'IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = ''' + @DMS_User + ''') CREATE USER [' + @DMS_User + '] FOR LOGIN [' + @DMS_User + ']; ' +
    'EXEC sp_addrolemember N''db_owner'', N''' + @DMS_User + ''';';
EXEC sp_executesql @sql;

PRINT '  db_owner role granted on [' + @SourceDB + '].';
GO

-- ============================================================================
-- CLEANUP & VERIFICATION
-- ============================================================================
DROP TABLE IF EXISTS #DMS_Config;
GO

PRINT '';
PRINT '================================================================================';
PRINT '  SETUP COMPLETE!';
PRINT '================================================================================';
PRINT '';
PRINT '  SQL Server Version: ' + CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20));
PRINT '';
PRINT '  Objects created on [master]:';
PRINT '    - Schema: [awsdms]';
PRINT '    - Function: [awsdms].[split_partition_list]';
PRINT '    - Procedure: [awsdms].[rtm_dump_dblog] (version-aware)';
PRINT '    - Procedure: [awsdms].[rtm_position_1st_timestamp] (version-aware)';
PRINT '    - Certificate: [awsdms_rtm_dump_dblog_cert]';
PRINT '    - Certificate: [awsdms_rtm_position_1st_timestamp_cert]';
PRINT '    - Login: [awsdms_rtm_dump_dblog_login] (sysadmin via cert)';
PRINT '    - Login: [awsdms_rtm_position_1st_timestamp_login] (sysadmin via cert)';
PRINT '';
PRINT '  IMPORTANT: Add this ECA to your DMS source endpoint:';
PRINT '    enableNonSysadminWrapper=true;';
PRINT '';
PRINT '  IMPORTANT: If you recreate the stored procedures, you MUST re-add signatures!';
PRINT '================================================================================';
GO
