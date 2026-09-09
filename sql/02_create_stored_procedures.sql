-- =============================================================================
-- 02_create_stored_procedures.sql
-- Creates the same version-aware DMS wrapper procedures as the tested
-- all-in-one standalone setup.
-- =============================================================================

USE master;
GO

IF OBJECT_ID(N'awsdms.rtm_dump_dblog', N'P') IS NOT NULL
    DROP PROCEDURE awsdms.rtm_dump_dblog;
GO

DECLARE @parameter_count INT;
DECLARE @default_count INT;
DECLARE @defaults NVARCHAR(MAX) = N'';
DECLARE @index INT = 1;
DECLARE @sql NVARCHAR(MAX);

SELECT @parameter_count = COUNT(*)
FROM sys.all_parameters
WHERE object_id = OBJECT_ID(N'sys.fn_dump_dblog');

IF @parameter_count <= 5
    THROW 51005, 'Unable to determine the fn_dump_dblog parameter count.', 1;

SET @default_count = @parameter_count - 5;
WHILE @index <= @default_count
BEGIN
    SET @defaults += CASE WHEN @index > 1 THEN N',' ELSE N'' END + N'default';
    SET @index += 1;
END

SET @sql = N'
CREATE PROCEDURE awsdms.rtm_dump_dblog
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

    IF @start_lsn_cmp IS NULL
        SET @start_lsn_cmp = ''00000000:00000000:0000'';

    IF @partition_list IS NULL
    BEGIN
        RAISERROR (''Null partition list was passed'', 16, 1);
        RETURN;
    END

    IF @start_lsn IS NOT NULL
        SET @start_lsn = ''0x'' + @start_lsn;

    IF @programmed_filtering = 0
    BEGIN
        SELECT
            [Current LSN], [operation], [Context], [Transaction ID], [Transaction Name],
            [Begin Time], [End Time], [Flag Bits], [PartitionID], [Page ID], [Slot ID],
            [RowLog Contents 0], [Log Record], [RowLog Contents 1]
        FROM fn_dump_dblog (
            @start_lsn, NULL, N''DISK'', @seqno, @filename,
            ' + @defaults + N')
        WHERE [Current LSN] COLLATE SQL_Latin1_General_CP1_CI_AS
              > @start_lsn_cmp COLLATE SQL_Latin1_General_CP1_CI_AS
          AND (
              [operation] IN (''LOP_BEGIN_XACT'', ''LOP_COMMIT_XACT'', ''LOP_ABORT_XACT'')
              OR (
                  [operation] IN (''LOP_INSERT_ROWS'', ''LOP_DELETE_ROWS'', ''LOP_MODIFY_ROW'')
                  AND (
                      [context] IN (''LCX_HEAP'', ''LCX_CLUSTERED'', ''LCX_MARK_AS_GHOST'')
                      OR ([context] = ''LCX_TEXT_MIX'' AND DATALENGTH([RowLog Contents 0]) IN (0, 1))
                  )
                  AND [PartitionID] IN (
                      SELECT pid FROM master.awsdms.split_partition_list(@partition_list, '','')
                  )
              )
              OR [operation] = ''LOP_HOBT_DDL''
          );
    END
    ELSE
    BEGIN
        SELECT
            [Current LSN], [operation], [Context], [Transaction ID], [Transaction Name],
            [Begin Time], [End Time], [Flag Bits], [PartitionID], [Page ID], [Slot ID],
            [RowLog Contents 0], [Log Record], [RowLog Contents 1]
        FROM fn_dump_dblog (
            @start_lsn, NULL, N''DISK'', @seqno, @filename,
            ' + @defaults + N')
        WHERE [Current LSN] COLLATE SQL_Latin1_General_CP1_CI_AS
              > @start_lsn_cmp COLLATE SQL_Latin1_General_CP1_CI_AS
          AND (
              [operation] IN (''LOP_BEGIN_XACT'', ''LOP_COMMIT_XACT'', ''LOP_ABORT_XACT'')
              OR (
                  [operation] IN (''LOP_INSERT_ROWS'', ''LOP_DELETE_ROWS'', ''LOP_MODIFY_ROW'')
                  AND (
                      [context] IN (''LCX_HEAP'', ''LCX_CLUSTERED'', ''LCX_MARK_AS_GHOST'')
                      OR ([context] = ''LCX_TEXT_MIX'' AND DATALENGTH([RowLog Contents 0]) IN (0, 1))
                  )
                  AND [PartitionID] IS NOT NULL
                  AND [PartitionID] >= @minPartition
                  AND [PartitionID] <= @maxPartition
              )
              OR [operation] = ''LOP_HOBT_DDL''
          );
    END

    SET NOCOUNT OFF;
END;';

EXEC sys.sp_executesql @sql;
PRINT 'Created awsdms.rtm_dump_dblog with '
    + CAST(@default_count AS VARCHAR(10)) + ' version-specific default parameters.';
GO

IF OBJECT_ID(N'awsdms.rtm_position_1st_timestamp', N'P') IS NOT NULL
    DROP PROCEDURE awsdms.rtm_position_1st_timestamp;
GO

DECLARE @parameter_count INT;
DECLARE @default_count INT;
DECLARE @defaults NVARCHAR(MAX) = N'';
DECLARE @index INT = 1;
DECLARE @sql NVARCHAR(MAX);

SELECT @parameter_count = COUNT(*)
FROM sys.all_parameters
WHERE object_id = OBJECT_ID(N'sys.fn_dump_dblog');

IF @parameter_count <= 5
    THROW 51006, 'Unable to determine the fn_dump_dblog parameter count.', 1;

SET @default_count = @parameter_count - 5;
WHILE @index <= @default_count
BEGIN
    SET @defaults += CASE WHEN @index > 1 THEN N',' ELSE N'' END + N'default';
    SET @index += 1;
END

SET @sql = N'
CREATE PROCEDURE awsdms.rtm_position_1st_timestamp
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
    DECLARE @statement NVARCHAR(4000);
    DECLARE @newline CHAR(2) = CHAR(10);
    DECLARE @tab CHAR(2) = CHAR(9);
    DECLARE @filename_variable NVARCHAR(254) = ''NULL'';

    IF @filename IS NOT NULL
        SET @filename_variable = '''''''' + @filename + '''''''';

    SET @statement = ''USE '' + QUOTENAME(@dbname) + '';
SELECT TOP (1) [Current LSN], [Begin Time]
FROM fn_dump_dblog (NULL, NULL, NULL, '' + CAST(@seqno AS VARCHAR(10)) + '',''
        + @filename_variable + '','' + @newline + @tab + ''' + @defaults + N')
WHERE [operation] = ''''LOP_BEGIN_XACT''''
  AND [Begin Time] >= CAST('''''''' + @1stTimeStamp + '''''''' AS DATETIME);'';

    INSERT INTO @firstMatching
        EXEC sys.sp_executesql @statement;

    SELECT TOP (1)
        cLsn AS [matching LSN],
        CONVERT(VARCHAR, bTim, 121) AS [matching Timestamp]
    FROM @firstMatching;

    SET NOCOUNT OFF;
END;';

EXEC sys.sp_executesql @sql;
PRINT 'Created awsdms.rtm_position_1st_timestamp using fn_dump_dblog timestamp positioning.';
GO

PRINT '02 - Version-aware wrapper procedures created.';
GO
