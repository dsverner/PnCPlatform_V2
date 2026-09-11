-- SCHEMA-DESIGN §13.4 (177). Class AppendOnly. What has been moved out of the live tables, where,
-- and how to verify it.
CREATE TABLE [archive].[Manifest] (
    [ManifestId]            BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_Manifest] PRIMARY KEY CLUSTERED,
    [SourceSchema]          SYSNAME           NOT NULL,
    [SourceTable]           SYSNAME           NOT NULL,
    [KeyRangeFrom]          NVARCHAR(100)     NOT NULL,
    [KeyRangeTo]            NVARCHAR(100)     NOT NULL,
    [RowCount]              BIGINT            NOT NULL,
    [MovedAt]               DATETIMEOFFSET(7) NOT NULL,
    [Destination]           NVARCHAR(40)      NOT NULL CONSTRAINT [CK_Manifest_Destination] CHECK ([Destination] IN (N'SameDatabaseFilegroup', N'ArchiveDatabase', N'CompanionStore')),
    [DestinationReference]  NVARCHAR(400)     NOT NULL,
    [Sha256]                BINARY(32)        NOT NULL,
    [MovedByActorId]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Manifest_MovedBy] REFERENCES [personnel].[Actor] ([ActorId])
);
GO
CREATE INDEX [IX_Manifest_Source] ON [archive].[Manifest] ([SourceSchema], [SourceTable], [MovedAt]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'archive', @level1type = N'TABLE', @level1name = N'Manifest';
GO
