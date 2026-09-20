-- #213 (2026-09-20): the one way a winding's tap is landed. The owner: "Every CT has discrete tap capabilities which should
-- be listed"; the ratio in use is which tap the wires are on, a setting of the protection in the CTR sense. The tap must be a
-- current tap of THIS winding (50274 otherwise); the winding is revised (bi-temporal, audited) with TapInUseEntityId and its
-- RatioInUse set from the tap's ratio, so scheme.vSchemeSource and every list keep reading RatioInUse. @TapEntityId NULL
-- clears the tap and leaves the text ratio as it is (a winding whose taps are not recorded keeps a typed ratio).
--   50273 no current winding with that id   50274 the tap is not a current tap of the winding
CREATE PROCEDURE [asset].[SetWindingTap]
    @WindingEntityId UNIQUEIDENTIFIER,
    @TapEntityId UNIQUEIDENTIFIER = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @RowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @asset UNIQUEIDENTIFIER, @no TINYINT, @code NVARCHAR(20), @purpose NVARCHAR(20), @taps NVARCHAR(200), @ratio NVARCHAR(40),
            @class NVARCHAR(40), @burden NVARCHAR(40), @knee DECIMAL(10,2), @sec NVARCHAR(20), @conn NVARCHAR(20), @notes NVARCHAR(400);
    SELECT @asset = [AssetEntityId], @no = [WindingNo], @code = [Code], @purpose = [Purpose], @taps = [RatioTaps], @ratio = [RatioInUse],
           @class = [AccuracyClass], @burden = [RatedBurden], @knee = [KneePointVoltageV], @sec = [RatedSecondary], @conn = [Connection], @notes = [Notes]
    FROM [asset].[InstrumentWinding] WHERE [EntityId] = @WindingEntityId AND [ValidTo] IS NULL AND [IsDeleted] = 0;
    IF @asset IS NULL THROW 50273, N'asset.SetWindingTap: no current secondary winding with that id.', 1;
    IF @TapEntityId IS NOT NULL
    BEGIN
        DECLARE @tapRatio NVARCHAR(40);
        SELECT @tapRatio = [Ratio] FROM [asset].[WindingTap] WHERE [EntityId] = @TapEntityId AND [WindingEntityId] = @WindingEntityId AND [ValidTo] IS NULL AND [IsDeleted] = 0;
        IF @tapRatio IS NULL THROW 50274, N'asset.SetWindingTap: the tap is not a current tap of this winding.', 1;
        SET @ratio = @tapRatio;
    END
    EXEC [asset].[InstrumentWinding_Revise] @EntityId = @WindingEntityId, @AssetEntityId = @asset, @WindingNo = @no, @Code = @code, @Purpose = @purpose,
         @RatioTaps = @taps, @RatioInUse = @ratio, @AccuracyClass = @class, @RatedBurden = @burden, @KneePointVoltageV = @knee, @RatedSecondary = @sec,
         @Connection = @conn, @Notes = @notes, @TapInUseEntityId = @TapEntityId, @ActorId = @ActorId, @RowId = @RowId OUTPUT;
END;
GO
