/* ============================================================================
   PnCPlatform — extensibility gate toy (SCHEMA-DESIGN §2.6, decision 77)
   00-schema.sql — every object the gate uses. Run once into an empty database.

   TOY. Minimal tables shaped per SCHEMA-DESIGN §0.3 / §2.1–2.4 / §12.3–12.4.
   Deviations from the design are listed in README.md.
   ============================================================================ */
SET NOCOUNT ON;
GO
CREATE SCHEMA ref;
GO
CREATE SCHEMA personnel;
GO
CREATE SCHEMA config;
GO
CREATE SCHEMA asset;
GO
CREATE SCHEMA compliance;
GO

/* ---------------------------------------------------------------- reference */
CREATE TABLE ref.DefinitionKind (
    DefinitionKind NVARCHAR(40) NOT NULL CONSTRAINT PK_DefinitionKind PRIMARY KEY,
    MetaKind       NVARCHAR(20) NOT NULL   -- CharacteristicSchema | Transform | Program
);
CREATE TABLE ref.Unit (
    UnitCode NVARCHAR(20)  NOT NULL CONSTRAINT PK_Unit PRIMARY KEY,
    Name     NVARCHAR(100) NOT NULL
);
CREATE TABLE ref.AssetType (
    AssetTypeCode NVARCHAR(40)  NOT NULL CONSTRAINT PK_AssetType PRIMARY KEY,
    Name          NVARCHAR(100) NOT NULL
);
CREATE TABLE personnel.Actor (
    ActorId     UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_Actor PRIMARY KEY,
    DisplayName NVARCHAR(100)    NOT NULL,
    CreatedAt   DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_Actor_CreatedAt DEFAULT SYSDATETIMEOFFSET()
);
GO

/* ---------------------------------------------------------------- config */
CREATE TABLE config.DefinitionRegistry (
    EntityId UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_DefinitionRegistry PRIMARY KEY
);
GO
CREATE TABLE config.Definition (
    RowSeq          BIGINT IDENTITY(1,1) NOT NULL,
    RowId           UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Definition_RowId DEFAULT NEWSEQUENTIALID(),
    EntityId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_Definition_Registry REFERENCES config.DefinitionRegistry(EntityId),
    SysStart        DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    SysEnd          DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysStart, SysEnd),
    CreatedBy       UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_Definition_CreatedBy  REFERENCES personnel.Actor(ActorId),
    CreatedAt       DATETIMEOFFSET(7) NOT NULL,
    ModifiedBy      UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_Definition_ModifiedBy REFERENCES personnel.Actor(ActorId),
    ModifiedAt      DATETIMEOFFSET(7) NOT NULL,
    IsDeleted       BIT NOT NULL CONSTRAINT DF_Definition_IsDeleted DEFAULT 0,
    DeletedBy       UNIQUEIDENTIFIER NULL,
    DeletedAt       DATETIMEOFFSET(7) NULL,
    MigrationRunId  UNIQUEIDENTIFIER NULL,
    DefinitionKind  NVARCHAR(40)  NOT NULL CONSTRAINT FK_Definition_Kind REFERENCES ref.DefinitionKind(DefinitionKind),
    DefinitionKey   NVARCHAR(100) NOT NULL,
    Name            NVARCHAR(200) NOT NULL,
    Description     NVARCHAR(MAX) NULL,
    CONSTRAINT PK_Definition PRIMARY KEY CLUSTERED (RowSeq),
    CONSTRAINT UQ_Definition_RowId UNIQUE NONCLUSTERED (RowId)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = config.Definition_History));
GO
EXEC sys.sp_addextendedproperty N'PnC.TemporalClass', N'Versioned', N'SCHEMA', N'config', N'TABLE', N'Definition';
GO
CREATE UNIQUE INDEX UX_Definition_KindKey ON config.Definition(DefinitionKind, DefinitionKey) WHERE IsDeleted = 0;
GO
CREATE TABLE config.DefinitionVersion (
    RowSeq              BIGINT IDENTITY(1,1) NOT NULL,
    RowId               UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_DefinitionVersion_RowId DEFAULT NEWSEQUENTIALID(),
    EntityId            UNIQUEIDENTIFIER NOT NULL,      -- the version's own identity
    SysStart            DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    SysEnd              DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysStart, SysEnd),
    CreatedBy           UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_DefinitionVersion_CreatedBy  REFERENCES personnel.Actor(ActorId),
    CreatedAt           DATETIMEOFFSET(7) NOT NULL,
    ModifiedBy          UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_DefinitionVersion_ModifiedBy REFERENCES personnel.Actor(ActorId),
    ModifiedAt          DATETIMEOFFSET(7) NOT NULL,
    IsDeleted           BIT NOT NULL CONSTRAINT DF_DefinitionVersion_IsDeleted DEFAULT 0,
    DeletedBy           UNIQUEIDENTIFIER NULL,
    DeletedAt           DATETIMEOFFSET(7) NULL,
    MigrationRunId      UNIQUEIDENTIFIER NULL,
    DefinitionEntityId  UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_DefinitionVersion_Definition REFERENCES config.DefinitionRegistry(EntityId),
    VersionNumber       INT NOT NULL,
    Status              NVARCHAR(20) NOT NULL CONSTRAINT CK_DefinitionVersion_Status CHECK (Status IN (N'Draft', N'Approved', N'Effective', N'Retired')),
    EffectiveFrom       DATETIMEOFFSET(7) NULL,
    EffectiveTo         DATETIMEOFFSET(7) NULL,
    ApprovedBy          UNIQUEIDENTIFIER NULL CONSTRAINT FK_DefinitionVersion_ApprovedBy REFERENCES personnel.Actor(ActorId),
    ApprovedAt          DATETIMEOFFSET(7) NULL,
    ChangeNote          NVARCHAR(MAX) NULL,
    TestEvidenceRecordId UNIQUEIDENTIFIER NULL,        -- record.* does not exist in the toy
    PayloadText         NVARCHAR(MAX) NULL,            -- programs only (decision 78)
    PayloadHash         BINARY(32) NULL,
    CONSTRAINT PK_DefinitionVersion PRIMARY KEY CLUSTERED (RowSeq),
    CONSTRAINT UQ_DefinitionVersion_RowId UNIQUE NONCLUSTERED (RowId)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = config.DefinitionVersion_History));
GO
EXEC sys.sp_addextendedproperty N'PnC.TemporalClass', N'Versioned', N'SCHEMA', N'config', N'TABLE', N'DefinitionVersion';
GO
CREATE UNIQUE INDEX UX_DefinitionVersion_Number ON config.DefinitionVersion(DefinitionEntityId, VersionNumber) WHERE IsDeleted = 0;
GO
CREATE TABLE config.CharacteristicDefinition (
    RowSeq                  BIGINT IDENTITY(1,1) NOT NULL,
    RowId                   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_CharacteristicDefinition_RowId DEFAULT NEWSEQUENTIALID(),
    EntityId                UNIQUEIDENTIFIER NOT NULL,
    SysStart                DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    SysEnd                  DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysStart, SysEnd),
    CreatedBy               UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_CharacteristicDefinition_CreatedBy  REFERENCES personnel.Actor(ActorId),
    CreatedAt               DATETIMEOFFSET(7) NOT NULL,
    ModifiedBy              UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_CharacteristicDefinition_ModifiedBy REFERENCES personnel.Actor(ActorId),
    ModifiedAt              DATETIMEOFFSET(7) NOT NULL,
    IsDeleted               BIT NOT NULL CONSTRAINT DF_CharacteristicDefinition_IsDeleted DEFAULT 0,
    DeletedBy               UNIQUEIDENTIFIER NULL,
    DeletedAt               DATETIMEOFFSET(7) NULL,
    MigrationRunId          UNIQUEIDENTIFIER NULL,
    DefinitionVersionRowId  UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_CharacteristicDefinition_Version REFERENCES config.DefinitionVersion(RowId),
    CharacteristicKey       NVARCHAR(100) NOT NULL,
    Name                    NVARCHAR(200) NOT NULL,
    Description             NVARCHAR(MAX) NULL,
    DataType                NVARCHAR(20)  NOT NULL CONSTRAINT CK_CharacteristicDefinition_DataType CHECK (DataType IN (N'Text', N'Integer', N'Decimal', N'Boolean', N'DateTime', N'Reference', N'Enumeration')),
    UnitCode                NVARCHAR(20)  NULL CONSTRAINT FK_CharacteristicDefinition_Unit REFERENCES ref.Unit(UnitCode),
    Base                    NVARCHAR(20)  NULL CONSTRAINT CK_CharacteristicDefinition_Base CHECK (Base IS NULL OR Base IN (N'Primary', N'Secondary', N'PerUnit')),
    IsRequired              BIT NOT NULL CONSTRAINT DF_CharacteristicDefinition_IsRequired DEFAULT 0,
    AllowedValuesJson       NVARCHAR(MAX) NULL,   -- TOY: inline JSON array stands in for AllowedValuesDefinitionRowId
    ReferenceTargetKind     NVARCHAR(60)  NULL,
    ValidationExpression    NVARCHAR(MAX) NULL,
    DisplayOrder            INT NOT NULL CONSTRAINT DF_CharacteristicDefinition_DisplayOrder DEFAULT 0,
    DisplayGroup            NVARCHAR(100) NULL,
    IsCatalogueFact         BIT NOT NULL CONSTRAINT DF_CharacteristicDefinition_IsCatalogueFact DEFAULT 0,
    CONSTRAINT PK_CharacteristicDefinition PRIMARY KEY CLUSTERED (RowSeq),
    CONSTRAINT UQ_CharacteristicDefinition_RowId UNIQUE NONCLUSTERED (RowId)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = config.CharacteristicDefinition_History));
GO
EXEC sys.sp_addextendedproperty N'PnC.TemporalClass', N'Versioned', N'SCHEMA', N'config', N'TABLE', N'CharacteristicDefinition';
GO
CREATE UNIQUE INDEX UX_CharacteristicDefinition_Key ON config.CharacteristicDefinition(DefinitionVersionRowId, CharacteristicKey) WHERE IsDeleted = 0;
GO

/* ---------------------------------------------------------------- asset */
CREATE TABLE asset.AssetRegistry (
    EntityId UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_AssetRegistry PRIMARY KEY
);
GO
CREATE TABLE asset.Asset (
    RowSeq                      BIGINT IDENTITY(1,1) NOT NULL,
    RowId                       UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Asset_RowId DEFAULT NEWSEQUENTIALID(),
    EntityId                    UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_Asset_Registry REFERENCES asset.AssetRegistry(EntityId),
    ValidFrom                   DATETIMEOFFSET(7) NOT NULL,
    ValidTo                     DATETIMEOFFSET(7) NULL,
    ValidFromQuality            TINYINT NOT NULL CONSTRAINT DF_Asset_ValidFromQuality DEFAULT 0,
    SysStart                    DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    SysEnd                      DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysStart, SysEnd),
    CreatedBy                   UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_Asset_CreatedBy  REFERENCES personnel.Actor(ActorId),
    CreatedAt                   DATETIMEOFFSET(7) NOT NULL,
    ModifiedBy                  UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_Asset_ModifiedBy REFERENCES personnel.Actor(ActorId),
    ModifiedAt                  DATETIMEOFFSET(7) NOT NULL,
    IsDeleted                   BIT NOT NULL CONSTRAINT DF_Asset_IsDeleted DEFAULT 0,
    DeletedBy                   UNIQUEIDENTIFIER NULL,
    DeletedAt                   DATETIMEOFFSET(7) NULL,
    MigrationRunId              UNIQUEIDENTIFIER NULL,
    AssetTypeCode               NVARCHAR(40)  NOT NULL CONSTRAINT FK_Asset_Type REFERENCES ref.AssetType(AssetTypeCode),
    Name                        NVARCHAR(200) NOT NULL,   -- TOY: stands in for asset.AlternateKey designation
    TemplateDefinitionEntityId  UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_Asset_Template REFERENCES config.DefinitionRegistry(EntityId),
                                -- TOY: in the design this is resolved by config.DefinitionAppliesTo; here it is stored
    CONSTRAINT PK_Asset PRIMARY KEY CLUSTERED (RowSeq),
    CONSTRAINT UQ_Asset_RowId UNIQUE NONCLUSTERED (RowId)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = asset.Asset_History));
GO
EXEC sys.sp_addextendedproperty N'PnC.TemporalClass', N'ValidTime', N'SCHEMA', N'asset', N'TABLE', N'Asset';
GO
CREATE INDEX IX_Asset_Entity ON asset.Asset(EntityId, ValidFrom);
GO
CREATE TABLE asset.CharacteristicValue (
    RowSeq                          BIGINT IDENTITY(1,1) NOT NULL,
    RowId                           UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_CharacteristicValue_RowId DEFAULT NEWSEQUENTIALID(),
    EntityId                        UNIQUEIDENTIFIER NOT NULL,   -- the value's own identity (§2.4)
    ValidFrom                       DATETIMEOFFSET(7) NOT NULL,
    ValidTo                         DATETIMEOFFSET(7) NULL,
    ValidFromQuality                TINYINT NOT NULL CONSTRAINT DF_CharacteristicValue_ValidFromQuality DEFAULT 0,
    SysStart                        DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    SysEnd                          DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysStart, SysEnd),
    CreatedBy                       UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_CharacteristicValue_CreatedBy  REFERENCES personnel.Actor(ActorId),
    CreatedAt                       DATETIMEOFFSET(7) NOT NULL,
    ModifiedBy                      UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_CharacteristicValue_ModifiedBy REFERENCES personnel.Actor(ActorId),
    ModifiedAt                      DATETIMEOFFSET(7) NOT NULL,
    IsDeleted                       BIT NOT NULL CONSTRAINT DF_CharacteristicValue_IsDeleted DEFAULT 0,
    DeletedBy                       UNIQUEIDENTIFIER NULL,
    DeletedAt                       DATETIMEOFFSET(7) NULL,
    MigrationRunId                  UNIQUEIDENTIFIER NULL,
    HostEntityId                    UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_CharacteristicValue_Host REFERENCES asset.AssetRegistry(EntityId),
    CharacteristicDefinitionRowId   UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_CharacteristicValue_Definition REFERENCES config.CharacteristicDefinition(RowId),
    TextValue                       NVARCHAR(400) NULL,
    IntegerValue                    BIGINT NULL,
    DecimalValue                    DECIMAL(28,10) NULL,
    BooleanValue                    BIT NULL,
    DateTimeValue                   DATETIMEOFFSET(7) NULL,
    ReferenceEntityId               UNIQUEIDENTIFIER NULL,
    UnitOverrideCode                NVARCHAR(20) NULL CONSTRAINT FK_CharacteristicValue_UnitOverride REFERENCES ref.Unit(UnitCode),
    SourceRecordRowId               UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_CharacteristicValue PRIMARY KEY CLUSTERED (RowSeq),
    CONSTRAINT UQ_CharacteristicValue_RowId UNIQUE NONCLUSTERED (RowId),
    CONSTRAINT CK_CharacteristicValue_OneValue CHECK (
        (CASE WHEN TextValue IS NULL THEN 0 ELSE 1 END) + (CASE WHEN IntegerValue IS NULL THEN 0 ELSE 1 END)
      + (CASE WHEN DecimalValue IS NULL THEN 0 ELSE 1 END) + (CASE WHEN BooleanValue IS NULL THEN 0 ELSE 1 END)
      + (CASE WHEN DateTimeValue IS NULL THEN 0 ELSE 1 END) + (CASE WHEN ReferenceEntityId IS NULL THEN 0 ELSE 1 END) = 1)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = asset.CharacteristicValue_History));
GO
EXEC sys.sp_addextendedproperty N'PnC.TemporalClass', N'ValidTime', N'SCHEMA', N'asset', N'TABLE', N'CharacteristicValue';
GO
CREATE INDEX IX_CharacteristicValue_Host ON asset.CharacteristicValue(HostEntityId, CharacteristicDefinitionRowId, ValidFrom);
GO

/* ---------------------------------------------------------------- compliance */
CREATE TABLE compliance.RuleEvaluationRun (
    RunId                       UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_RuleEvaluationRun PRIMARY KEY,
    RuleDefinitionVersionRowId  UNIQUEIDENTIFIER NULL CONSTRAINT FK_RuleEvaluationRun_Rule REFERENCES config.DefinitionVersion(RowId),
    Mode                        NVARCHAR(20) NOT NULL CONSTRAINT CK_RuleEvaluationRun_Mode CHECK (Mode IN (N'Preview', N'Effective')),
    [Trigger]                   NVARCHAR(20) NOT NULL,
    StartedAt                   DATETIMEOFFSET(7) NOT NULL,
    CompletedAt                 DATETIMEOFFSET(7) NULL,
    ActorId                     UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_RuleEvaluationRun_Actor REFERENCES personnel.Actor(ActorId),
    SubjectsScoped              INT NULL,
    InstancesOpened             INT NULL,
    InstancesClosed             INT NULL,
    InstancesUnchanged          INT NULL,
    ResultDocumentEntityId      UNIQUEIDENTIFIER NULL
);
GO
EXEC sys.sp_addextendedproperty N'PnC.TemporalClass', N'AppendOnly', N'SCHEMA', N'compliance', N'TABLE', N'RuleEvaluationRun';
GO

/* ---------------------------------------------------------------- current views
   TOY: hand-written. The design generates these from PnC.TemporalClass (decision 69);
   the generator is DDL-project work, not under test here.                            */
CREATE VIEW config.vDefinition AS
    SELECT * FROM config.Definition WHERE IsDeleted = 0;
GO
CREATE VIEW config.vDefinitionVersion AS
    SELECT * FROM config.DefinitionVersion WHERE IsDeleted = 0;
GO
CREATE VIEW config.vCharacteristicDefinition AS
    SELECT * FROM config.CharacteristicDefinition WHERE IsDeleted = 0;
GO
CREATE VIEW asset.vAsset AS
    SELECT * FROM asset.Asset WHERE IsDeleted = 0 AND ValidTo IS NULL;
GO
CREATE VIEW asset.vCharacteristicValue AS
    SELECT * FROM asset.CharacteristicValue WHERE IsDeleted = 0 AND ValidTo IS NULL;
GO

/* The definition version in force now, per definition entity. */
CREATE VIEW config.vEffectiveDefinitionVersion AS
    SELECT dv.*
    FROM config.vDefinitionVersion dv
    WHERE dv.Status = N'Effective'
      AND dv.EffectiveFrom <= SYSDATETIMEOFFSET()
      AND (dv.EffectiveTo IS NULL OR dv.EffectiveTo > SYSDATETIMEOFFSET());
GO

/* ---------------------------------------------------------------- the fact catalogue (§12.3)
   A view over definition rows. Nothing regenerates it: a characteristic flagged
   IsCatalogueFact on the effective template version, or an effective formula, appears here
   by virtue of its row existing. This is the property the gate tests.                  */
CREATE VIEW compliance.vFactCatalogue AS
    SELECT
        FactName    = N'asset.template.' + cd.CharacteristicKey,
        FactSource  = N'Characteristic',
        FactKey     = cd.CharacteristicKey,
        DefinitionEntityId = dv.DefinitionEntityId,
        SourceSchema = N'asset', SourceObject = N'vCharacteristicValue',
        SourceColumn = CASE cd.DataType
                          WHEN N'Text' THEN N'TextValue' WHEN N'Enumeration' THEN N'TextValue'
                          WHEN N'Integer' THEN N'IntegerValue' WHEN N'Decimal' THEN N'DecimalValue'
                          WHEN N'Boolean' THEN N'BooleanValue' WHEN N'DateTime' THEN N'DateTimeValue'
                          WHEN N'Reference' THEN N'ReferenceEntityId' END,
        DataType    = cd.DataType,
        UnitCode    = cd.UnitCode,
        SubjectKind = N'Asset',
        TemporalClass = N'ValidTime',
        PublishedByDefinitionVersionRowId = dv.RowId
    FROM config.vCharacteristicDefinition cd
    JOIN config.vEffectiveDefinitionVersion dv ON dv.RowId = cd.DefinitionVersionRowId
    JOIN config.vDefinition d ON d.EntityId = dv.DefinitionEntityId
    WHERE cd.IsCatalogueFact = 1
      AND d.DefinitionKind = N'CharacteristicSchema.AssetTemplate'
    UNION ALL
    SELECT
        FactName    = N'asset.formula.' + d.DefinitionKey,
        FactSource  = N'Formula',
        FactKey     = d.DefinitionKey,
        DefinitionEntityId = d.EntityId,
        SourceSchema = N'config', SourceObject = N'vEffectiveDefinitionVersion', SourceColumn = N'PayloadText',
        DataType    = N'Boolean',
        UnitCode    = NULL,
        SubjectKind = N'Asset',
        TemporalClass = N'Versioned',
        PublishedByDefinitionVersionRowId = dv.RowId
    FROM config.vDefinition d
    JOIN config.vEffectiveDefinitionVersion dv ON dv.DefinitionEntityId = d.EntityId
    WHERE d.DefinitionKind = N'Program.Formula';
GO

/* ---------------------------------------------------------------- interpreter (T-SQL, generic)
   The payload grammar here is a JSON predicate tree and is a PLACEHOLDER for the formula
   language of vision §13.3. The gate's property does not depend on the grammar: facts are
   addressed by catalogue name only.

     leaf:   {"fact":"<FactName>","op":"=|<>|>|>=|<|<=|in","value":<scalar or array>}
     tree:   {"all":[...]} | {"any":[...]} | {"not":{...}}
   Comparison is numeric when both sides parse as DECIMAL(28,10), otherwise text.       */

/* Read one characteristic fact for a subject, as text, through the catalogue's key.
   Matches by (template definition entity, key) across template versions so a value entered
   under version 1 remains addressable after version 2 becomes effective (see README).      */
CREATE FUNCTION compliance.fCharacteristicFactValue
    (@subjectEntityId UNIQUEIDENTIFIER, @definitionEntityId UNIQUEIDENTIFIER, @key NVARCHAR(100), @at DATETIMEOFFSET(7))
RETURNS NVARCHAR(400)
AS
BEGIN
    DECLARE @v NVARCHAR(400);
    SELECT TOP (1) @v = COALESCE(
            cv.TextValue,
            CONVERT(NVARCHAR(400), cv.IntegerValue),
            CONVERT(NVARCHAR(400), cv.DecimalValue),
            CASE cv.BooleanValue WHEN 1 THEN N'true' WHEN 0 THEN N'false' END,
            CONVERT(NVARCHAR(400), cv.DateTimeValue, 127),
            CONVERT(NVARCHAR(400), cv.ReferenceEntityId))
    FROM asset.CharacteristicValue cv
    JOIN config.CharacteristicDefinition cd ON cd.RowId = cv.CharacteristicDefinitionRowId AND cd.IsDeleted = 0
    JOIN config.DefinitionVersion dv ON dv.RowId = cd.DefinitionVersionRowId AND dv.IsDeleted = 0
    WHERE cv.HostEntityId = @subjectEntityId
      AND cv.IsDeleted = 0
      AND cv.ValidFrom <= @at AND (cv.ValidTo IS NULL OR cv.ValidTo > @at)
      AND dv.DefinitionEntityId = @definitionEntityId
      AND cd.CharacteristicKey = @key
    ORDER BY cv.ValidFrom DESC, cv.RowSeq DESC;
    RETURN @v;
END;
GO

CREATE FUNCTION compliance.fEvaluate
    (@subjectEntityId UNIQUEIDENTIFIER, @json NVARCHAR(MAX), @at DATETIMEOFFSET(7))
RETURNS BIT
AS
BEGIN
    IF @json IS NULL RETURN 0;

    IF JSON_QUERY(@json, '$.all') IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM OPENJSON(@json, '$.all') j WHERE compliance.fEvaluate(@subjectEntityId, j.[value], @at) = 0) RETURN 0;
        RETURN 1;
    END
    IF JSON_QUERY(@json, '$.any') IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM OPENJSON(@json, '$.any') j WHERE compliance.fEvaluate(@subjectEntityId, j.[value], @at) = 1) RETURN 1;
        RETURN 0;
    END
    IF JSON_QUERY(@json, '$.not') IS NOT NULL
        RETURN CASE WHEN compliance.fEvaluate(@subjectEntityId, JSON_QUERY(@json, '$.not'), @at) = 1 THEN 0 ELSE 1 END;

    /* leaf */
    DECLARE @fact NVARCHAR(200) = JSON_VALUE(@json, '$.fact');
    DECLARE @op   NVARCHAR(10)  = JSON_VALUE(@json, '$.op');
    DECLARE @source NVARCHAR(20), @key NVARCHAR(100), @defEntity UNIQUEIDENTIFIER, @pubRowId UNIQUEIDENTIFIER;

    SELECT @source = FactSource, @key = FactKey, @defEntity = DefinitionEntityId, @pubRowId = PublishedByDefinitionVersionRowId
    FROM compliance.vFactCatalogue WHERE FactName = @fact;

    IF @source IS NULL
    BEGIN
        /* functions cannot THROW; force a conversion error carrying the fact name */
        DECLARE @boom INT = CONVERT(INT, N'UNKNOWN FACT: ' + ISNULL(@fact, N'(null)'));
        RETURN @boom;
    END

    DECLARE @fv NVARCHAR(400);
    IF @source = N'Characteristic'
        SET @fv = compliance.fCharacteristicFactValue(@subjectEntityId, @defEntity, @key, @at);
    ELSE IF @source = N'Formula'
        SET @fv = CASE WHEN compliance.fEvaluate(@subjectEntityId,
                                (SELECT PayloadText FROM config.DefinitionVersion WHERE RowId = @pubRowId), @at) = 1
                       THEN N'true' ELSE N'false' END;

    IF @fv IS NULL RETURN 0;   /* no value on this subject: the predicate does not hold */

    IF @op = N'in'
        RETURN CASE WHEN EXISTS (SELECT 1 FROM OPENJSON(@json, '$.value') v
                                  WHERE (TRY_CONVERT(DECIMAL(28,10), v.[value]) IS NOT NULL AND TRY_CONVERT(DECIMAL(28,10), @fv) IS NOT NULL
                                         AND TRY_CONVERT(DECIMAL(28,10), v.[value]) = TRY_CONVERT(DECIMAL(28,10), @fv))
                                     OR v.[value] = @fv) THEN 1 ELSE 0 END;

    DECLARE @lit NVARCHAR(400) = JSON_VALUE(@json, '$.value');
    DECLARE @fn DECIMAL(28,10) = TRY_CONVERT(DECIMAL(28,10), @fv);
    DECLARE @ln DECIMAL(28,10) = TRY_CONVERT(DECIMAL(28,10), @lit);
    DECLARE @cmp INT;
    IF @fn IS NOT NULL AND @ln IS NOT NULL
        SET @cmp = CASE WHEN @fn < @ln THEN -1 WHEN @fn > @ln THEN 1 ELSE 0 END;
    ELSE
        SET @cmp = CASE WHEN @fv < @lit THEN -1 WHEN @fv > @lit THEN 1 ELSE 0 END;

    RETURN CASE @op
             WHEN N'='  THEN CASE WHEN @cmp = 0  THEN 1 ELSE 0 END
             WHEN N'<>' THEN CASE WHEN @cmp <> 0 THEN 1 ELSE 0 END
             WHEN N'>'  THEN CASE WHEN @cmp > 0  THEN 1 ELSE 0 END
             WHEN N'>=' THEN CASE WHEN @cmp >= 0 THEN 1 ELSE 0 END
             WHEN N'<'  THEN CASE WHEN @cmp < 0  THEN 1 ELSE 0 END
             WHEN N'<=' THEN CASE WHEN @cmp <= 0 THEN 1 ELSE 0 END
             ELSE 0 END;
END;
GO

/* Convenience for reporting: a fact's value for a subject, by catalogue name. */
CREATE FUNCTION compliance.fFactValue
    (@subjectEntityId UNIQUEIDENTIFIER, @factName NVARCHAR(200), @at DATETIMEOFFSET(7))
RETURNS NVARCHAR(400)
AS
BEGIN
    DECLARE @source NVARCHAR(20), @key NVARCHAR(100), @defEntity UNIQUEIDENTIFIER, @pubRowId UNIQUEIDENTIFIER;
    SELECT @source = FactSource, @key = FactKey, @defEntity = DefinitionEntityId, @pubRowId = PublishedByDefinitionVersionRowId
    FROM compliance.vFactCatalogue WHERE FactName = @factName;
    IF @source = N'Characteristic' RETURN compliance.fCharacteristicFactValue(@subjectEntityId, @defEntity, @key, @at);
    IF @source = N'Formula'
        RETURN CASE WHEN compliance.fEvaluate(@subjectEntityId, (SELECT PayloadText FROM config.DefinitionVersion WHERE RowId = @pubRowId), @at) = 1
                    THEN N'true' ELSE N'false' END;
    RETURN NULL;
END;
GO

/* Every fact name a program payload references, at any depth. */
CREATE FUNCTION compliance.fPayloadFactNames (@json NVARCHAR(MAX))
RETURNS TABLE
AS
RETURN
    WITH nodes AS (
        SELECT CAST(@json AS NVARCHAR(MAX)) AS j
        UNION ALL
        SELECT CAST(o.[value] AS NVARCHAR(MAX))
        FROM nodes CROSS APPLY OPENJSON(nodes.j) o
        WHERE o.[type] IN (4, 5)          /* array, object */
    )
    SELECT DISTINCT FactName = JSON_VALUE(j, '$.fact') FROM nodes WHERE JSON_VALUE(j, '$.fact') IS NOT NULL;
GO

/* The interpreter refuses a program that names a fact absent from the catalogue (§12.3). */
CREATE PROCEDURE compliance.ValidateProgramFacts @payloadText NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    IF ISJSON(@payloadText) <> 1 THROW 50010, N'Program payload is not valid JSON.', 1;
    DECLARE @missing NVARCHAR(MAX);
    SELECT @missing = STRING_AGG(f.FactName, N', ')
    FROM compliance.fPayloadFactNames(@payloadText) f
    LEFT JOIN compliance.vFactCatalogue c ON c.FactName = f.FactName
    WHERE c.FactName IS NULL;
    IF @missing IS NOT NULL
    BEGIN
        DECLARE @msg NVARCHAR(MAX) = N'Program references facts not in the catalogue: ' + @missing;
        THROW 50011, @msg, 1;
    END
END;
GO

/* ---------------------------------------------------------------- write procedures (§0.5)
   TOY: the actor is passed in; the design resolves it from the session (step 11).          */
CREATE PROCEDURE config.AddDefinition
    @definitionKind NVARCHAR(40), @definitionKey NVARCHAR(100), @name NVARCHAR(200), @description NVARCHAR(MAX) = NULL,
    @actorId UNIQUEIDENTIFIER, @entityId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    SET @entityId = NEWID();
    INSERT config.DefinitionRegistry (EntityId) VALUES (@entityId);
    INSERT config.Definition (EntityId, CreatedBy, CreatedAt, ModifiedBy, ModifiedAt, DefinitionKind, DefinitionKey, Name, Description)
    VALUES (@entityId, @actorId, @now, @actorId, @now, @definitionKind, @definitionKey, @name, @description);
END;
GO

CREATE PROCEDURE config.AddDefinitionVersion
    @definitionKey NVARCHAR(100), @changeNote NVARCHAR(MAX) = NULL, @payloadText NVARCHAR(MAX) = NULL,
    @actorId UNIQUEIDENTIFIER, @versionRowId UNIQUEIDENTIFIER = NULL OUTPUT, @versionNumber INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    DECLARE @defEntity UNIQUEIDENTIFIER, @kind NVARCHAR(40);
    SELECT @defEntity = EntityId, @kind = DefinitionKind FROM config.vDefinition WHERE DefinitionKey = @definitionKey;
    IF @defEntity IS NULL THROW 50001, N'Unknown definition key.', 1;

    IF @kind LIKE N'Program.%'
    BEGIN
        IF @payloadText IS NULL THROW 50002, N'Program definitions require a payload.', 1;
        EXEC compliance.ValidateProgramFacts @payloadText;
    END
    ELSE IF @payloadText IS NOT NULL
        THROW 50003, N'Only program definitions carry PayloadText (decision 78).', 1;

    SELECT @versionNumber = ISNULL(MAX(VersionNumber), 0) + 1 FROM config.vDefinitionVersion WHERE DefinitionEntityId = @defEntity;
    DECLARE @out TABLE (RowId UNIQUEIDENTIFIER);
    INSERT config.DefinitionVersion (EntityId, CreatedBy, CreatedAt, ModifiedBy, ModifiedAt, DefinitionEntityId, VersionNumber, Status, ChangeNote, PayloadText, PayloadHash)
    OUTPUT inserted.RowId INTO @out
    VALUES (NEWID(), @actorId, @now, @actorId, @now, @defEntity, @versionNumber, N'Draft', @changeNote, @payloadText,
            CASE WHEN @payloadText IS NULL THEN NULL ELSE HASHBYTES('SHA2_256', @payloadText) END);
    SELECT @versionRowId = RowId FROM @out;
END;
GO

CREATE PROCEDURE config.AddCharacteristic
    @definitionKey NVARCHAR(100), @versionNumber INT, @characteristicKey NVARCHAR(100), @name NVARCHAR(200),
    @dataType NVARCHAR(20), @unitCode NVARCHAR(20) = NULL, @base NVARCHAR(20) = NULL, @isRequired BIT = 0,
    @allowedValuesJson NVARCHAR(MAX) = NULL, @isCatalogueFact BIT = 0, @displayOrder INT = 0, @actorId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    DECLARE @versionRowId UNIQUEIDENTIFIER, @status NVARCHAR(20);
    SELECT @versionRowId = dv.RowId, @status = dv.Status
    FROM config.vDefinitionVersion dv JOIN config.vDefinition d ON d.EntityId = dv.DefinitionEntityId
    WHERE d.DefinitionKey = @definitionKey AND dv.VersionNumber = @versionNumber AND d.DefinitionKind LIKE N'CharacteristicSchema.%';
    IF @versionRowId IS NULL THROW 50004, N'Unknown characteristic-schema version.', 1;
    IF @status <> N'Draft' THROW 50005, N'Characteristics may be added to Draft versions only.', 1;
    IF @allowedValuesJson IS NOT NULL AND ISJSON(@allowedValuesJson) <> 1 THROW 50006, N'AllowedValuesJson is not valid JSON.', 1;

    INSERT config.CharacteristicDefinition (EntityId, CreatedBy, CreatedAt, ModifiedBy, ModifiedAt, DefinitionVersionRowId, CharacteristicKey, Name,
                                            DataType, UnitCode, Base, IsRequired, AllowedValuesJson, IsCatalogueFact, DisplayOrder)
    VALUES (NEWID(), @actorId, @now, @actorId, @now, @versionRowId, @characteristicKey, @name,
            @dataType, @unitCode, @base, @isRequired, @allowedValuesJson, @isCatalogueFact, @displayOrder);
END;
GO

/* Approve and make effective. Retires the prior effective version. Approver must differ from
   the author (the segregation rule of §2.2, hard-coded here rather than a Program.SegregationRule). */
CREATE PROCEDURE config.ApproveDefinitionVersion
    @definitionKey NVARCHAR(100), @versionNumber INT, @approverActorId UNIQUEIDENTIFIER, @effectiveFrom DATETIMEOFFSET(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    SET @effectiveFrom = ISNULL(@effectiveFrom, @now);
    DECLARE @defEntity UNIQUEIDENTIFIER, @rowId UNIQUEIDENTIFIER, @createdBy UNIQUEIDENTIFIER, @status NVARCHAR(20);
    SELECT @defEntity = dv.DefinitionEntityId, @rowId = dv.RowId, @createdBy = dv.CreatedBy, @status = dv.Status
    FROM config.vDefinitionVersion dv JOIN config.vDefinition d ON d.EntityId = dv.DefinitionEntityId
    WHERE d.DefinitionKey = @definitionKey AND dv.VersionNumber = @versionNumber;
    IF @rowId IS NULL THROW 50007, N'Unknown definition version.', 1;
    IF @status <> N'Draft' THROW 50008, N'Only Draft versions can be approved.', 1;
    IF @createdBy = @approverActorId THROW 50009, N'Approver must differ from the author (segregation).', 1;

    UPDATE config.DefinitionVersion
       SET Status = N'Retired', EffectiveTo = @effectiveFrom, ModifiedBy = @approverActorId, ModifiedAt = @now
     WHERE DefinitionEntityId = @defEntity AND IsDeleted = 0 AND Status = N'Effective' AND EffectiveTo IS NULL;

    UPDATE config.DefinitionVersion
       SET Status = N'Effective', EffectiveFrom = @effectiveFrom, ApprovedBy = @approverActorId, ApprovedAt = @now,
           ModifiedBy = @approverActorId, ModifiedAt = @now
     WHERE RowId = @rowId;
END;
GO

CREATE PROCEDURE asset.AddAsset
    @name NVARCHAR(200), @assetTypeCode NVARCHAR(40), @templateDefinitionKey NVARCHAR(100),
    @actorId UNIQUEIDENTIFIER, @entityId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    DECLARE @template UNIQUEIDENTIFIER;
    SELECT @template = EntityId FROM config.vDefinition WHERE DefinitionKey = @templateDefinitionKey AND DefinitionKind = N'CharacteristicSchema.AssetTemplate';
    IF @template IS NULL THROW 50020, N'Unknown asset template.', 1;
    SET @entityId = NEWID();
    INSERT asset.AssetRegistry (EntityId) VALUES (@entityId);
    INSERT asset.Asset (EntityId, ValidFrom, CreatedBy, CreatedAt, ModifiedBy, ModifiedAt, AssetTypeCode, Name, TemplateDefinitionEntityId)
    VALUES (@entityId, @now, @actorId, @now, @actorId, @now, @assetTypeCode, @name, @template);
END;
GO

/* Enter a characteristic value against the asset's effective template version, typed per the
   definition. Closes the prior current row for the same characteristic key.                 */
CREATE PROCEDURE asset.SetCharacteristicValue
    @assetName NVARCHAR(200), @characteristicKey NVARCHAR(100),
    @textValue NVARCHAR(400) = NULL, @integerValue BIGINT = NULL, @decimalValue DECIMAL(28,10) = NULL,
    @booleanValue BIT = NULL, @dateTimeValue DATETIMEOFFSET(7) = NULL, @referenceEntityId UNIQUEIDENTIFIER = NULL,
    @actorId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    DECLARE @host UNIQUEIDENTIFIER, @template UNIQUEIDENTIFIER;
    SELECT @host = EntityId, @template = TemplateDefinitionEntityId FROM asset.vAsset WHERE Name = @assetName;
    IF @host IS NULL THROW 50021, N'Unknown asset.', 1;

    DECLARE @cdRowId UNIQUEIDENTIFIER, @dataType NVARCHAR(20), @allowed NVARCHAR(MAX);
    SELECT @cdRowId = cd.RowId, @dataType = cd.DataType, @allowed = cd.AllowedValuesJson
    FROM config.vCharacteristicDefinition cd
    JOIN config.vEffectiveDefinitionVersion dv ON dv.RowId = cd.DefinitionVersionRowId
    WHERE dv.DefinitionEntityId = @template AND cd.CharacteristicKey = @characteristicKey;
    IF @cdRowId IS NULL THROW 50022, N'The asset''s effective template has no such characteristic.', 1;

    DECLARE @ok BIT = CASE @dataType
        WHEN N'Text'        THEN CASE WHEN @textValue IS NOT NULL THEN 1 ELSE 0 END
        WHEN N'Enumeration' THEN CASE WHEN @textValue IS NOT NULL THEN 1 ELSE 0 END
        WHEN N'Integer'     THEN CASE WHEN @integerValue IS NOT NULL THEN 1 ELSE 0 END
        WHEN N'Decimal'     THEN CASE WHEN @decimalValue IS NOT NULL THEN 1 ELSE 0 END
        WHEN N'Boolean'     THEN CASE WHEN @booleanValue IS NOT NULL THEN 1 ELSE 0 END
        WHEN N'DateTime'    THEN CASE WHEN @dateTimeValue IS NOT NULL THEN 1 ELSE 0 END
        WHEN N'Reference'   THEN CASE WHEN @referenceEntityId IS NOT NULL THEN 1 ELSE 0 END END;
    IF @ok <> 1 THROW 50023, N'Value column does not match the characteristic DataType.', 1;
    IF @dataType = N'Enumeration' AND @allowed IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM OPENJSON(@allowed) WHERE [value] = @textValue)
        THROW 50024, N'Value is not in the enumeration''s allowed values.', 1;

    /* close the prior current value for the same key (any template version) */
    UPDATE cv SET ValidTo = @now, ModifiedBy = @actorId, ModifiedAt = @now
    FROM asset.CharacteristicValue cv
    JOIN config.CharacteristicDefinition cd ON cd.RowId = cv.CharacteristicDefinitionRowId
    JOIN config.DefinitionVersion dv ON dv.RowId = cd.DefinitionVersionRowId
    WHERE cv.HostEntityId = @host AND cv.IsDeleted = 0 AND cv.ValidTo IS NULL
      AND dv.DefinitionEntityId = @template AND cd.CharacteristicKey = @characteristicKey;

    INSERT asset.CharacteristicValue (EntityId, ValidFrom, CreatedBy, CreatedAt, ModifiedBy, ModifiedAt, HostEntityId, CharacteristicDefinitionRowId,
                                      TextValue, IntegerValue, DecimalValue, BooleanValue, DateTimeValue, ReferenceEntityId)
    VALUES (NEWID(), @now, @actorId, @now, @actorId, @now, @host, @cdRowId,
            @textValue, @integerValue, @decimalValue, @booleanValue, @dateTimeValue, @referenceEntityId);
END;
GO

/* Preview run (§12.4): writes the run row only; returns the scoped subjects. */
CREATE PROCEDURE compliance.RunRulePreview
    @ruleDefinitionKey NVARCHAR(100), @actorId UNIQUEIDENTIFIER, @at DATETIMEOFFSET(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    SET @at = ISNULL(@at, @now);
    DECLARE @ruleRowId UNIQUEIDENTIFIER, @payload NVARCHAR(MAX);
    SELECT @ruleRowId = dv.RowId, @payload = dv.PayloadText
    FROM config.vEffectiveDefinitionVersion dv JOIN config.vDefinition d ON d.EntityId = dv.DefinitionEntityId
    WHERE d.DefinitionKey = @ruleDefinitionKey AND d.DefinitionKind = N'Program.ObligationRule';
    IF @ruleRowId IS NULL THROW 50030, N'No effective obligation rule with that key.', 1;

    EXEC compliance.ValidateProgramFacts @payload;   /* re-checked at run time: the catalogue may have changed */

    DECLARE @predicate NVARCHAR(MAX) = JSON_QUERY(@payload, '$.predicate');
    DECLARE @runId UNIQUEIDENTIFIER = NEWID();
    INSERT compliance.RuleEvaluationRun (RunId, RuleDefinitionVersionRowId, Mode, [Trigger], StartedAt, ActorId)
    VALUES (@runId, @ruleRowId, N'Preview', N'Manual', @now, @actorId);

    DECLARE @scoped TABLE (SubjectKind NVARCHAR(40), SubjectEntityId UNIQUEIDENTIFIER, SubjectName NVARCHAR(200));
    INSERT @scoped
    SELECT N'Asset', a.EntityId, a.Name
    FROM asset.vAsset a
    WHERE EXISTS (SELECT 1 FROM OPENJSON(@payload, '$.subjectKinds') k WHERE k.[value] = N'Asset')
      AND compliance.fEvaluate(a.EntityId, @predicate, @at) = 1;

    UPDATE compliance.RuleEvaluationRun SET CompletedAt = SYSDATETIMEOFFSET(), SubjectsScoped = (SELECT COUNT(*) FROM @scoped) WHERE RunId = @runId;

    SELECT RunId = @runId, RuleDefinitionVersionRowId = @ruleRowId, SubjectKind, SubjectEntityId, SubjectName
    FROM @scoped ORDER BY SubjectName;
END;
GO
