-- #192 (2026-09-18): the revision a draft is measured against. The newest live BasedOn link names the basis; when that
-- revision is withdrawn (Superseded/Withdrawn, deleted) or its request cancelled, the device's in-service revision stands
-- in — the second change then re-bases onto what is actually in service. NULL when the draft is based on nothing.
CREATE FUNCTION [process].[fBasisRevision] (@RevisionRowId UNIQUEIDENTIFIER)
RETURNS UNIQUEIDENTIFIER
AS
BEGIN
    DECLARE @linked UNIQUEIDENTIFIER = (SELECT TOP (1) l.[SubjectEntityId] FROM [document].[RevisionLink] l
                                        WHERE l.[RevisionRowId] = @RevisionRowId AND l.[LinkKind] = N'BasedOn' AND l.[ValidTo] IS NULL AND l.[IsDeleted] = 0 ORDER BY l.[RowSeq] DESC);
    IF @linked IS NULL RETURN NULL;
    DECLARE @live BIT = CASE WHEN EXISTS (
        SELECT 1 FROM [document].[Revision] br JOIN [document].[ConfigurationFile] bcf ON bcf.[RevisionRowId] = br.[RowId] AND bcf.[IsDeleted] = 0
        WHERE br.[RowId] = @linked AND br.[IsDeleted] = 0 AND br.[Status] NOT IN (N'Superseded', N'Withdrawn')
          AND NOT EXISTS (SELECT 1 FROM [document].[vSettingsRecord] sr JOIN [process].[WorkflowInstance] wi
                            ON wi.[IsDeleted] = 0 AND wi.[SubjectKind] = N'WorkRequest' AND wi.[SubjectEntityId] = sr.[WorkRequestEntityId] AND wi.[CurrentState] = N'Cancelled'
                          WHERE sr.[RevisionRowId] = @linked)) THEN 1 ELSE 0 END;
    IF @live = 1 RETURN @linked;
    DECLARE @device UNIQUEIDENTIFIER = (SELECT [DeviceEntityId] FROM [document].[ConfigurationFile] WHERE [RevisionRowId] = @RevisionRowId AND [IsDeleted] = 0);
    RETURN (SELECT TOP (1) sr.[RevisionRowId] FROM [document].[vSettingsRecord] sr WHERE sr.[DeviceEntityId] = @device AND sr.[GridState] = N'Active' ORDER BY sr.[RowSeq] DESC);
END;
GO
