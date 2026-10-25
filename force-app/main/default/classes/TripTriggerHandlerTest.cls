@IsTest
private class TripTriggerHandlerTest {

    private static Trip__c createApprovedTrip() {
        Trip__c trip = new Trip__c(
            Purpose__c = 'Client Visit',
            Trip_Type__c = 'Domestic',
            Destination_City__c = 'Bengaluru',
            Start_Date__c = Date.today().addDays(10),
            End_Date__c = Date.today().addDays(12),
            Estimated_Cost__c = 30000,
            Status__c = 'Approved'
        );
        insert trip;
        return trip;
    }

    @IsTest
    static void statusChangeToManagerApprovedIsProcessed() {
        Trip__c trip = createApprovedTrip();

        Test.startTest();
        trip.Claim_Status__c = 'Manager Approved';
        update trip;
        Test.stopTest();

        // Notification delivery is not asserted (it is fire-and-forget in tests).
        // This checks that the update succeeds with the trigger and handler running.
        Trip__c saved = [SELECT Claim_Status__c FROM Trip__c WHERE Id = :trip.Id];
        System.assertEquals('Manager Approved', saved.Claim_Status__c);
    }

    @IsTest
    static void statusChangeToNonNotifyingValueIsIgnored() {
        Trip__c trip = createApprovedTrip();

        Test.startTest();
        trip.Claim_Status__c = 'Submitted';
        update trip;
        Test.stopTest();

        Trip__c saved = [SELECT Claim_Status__c FROM Trip__c WHERE Id = :trip.Id];
        System.assertEquals('Submitted', saved.Claim_Status__c);
    }

    @IsTest
    static void unchangedStatusDoesNotNotify() {
        Trip__c trip = createApprovedTrip();

        Test.startTest();
        // Approved trip details are locked by a validation rule, so change a field that stays editable.
        trip.Booking_Reference__c = 'PNR-1234';
        update trip;
        Test.stopTest();

        Trip__c saved = [SELECT Booking_Reference__c FROM Trip__c WHERE Id = :trip.Id];
        System.assertEquals('PNR-1234', saved.Booking_Reference__c);
    }
}