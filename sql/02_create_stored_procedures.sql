-- =============================================================================
-- 02_create_stored_procedures.sql
-- Creates the two wrapper stored procedures that AWS DMS calls for CDC
-- log reading instead of the raw system functions.
--
-- These procedures wrap:
--   fn_dump_dblog        -> awsdms.rtm_dump_dblog
--   fn_position_1st_timestamp -> awsdms.rtm_position_1st_timestamp
--
-- Usage:
--   sqlcmd -S <server> -i 02_create_stored_procedures.sql
-- =============================================================================

USE master;
GO

-- Drop existing procedures if they exist
IF OBJECT_ID('awsdms.rtm_dump_dblog', 'P') IS NOT NULL
    DROP PROCEDURE awsdms.rtm_dump_dblog;
GO

IF OBJECT_ID('awsdms.rtm_position_1st_timestamp', 'P') IS NOT NULL
    DROP PROCEDURE awsdms.rtm_position_1st_timestamp;
GO

-- Wrapper for fn_dump_dblog
-- DMS calls this to read transaction log records for CDC
CREATE PROCEDURE awsdms.rtm_dump_dblog
    @start_lsn        VARCHAR(32)  = NULL,
    @end_lsn          VARCHAR(32)  = NULL,
    @device_type      VARCHAR(260) = 'DISK',
    @file_name_1      VARCHAR(260) = NULL,
    @file_name_2      VARCHAR(260) = NULL,
    @file_name_3      VARCHAR(260) = NULL,
    @file_name_4      VARCHAR(260) = NULL,
    @file_name_5      VARCHAR(260) = NULL,
    @file_name_6      VARCHAR(260) = NULL,
    @file_name_7      VARCHAR(260) = NULL,
    @file_name_8      VARCHAR(260) = NULL,
    @file_name_9      VARCHAR(260) = NULL,
    @file_name_10     VARCHAR(260) = NULL,
    @file_name_11     VARCHAR(260) = NULL,
    @file_name_12     VARCHAR(260) = NULL,
    @file_name_13     VARCHAR(260) = NULL,
    @file_name_14     VARCHAR(260) = NULL,
    @file_name_15     VARCHAR(260) = NULL,
    @file_name_16     VARCHAR(260) = NULL,
    @file_name_17     VARCHAR(260) = NULL,
    @file_name_18     VARCHAR(260) = NULL,
    @file_name_19     VARCHAR(260) = NULL,
    @file_name_20     VARCHAR(260) = NULL,
    @file_name_21     VARCHAR(260) = NULL,
    @file_name_22     VARCHAR(260) = NULL,
    @file_name_23     VARCHAR(260) = NULL,
    @file_name_24     VARCHAR(260) = NULL,
    @file_name_25     VARCHAR(260) = NULL,
    @file_name_26     VARCHAR(260) = NULL,
    @file_name_27     VARCHAR(260) = NULL,
    @file_name_28     VARCHAR(260) = NULL,
    @file_name_29     VARCHAR(260) = NULL,
    @file_name_30     VARCHAR(260) = NULL,
    @file_name_31     VARCHAR(260) = NULL,
    @file_name_32     VARCHAR(260) = NULL,
    @file_name_33     VARCHAR(260) = NULL,
    @file_name_34     VARCHAR(260) = NULL,
    @file_name_35     VARCHAR(260) = NULL,
    @file_name_36     VARCHAR(260) = NULL,
    @file_name_37     VARCHAR(260) = NULL,
    @file_name_38     VARCHAR(260) = NULL,
    @file_name_39     VARCHAR(260) = NULL,
    @file_name_40     VARCHAR(260) = NULL,
    @file_name_41     VARCHAR(260) = NULL,
    @file_name_42     VARCHAR(260) = NULL,
    @file_name_43     VARCHAR(260) = NULL,
    @file_name_44     VARCHAR(260) = NULL,
    @file_name_45     VARCHAR(260) = NULL,
    @file_name_46     VARCHAR(260) = NULL,
    @file_name_47     VARCHAR(260) = NULL,
    @file_name_48     VARCHAR(260) = NULL,
    @file_name_49     VARCHAR(260) = NULL,
    @file_name_50     VARCHAR(260) = NULL,
    @file_name_51     VARCHAR(260) = NULL,
    @file_name_52     VARCHAR(260) = NULL,
    @file_name_53     VARCHAR(260) = NULL,
    @file_name_54     VARCHAR(260) = NULL,
    @file_name_55     VARCHAR(260) = NULL,
    @file_name_56     VARCHAR(260) = NULL,
    @file_name_57     VARCHAR(260) = NULL,
    @file_name_58     VARCHAR(260) = NULL,
    @file_name_59     VARCHAR(260) = NULL,
    @file_name_60     VARCHAR(260) = NULL,
    @file_name_61     VARCHAR(260) = NULL,
    @file_name_62     VARCHAR(260) = NULL,
    @file_name_63     VARCHAR(260) = NULL,
    @file_name_64     VARCHAR(260) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT * FROM fn_dump_dblog(
        @start_lsn, @end_lsn, @device_type,
        @file_name_1,  @file_name_2,  @file_name_3,  @file_name_4,
        @file_name_5,  @file_name_6,  @file_name_7,  @file_name_8,
        @file_name_9,  @file_name_10, @file_name_11, @file_name_12,
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

-- Wrapper for fn_position_1st_timestamp
-- DMS calls this to find the starting LSN for a given timestamp
CREATE PROCEDURE awsdms.rtm_position_1st_timestamp
    @db_name   SYSNAME,
    @timestamp DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    SELECT fn_position_1st_timestamp(@db_name, @timestamp);
END
GO

PRINT '02 - Stored procedures created successfully.';
GO
