-- =============================================================================
-- 01_create_schema_and_functions.sql
-- Creates the awsdms schema and split_partition_list table-valued function in
-- master. This matches the tested all-in-one standalone setup.
-- =============================================================================

USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'awsdms')
    EXEC(N'CREATE SCHEMA [awsdms] AUTHORIZATION [dbo]');
GO

IF OBJECT_ID(N'awsdms.split_partition_list', N'TF') IS NOT NULL
    DROP FUNCTION awsdms.split_partition_list;
GO

CREATE FUNCTION awsdms.split_partition_list
(
    @plist VARCHAR(8000),
    @dlm NVARCHAR(1)
)
RETURNS @partitions TABLE (pid BIGINT PRIMARY KEY)
AS
BEGIN
    DECLARE @partition_id BIGINT;
    DECLARE @delimiter_position INT;
    DECLARE @delimiter_length INT = LEN(@dlm);

    WHILE CHARINDEX(@dlm, @plist) > 0
    BEGIN
        SET @delimiter_position = CHARINDEX(@dlm, @plist);
        SET @partition_id = CAST(LTRIM(RTRIM(SUBSTRING(@plist, 1, @delimiter_position - 1))) AS BIGINT);
        INSERT INTO @partitions (pid) VALUES (@partition_id);
        SET @plist = SUBSTRING(@plist, @delimiter_position + @delimiter_length, LEN(@plist));
    END

    SET @partition_id = CAST(LTRIM(RTRIM(@plist)) AS BIGINT);
    INSERT INTO @partitions (pid) VALUES (@partition_id);
    RETURN;
END
GO

PRINT '01 - awsdms schema and split_partition_list function created.';
GO
