-- SCHEMA-DESIGN §10.1 (decision 42), §10.7 (149), §11.7 (158); PROCEDURES.md #20.
-- Writes the acceptance of a record (bi-temporal: an acceptance is an approval). Tester ≠ acceptor
-- through security.CheckSegregation (Test / Accept on a Record; the tester is PerformedByActorId).
-- For a record of kind CommissioningPackage, acceptance is the commissioning sign-off and cascades
-- to every member record not already accepted, under the package's authority (the member
-- acceptances cite the package in Reason). Implementation choice (STEPS.md step 10): the cascade
-- does not re-evaluate segregation per member — the package acceptance carried it.
CREATE PROCEDURE [record].[AcceptRecord]
    @RecordEntityId UNIQUEIDENTIFIER,
    @AcceptanceStatus NVARCHAR(20) = N'Accepted',
    @Reason NVARCHAR(400) = NULL,
    @AcceptedAt DATETIMEOFFSET(7) = NULL,
    @OverrideReason NVARCHAR(400) = NULL,
    @OverrideApprovedByActorId UNIQUEIDENTIFIER = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @AcceptanceEntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @MembersAccepted INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @AcceptedAt = ISNULL(@AcceptedAt, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF @AcceptanceStatus NOT IN (N'Accepted', N'Rejected', N'Withdrawn') THROW 50320, N'record.AcceptRecord: AcceptanceStatus is Accepted, Rejected or Withdrawn (§10.1).', 1;

    DECLARE @kind NVARCHAR(40), @tester UNIQUEIDENTIFIER;
    SELECT @kind = [RecordKindCode], @tester = [PerformedByActorId] FROM [record].[vRecord] WHERE [EntityId] = @RecordEntityId;
    IF @kind IS NULL THROW 50321, N'record.AcceptRecord: the record is not current.', 1;
    IF EXISTS (SELECT 1 FROM [record].[vAcceptance] WHERE [RecordEntityId] = @RecordEntityId AND [AcceptanceStatus] = N'Accepted') AND @AcceptanceStatus = N'Accepted'
        THROW 50322, N'record.AcceptRecord: the record is already accepted.', 1;

    SET @MembersAccepted = 0;
    BEGIN TRANSACTION;
    IF @AcceptanceStatus = N'Accepted'
        EXEC [security].[CheckSegregation] @ActionA = N'Test', @ActionB = N'Accept', @SubjectKind = N'Record', @SubjectEntityId = @RecordEntityId,
             @ActorA = @tester, @ActorB = @ActorId, @OverrideReason = @OverrideReason, @OverrideApprovedByActorId = @OverrideApprovedByActorId, @OccurredAt = @AcceptedAt;

    EXEC [record].[Acceptance_Add] @RecordEntityId = @RecordEntityId, @AcceptedByActorId = @ActorId, @AcceptedAt = @AcceptedAt, @AcceptanceStatus = @AcceptanceStatus, @Reason = @Reason,
         @ValidFrom = @AcceptedAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @AcceptanceEntityId OUTPUT;
    EXEC [audit].[LogAction] @ActionKindCode = N'Approval', @SubjectSchema = N'record', @SubjectTable = N'Record', @SubjectEntityId = @RecordEntityId, @ActorId = @ActorId, @OccurredAt = @AcceptedAt;

    IF @kind = N'CommissioningPackage' AND @AcceptanceStatus = N'Accepted'
    BEGIN
        DECLARE @member UNIQUEIDENTIFIER, @cascadeReason NVARCHAR(400) = LEFT(CONCAT(N'Accepted with commissioning package ', CONVERT(NVARCHAR(36), @RecordEntityId), N' (§10.7)'), 400);
        DECLARE members CURSOR LOCAL FAST_FORWARD FOR
            SELECT i.[MemberRecordEntityId] FROM [record].[vCommissioningPackageItem] i
            WHERE i.[PackageEntityId] = @RecordEntityId
              AND NOT EXISTS (SELECT 1 FROM [record].[vAcceptance] a WHERE a.[RecordEntityId] = i.[MemberRecordEntityId] AND a.[AcceptanceStatus] = N'Accepted')
            ORDER BY i.[Sequence];
        OPEN members; FETCH NEXT FROM members INTO @member;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC [record].[Acceptance_Add] @RecordEntityId = @member, @AcceptedByActorId = @ActorId, @AcceptedAt = @AcceptedAt, @AcceptanceStatus = N'Accepted', @Reason = @cascadeReason,
                 @ValidFrom = @AcceptedAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId;
            SET @MembersAccepted += 1;
            FETCH NEXT FROM members INTO @member;
        END;
        CLOSE members; DEALLOCATE members;
    END;
    COMMIT TRANSACTION;
END;
GO
