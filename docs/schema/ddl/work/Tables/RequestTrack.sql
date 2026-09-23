-- Decision #227 (2026-09-22). One completion track of a change request brought over from the old program, as the old
-- program kept it: a status set by hand, a date and a note. The old program's change-request window shows three tracks
-- (prog_frmRelaySettingChangeStatus.dfm: documentation, settings database, software) and refuses "Complete Request"
-- while any says "Change In Progress" (prog_frmRelaySettingChangeStatus.cpp:227-235). The software track is not kept
-- (#58; the owner, 2026-09-22: "never seriously used … declared as completed or NA in all cases just so that the work
-- request could be completed") — its status stays a note on the request.
-- A request raised in the platform does not use this table: its tracks are the steps of its procedure. Edited by
-- work.SetRequestTrack only (direct saves with audit, #163); valid time keeps every earlier answer.
CREATE TABLE [work].[RequestTrack] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_RequestTrack_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RequestTrack_Registry] REFERENCES [work].[RequestTrackRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_RequestTrack_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RequestTrack_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RequestTrack_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_RequestTrack_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_RequestTrack_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_RequestTrack_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [WorkRequestEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_RequestTrack_WorkRequest] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    [TrackCode]         NVARCHAR(20)      NOT NULL CONSTRAINT [CK_RequestTrack_TrackCode] CHECK ([TrackCode] IN (N'Documentation', N'Database')),
    [Status]            NVARCHAR(20)      NOT NULL CONSTRAINT [CK_RequestTrack_Status] CHECK ([Status] IN (N'InProgress', N'Complete', N'NotNeeded')),
    [TrackDate]         DATETIMEOFFSET(7) NULL,
    [Note]              NVARCHAR(MAX)     NULL,
    CONSTRAINT [PK_RequestTrack] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_RequestTrack_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [work].[RequestTrack_History]));
GO
CREATE INDEX [IX_RequestTrack_Entity] ON [work].[RequestTrack] ([EntityId], [ValidFrom]);
GO
-- one live answer per request and track
CREATE UNIQUE INDEX [UX_RequestTrack_Live] ON [work].[RequestTrack] ([WorkRequestEntityId], [TrackCode])
    INCLUDE ([Status], [TrackDate]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'work', @level1type = N'TABLE', @level1name = N'RequestTrack';
GO
