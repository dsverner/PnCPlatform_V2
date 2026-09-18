-- #192 (2026-09-18): the drift of a draft from its basis, for the record screen and the work item. Two result sets: the
-- rows of process.fBasisDrift, then one row naming the basis (its request, its state), whether a frozen basis exists,
-- and how many rows need attention (take, agree, conflict). @DeviceEntityId is the read's subject for the API's scope
-- (ConfigurationFile.Read on the device), as SetParsedSetting names it for a write.
CREATE PROCEDURE [process].[BasisDrift]
    @RevisionRowId UNIQUEIDENTIFIER,
    @DeviceEntityId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT [SettingCode], [GroupNumber], [SettingName], [ThenValue], [NowValue], [MineValue], [Outcome]
    FROM [process].[fBasisDrift](@RevisionRowId) ORDER BY [SettingCode], [GroupNumber];
    DECLARE @basis UNIQUEIDENTIFIER = [process].[fBasisRevision](@RevisionRowId);
    SELECT sr.[BasedOnWorkRequestTitle] AS [BasisTitle], sr.[BasedOnGridState] AS [BasisGridState],
           [BasisRevisionRowId] = @basis,
           [HasFrozenBasis] = CASE WHEN EXISTS (SELECT 1 FROM [document].[vFile] f WHERE f.[RevisionRowId] = @RevisionRowId AND f.[FileRole] = N'Attachment' AND f.[FileName] LIKE N'basis-%.json') THEN 1 ELSE 0 END,
           [DriftCount] = (SELECT COUNT(*) FROM [process].[fBasisDrift](@RevisionRowId) WHERE [Outcome] IN (N'take', N'agree', N'conflict'))
    FROM [document].[vSettingsRecord] sr WHERE sr.[RevisionRowId] = @RevisionRowId;
END;
GO
