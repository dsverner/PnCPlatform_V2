-- Filegroups per SCHEMA-DESIGN §13.4 (decision 177): the event tier and bulk files are on
-- their own filegroups from the first deployment so the archive seam needs no later move.
-- File paths come from the SQLCMD variable $(DataPath) (publish profile / deploy.py).
ALTER DATABASE [$(DatabaseName)] ADD FILEGROUP [EventData];
GO
ALTER DATABASE [$(DatabaseName)] ADD FILEGROUP [EventIndex];
GO
ALTER DATABASE [$(DatabaseName)] ADD FILEGROUP [BulkFiles];
GO
ALTER DATABASE [$(DatabaseName)]
    ADD FILE (NAME = [PnCPlatform_EventData], FILENAME = '$(DataPath)$(DatabaseName)_EventData.ndf', SIZE = 64MB, FILEGROWTH = 64MB)
    TO FILEGROUP [EventData];
GO
ALTER DATABASE [$(DatabaseName)]
    ADD FILE (NAME = [PnCPlatform_EventIndex], FILENAME = '$(DataPath)$(DatabaseName)_EventIndex.ndf', SIZE = 32MB, FILEGROWTH = 32MB)
    TO FILEGROUP [EventIndex];
GO
ALTER DATABASE [$(DatabaseName)] ADD FILEGROUP [FileStreamData] CONTAINS FILESTREAM;
GO
ALTER DATABASE [$(DatabaseName)]
    ADD FILE (NAME = [PnCPlatform_FileStream], FILENAME = '$(DataPath)$(DatabaseName)_FileStream')
    TO FILEGROUP [FileStreamData];
GO
ALTER DATABASE [$(DatabaseName)]
    ADD FILE (NAME = [PnCPlatform_BulkFiles], FILENAME = '$(DataPath)$(DatabaseName)_BulkFiles.ndf', SIZE = 64MB, FILEGROWTH = 64MB)
    TO FILEGROUP [BulkFiles];
GO
