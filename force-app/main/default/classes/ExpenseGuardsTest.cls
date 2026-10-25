@IsTest
private class ExpenseGuardsTest {

    // Covers duplicate detection, the delete lock, receipt tracking and the
    // daily claim reminder batch. Runs as the admin (G2).

    private static Trip__c createApprovedTrip() {
        Trip__c trip = new Trip__c(
            Purpose__c = 'Client Visit',
            Trip_Type__c = 'Domestic',
            Destination_City__c = 'Pune',
            Start_Date__c = Date.today().addDays(10),
            End_Date__c = Date.today().addDays(12),
            Estimated_Cost__c = 20000,
            Status__c = 'Approved',
            Claim_Status__c = 'Not Submitted'
        );
        insert trip;
        return trip;
    }

    private static Expense__c newMeal(Trip__c trip, Decimal amount) {
        return new Expense__c(
            Trip__c = trip.Id,
            Category__c = 'Meals',
            Expense_Date__c = trip.Start_Date__c,
            Amount__c = amount,
            Currency_Code__c = 'INR'
        );
    }

    @IsTest
    static void secondIdenticalExpenseIsFlaggedAsDuplicate() {
        Trip__c trip = createApprovedTrip();
        Expense__c first = newMeal(trip, 700);
        insert first;

        Test.startTest();
        Expense__c second = newMeal(trip, 700);
        Expense__c different = newMeal(trip, 450);
        insert new List<Expense__c>{ second, different };
        Test.stopTest();

        Map<Id, Expense__c> saved = new Map<Id, Expense__c>([
            SELECT Possible_Duplicate__c FROM Expense__c
        ]);
        System.assertEquals(false, saved.get(first.Id).Possible_Duplicate__c, 'The original is not a duplicate');
        System.assertEquals(true, saved.get(second.Id).Possible_Duplicate__c, 'Same date, category and amount is flagged');
        System.assertEquals(false, saved.get(different.Id).Possible_Duplicate__c, 'A different amount is not flagged');
    }

    @IsTest
    static void deleteBlockedAfterClaimSubmitted() {
        Trip__c trip = createApprovedTrip();
        Expense__c exp = newMeal(trip, 500);
        insert exp;
        trip.Claim_Status__c = 'Submitted';
        update trip;

        Test.startTest();
        Database.DeleteResult result = Database.delete(exp, false);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Delete must be blocked once the claim is submitted');
        System.assert(result.getErrors()[0].getMessage().contains('cannot be deleted'), 'Clear error message expected');
    }

    @IsTest
    static void deleteAllowedBeforeClaimSubmitted() {
        Trip__c trip = createApprovedTrip();
        Expense__c exp = newMeal(trip, 500);
        insert exp;

        Test.startTest();
        delete exp;
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Expense__c WHERE Id = :exp.Id], 'Draft claim expenses can be deleted');
    }

    @IsTest
    static void attachingAFileTicksHasReceipt() {
        Trip__c trip = createApprovedTrip();
        Expense__c exp = newMeal(trip, 500);
        insert exp;

        Test.startTest();
        insert new ContentVersion(
            Title = 'Dinner receipt',
            PathOnClient = 'receipt.pdf',
            VersionData = Blob.valueOf('receipt'),
            FirstPublishLocationId = exp.Id
        );
        Test.stopTest();

        System.assertEquals(true, [SELECT Has_Receipt__c FROM Expense__c WHERE Id = :exp.Id].Has_Receipt__c,
            'Has Receipt is ticked when a file is attached');
    }

    @IsTest
    static void batchCompletesTripAndCreatesReminder() {
        Trip__c trip = createApprovedTrip();
        ClaimReminderBatch.runDate = trip.End_Date__c.addDays(7);

        Test.startTest();
        Database.executeBatch(new ClaimReminderBatch());
        Test.stopTest();

        System.assertEquals('Completed', [SELECT Status__c FROM Trip__c WHERE Id = :trip.Id].Status__c,
            'A trip past its end date is marked Completed');
        List<Task> reminders = [SELECT OwnerId, Priority FROM Task WHERE WhatId = :trip.Id];
        System.assertEquals(1, reminders.size(), 'One reminder 7 days after the trip');
        System.assertEquals(UserInfo.getUserId(), reminders[0].OwnerId, 'Reminder goes to the trip owner');
        System.assertEquals('High', reminders[0].Priority, 'Reminder is high priority');
    }

    @IsTest
    static void noReminderWhenClaimAlreadySubmitted() {
        Trip__c trip = createApprovedTrip();
        trip.Claim_Status__c = 'Submitted';
        update trip;
        ClaimReminderBatch.runDate = trip.End_Date__c.addDays(7);

        Test.startTest();
        Database.executeBatch(new ClaimReminderBatch());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :trip.Id], 'No reminder once the claim is submitted');
    }

    @IsTest
    static void schedulerRegistersDailyJob() {
        Test.startTest();
        Id jobId = System.schedule('Test Claim Reminder', '0 0 7 * * ?', new ClaimReminderBatch());
        Test.stopTest();

        System.assertNotEquals(null, [SELECT Id FROM CronTrigger WHERE Id = :jobId], 'Daily job is scheduled');
    }
}
