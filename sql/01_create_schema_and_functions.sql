-- =============================================================================
-- 01_create_schema_and_functions.sql
-- Creates the awsdms schema and heartbeat function in the master database.
--
-- Usage:
--   sqlcmd -S <server> -i 01_create_schema_and_functions.sql -v DMS_USER="dmsnosysadmin"
--
-- SQLCMD Variables:
--   DMS_USER  - The DMS login name (default: dmsnosysadmin)
-- =============================================================================

USE master;
GO

-- Create the awsdms schema if it does not exist
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'awsdms')
BEGIN
    EXEC('CREATE SCHEMA [awsdms] AUTHORIZATION [dbo]');
END
GO

-- Create or replace the heartbeat function
-- DMS uses this to track replication health
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

PRINT '01 - Schema and functions created successfully.';
GO
