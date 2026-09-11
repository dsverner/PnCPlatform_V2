-- PLATFORM-ARCHITECTURE §8.1 (226), §9.2 (229); SCHEMA-DESIGN §15.6 (232). Class AppendOnly. A release of the
-- platform: the versioned artifact set (DACPAC, application package, SBOM) with its hashes — the platform's
-- own baseline, read by the catalogue facts platform.release / platform.baseline. Written by
-- tools/record_release.py (through platform.Release_Append) at the end of a deployment.
CREATE TABLE [platform].[Release] (
    [ReleaseId]              BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_Release] PRIMARY KEY CLUSTERED,
    [Version]                NVARCHAR(40)      NOT NULL CONSTRAINT [UQ_Release_Version] UNIQUE,
    [ReleasedAt]             DATETIMEOFFSET(7) NOT NULL,
    [DacpacHash]             BINARY(32)        NOT NULL,
    [PackageHash]            BINARY(32)        NULL,
    [SbomDocumentEntityId]   UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_Release_Sbom] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    [ReleaseDocumentEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Release_Document] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    [RecordedByActorId]      UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Release_RecordedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [Notes]                  NVARCHAR(MAX)     NULL
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'platform', @level1type = N'TABLE', @level1name = N'Release';
GO
