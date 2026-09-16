-- #170 (2026-09-16): the transmission voltage classes the group names its lines by (the owner: 138 kV lines start with a 1,
-- 230 kV with a 2, 345 kV with a 3; line 0012 is a 69 kV line). A primary asset carries one as its VoltageClassCode.
-- Idempotent through ref.VoltageClass_Upsert; more classes are added here when the group names them.
IF OBJECT_ID(N'[ref].[VoltageClass_Upsert]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
EXEC [ref].[VoltageClass_Upsert] @VoltageClassCode = N'69kV',  @NominalKv = 69,  @IsTransmission = 1, @DisplayOrder = 10, @ActorId = @actor;
EXEC [ref].[VoltageClass_Upsert] @VoltageClassCode = N'138kV', @NominalKv = 138, @IsTransmission = 1, @DisplayOrder = 20, @ActorId = @actor;
EXEC [ref].[VoltageClass_Upsert] @VoltageClassCode = N'230kV', @NominalKv = 230, @IsTransmission = 1, @DisplayOrder = 30, @ActorId = @actor;
EXEC [ref].[VoltageClass_Upsert] @VoltageClassCode = N'345kV', @NominalKv = 345, @IsTransmission = 1, @DisplayOrder = 40, @ActorId = @actor;
GO
