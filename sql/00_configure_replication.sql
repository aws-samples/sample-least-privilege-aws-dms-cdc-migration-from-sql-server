-- =============================================================================
-- 00_configure_replication.sql
-- Configures SQL Server distribution, creates the DMS-compatible transactional
-- publication, and adds primary-key user tables as filtered log-based articles.
--
-- Run as sysadmin from the source database context. Run from the repository root:
--   sqlcmd -S <server> -d <source-database> \
--     -i sql/00_configure_replication.sql \
--     -v REPLDATA_DIR="C:\\Program Files\\Microsoft SQL Server\\MSSQL\\ReplData" \
--        CREATE_PUBLICATION="1"
--
-- Run on every AG replica. Use CREATE_PUBLICATION=1 on the primary (or a
-- standalone source) and CREATE_PUBLICATION=0 on secondary replicas.
-- metadata while AWS DMS reads and transfers the changes itself.
-- Tables without a primary key are excluded from this publication.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @database_name SYSNAME = DB_NAME();
DECLARE @distributor SYSNAME = @@SERVERNAME;
DECLARE @working_directory NVARCHAR(4000) = N'$(REPLDATA_DIR)';
DECLARE @create_publication BIT = TRY_CONVERT(BIT, '$(CREATE_PUBLICATION)');

IF @create_publication IS NULL
    THROW 51000, 'CREATE_PUBLICATION must be 0 or 1.', 1;

IF @create_publication = 1 AND @database_name IN (N'master', N'model', N'msdb', N'tempdb')
    THROW 51001, 'Run publication setup from the user source database.', 1;

-- Configure this instance as its own distributor once. The working directory
-- must exist and be writable by SQL Server Agent.
IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE is_distributor = 1)
BEGIN
    IF NULLIF(@working_directory, N'') IS NULL
        THROW 51002, 'Set REPLDATA_DIR to a valid replication working directory.', 1;

    EXEC master.dbo.sp_adddistributor
        @distributor = @distributor,
        @password = N'';

    EXEC master.dbo.sp_adddistributiondb
        @database = N'distribution',
        @security_mode = 1;

    EXEC master.dbo.sp_adddistpublisher
        @publisher = @distributor,
        @distribution_db = N'distribution',
        @security_mode = 1,
        @working_directory = @working_directory;

    PRINT 'Configured SQL Server distribution.';
END
ELSE
    PRINT 'Distribution is already configured; no change made.';

IF @create_publication = 0
BEGIN
    PRINT 'Distribution-only mode complete on this replica.';
    RETURN;
END

-- Enable this source database for publishing.
IF NOT EXISTS (
    SELECT 1
    FROM master.dbo.sysdatabases
    WHERE dbid = DB_ID() AND (category & 1) <> 0
)
BEGIN
    EXEC sys.sp_replicationdboption
        @dbname = @database_name,
        @optname = N'publish',
        @value = N'true';
END

DECLARE @database_id INT = DB_ID();
DECLARE @suffix VARCHAR(10) = RIGHT('00000' + CAST(DB_ID() AS VARCHAR(10)), 5);
DECLARE @publication_name SYSNAME = N'AR_PUBLICATION_' + @suffix;
DECLARE @publication_description NVARCHAR(255) =
    N'AWS Schema Conversion Tool DMS Agent: Anonymous transactional publication for database '
    + @database_name + N' from publisher ' + @distributor + N'.';

IF NOT EXISTS (SELECT 1 FROM dbo.syspublications WHERE name = @publication_name)
BEGIN
    EXEC sys.sp_addpublication
        @publication = @publication_name,
        @description = @publication_description,
        @sync_method = N'native',
        @retention = 1,
        @allow_push = N'true',
        @allow_pull = N'true',
        @allow_anonymous = N'true',
        @enabled_for_internet = N'false',
        @snapshot_in_defaultfolder = N'true',
        @compress_snapshot = N'false',
        @allow_subscription_copy = N'false',
        @add_to_active_directory = N'false',
        @repl_freq = N'continuous',
        @status = N'active',
        @independent_agent = N'true',
        @immediate_sync = N'true',
        @allow_sync_tran = N'false',
        @autogen_sync_procs = N'false',
        @allow_queued_tran = N'false',
        @allow_dts = N'false',
        @replicate_ddl = 1,
        @allow_initialize_from_backup = N'false',
        @enabled_for_p2p = N'false',
        @enabled_for_het_sub = N'false';

    PRINT 'Created publication ' + @publication_name + N'.';
END
ELSE
    PRINT 'Publication ' + @publication_name + N' already exists.';

DECLARE @schema_name SYSNAME;
DECLARE @table_name SYSNAME;
DECLARE @object_id INT;
DECLARE @article_name SYSNAME;
DECLARE @filter_name SYSNAME;

DECLARE article_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT s.name, t.name, t.object_id
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
  AND EXISTS (
      SELECT 1 FROM sys.indexes AS i
      WHERE i.object_id = t.object_id AND i.is_primary_key = 1
  )
  AND t.name NOT LIKE N'awsdms[_]%'
  AND NOT EXISTS (
      SELECT 1
      FROM distribution.dbo.MSarticles AS a
      JOIN distribution.dbo.MSpublications AS p
        ON p.publication_id = a.publication_id
      WHERE p.publication = @publication_name
        AND a.source_owner = s.name
        AND a.source_object = t.name
  )
ORDER BY s.name, t.name;

OPEN article_cursor;
FETCH NEXT FROM article_cursor INTO @schema_name, @table_name, @object_id;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @article_name = N'AR_ARTICLE_' + @suffix + N'_' + CAST(@object_id AS NVARCHAR(20));
    SET @filter_name = N'AR_FILTER_' + @suffix + N'_' + CAST(@object_id AS NVARCHAR(20));

    EXEC sys.sp_addarticle
        @publication = @publication_name,
        @article = @article_name,
        @source_owner = @schema_name,
        @source_object = @table_name,
        @type = N'logbased',
        @creation_script = N'',
        @description = N'',
        @schema_option = 0x050D3,
        @pre_creation_cmd = N'drop',
        @identityrangemanagementoption = N'none',
        @status = 16,
        @vertical_partition = N'false',
        @filter_clause = N'(1=0)';

    EXEC sys.sp_articlefilter
        @publication = @publication_name,
        @article = @article_name,
        @filter_name = @filter_name,
        @filter_clause = N'(1=0)',
        @force_invalidate_snapshot = 1,
        @force_reinit_subscription = 1;

    PRINT N'Added article for ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@table_name) + N'.';
    FETCH NEXT FROM article_cursor INTO @schema_name, @table_name, @object_id;
END

CLOSE article_cursor;
DEALLOCATE article_cursor;

PRINT '';
PRINT 'Replication configuration complete.';
PRINT 'Publication: ' + @publication_name;
PRINT 'Only user tables with primary keys were added; other tables require MS-CDC configuration.';
GO
