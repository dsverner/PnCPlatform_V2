-- SCHEMA-DESIGN §3.1 (80). Allowed (child, parent) node-type pairs; the node procedure refuses others.
CREATE TABLE [ref].[LocationNodeTypeParent] (
    [ChildNodeTypeCode]  NVARCHAR(40)     NOT NULL CONSTRAINT [FK_LocationNodeTypeParent_Child]  REFERENCES [ref].[LocationNodeType] ([NodeTypeCode]),
    [ParentNodeTypeCode] NVARCHAR(40)     NOT NULL CONSTRAINT [FK_LocationNodeTypeParent_Parent] REFERENCES [ref].[LocationNodeType] ([NodeTypeCode]),
    [IsRequired]         BIT              NOT NULL CONSTRAINT [DF_LocationNodeTypeParent_IsRequired] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LocationNodeTypeParent_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LocationNodeTypeParent_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_LocationNodeTypeParent_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LocationNodeTypeParent_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_LocationNodeTypeParent] PRIMARY KEY CLUSTERED ([ChildNodeTypeCode], [ParentNodeTypeCode])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[LocationNodeTypeParent_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'LocationNodeTypeParent';
GO
