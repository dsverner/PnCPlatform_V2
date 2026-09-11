-- SCHEMA-DESIGN §8.1 (125). FILESTREAM FileTable holding every file the platform keeps; document.File
-- cites a row by stream_id and carries the SHA-256 compared on every read. Lives on the FileStreamData
-- filegroup (Storage/Filegroups.sql). Operational bulk (COMTRADE, oscillography) goes to the archive
-- tier's store (§13.4); File.FileStreamId is then null.
-- Class FileTable: not system-versioned (FileTables cannot be); the generator emits a pass-through view
-- only — files are written through the FILESTREAM share or the application's streaming API.
CREATE TABLE [document].[FileStore] AS FILETABLE
WITH (FILETABLE_DIRECTORY = N'FileStore', FILETABLE_COLLATE_FILENAME = database_default);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'FileTable',
    @level0type = N'SCHEMA', @level0name = N'document', @level1type = N'TABLE', @level1name = N'FileStore';
GO
