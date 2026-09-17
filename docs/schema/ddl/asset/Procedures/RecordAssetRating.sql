-- #173 (2026-09-17): the one way a person records a Facility Rating. The sibling of [asset].[RecordClassification], and
-- the same shape: one current value per subject and key — here per asset, rating kind and season (UX_AssetRating_AssetKindSeason)
-- — a new value revises the current row, and an empty value withdraws it.
-- Why it exists: ratings belong only to the asset types that carry one. The owner, 2026-09-17, looking at the Bathurst
-- 230 kV bus page: a bus has no rating, and the page must not offer one. ref.AssetType.CarriesRating says which types do
-- (Line and Transformer — PRC-023 R1's criteria 1, 2 and 13 measure a circuit's rating), and the rule is enforced here,
-- not only hidden on the screen (50235).
-- The generated CRUD (asset.AssetRating_Add / _Revise / _SoftDelete) stays as it is: the migration and the future ratings
-- connector write through it, with their own SourceSystem. Everything a person enters comes through this procedure, which
-- writes SourceSystem = 'Recorded' by the column's default.
-- Over HTTP: Asset.Modify on the asset.
CREATE PROCEDURE [asset].[RecordAssetRating]
    @AssetEntityId UNIQUEIDENTIFIER,
    @RatingKind NVARCHAR(30),                  -- Continuous, FourHour, FifteenMinute, PracticalLimitation
    @Season NVARCHAR(10),                      -- Summer, Winter, Spring, Fall, All
    @Amperes DECIMAL(12,2) = NULL,             -- NULL withdraws the current value
    @Source NVARCHAR(200) = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    DECLARE @assetType NVARCHAR(40), @carriesRating BIT;
    SELECT @assetType = a.[AssetTypeCode], @carriesRating = t.[CarriesRating]
    FROM [asset].[vAsset] a JOIN [ref].[AssetType] t ON t.[AssetTypeCode] = a.[AssetTypeCode]
    WHERE a.[EntityId] = @AssetEntityId;
    IF @assetType IS NULL THROW 50236, N'asset.RecordAssetRating: the asset is not a current asset.', 1;
    IF ISNULL(@carriesRating, 0) = 0   -- NULL and 0 both mean no: the column is nullable (a system-versioned table cannot take a NOT NULL one)
    BEGIN
        DECLARE @m1 NVARCHAR(400) = N'asset.RecordAssetRating: a ' + @assetType + N' carries no rating (ref.AssetType.CarriesRating is 0 for it).';
        THROW 50235, @m1, 1;
    END

    SET @EntityId = (SELECT TOP (1) [EntityId] FROM [asset].[AssetRating]
                     WHERE [AssetEntityId] = @AssetEntityId AND [RatingKind] = @RatingKind AND [Season] = @Season
                       AND [ValidTo] IS NULL AND [IsDeleted] = 0
                     ORDER BY [RowSeq] DESC);
    BEGIN TRANSACTION;
    IF @Amperes IS NULL
    BEGIN
        -- withdrawn: the current row closes in belief (the history keeps it); nothing to add
        IF @EntityId IS NOT NULL EXEC [asset].[AssetRating_SoftDelete] @EntityId = @EntityId, @ActorId = @ActorId;
    END
    ELSE IF @EntityId IS NULL
        EXEC [asset].[AssetRating_Add] @AssetEntityId = @AssetEntityId, @RatingKind = @RatingKind, @Season = @Season, @Amperes = @Amperes,
             @Source = @Source, @Notes = @Notes, @ActorId = @ActorId, @EntityId = @EntityId OUTPUT;
    ELSE
        EXEC [asset].[AssetRating_Revise] @EntityId = @EntityId, @AssetEntityId = @AssetEntityId, @RatingKind = @RatingKind, @Season = @Season, @Amperes = @Amperes,
             @Source = @Source, @Notes = @Notes, @ActorId = @ActorId;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"rating-recorded","kind":"', STRING_ESCAPE(@RatingKind, 'json'),
                                           N'","season":"', STRING_ESCAPE(@Season, 'json'),
                                           N'","amperes":', CASE WHEN @Amperes IS NULL THEN N'null' ELSE CONVERT(NVARCHAR(40), @Amperes) END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'asset', @SubjectTable = N'AssetRating', @SubjectEntityId = @AssetEntityId, @SubjectRowId = @EntityId,
         @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
