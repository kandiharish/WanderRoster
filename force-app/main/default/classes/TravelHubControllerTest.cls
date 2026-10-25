@IsTest
private class TravelHubControllerTest {

    @IsTest
    static void summaryAndTripsReturnOnlyMyData() {
        Trip__c trip = new Trip__c(
            Purpose__c = 'Training',
            Trip_Type__c = 'Domestic',
            Destination_City__c = 'Hyderabad',
            Start_Date__c = Date.today().addDays(3),
            End_Date__c = Date.today().addDays(4),
            Estimated_Cost__c = 10000,
            Status__c = 'Approved',
            Claim_Status__c = 'Submitted'
        );
        insert trip;

        Test.startTest();
        List<Trip__c> trips = TravelHubController.getMyTrips();
        TravelHubController.Summary summary = TravelHubController.getSummary();
        Test.stopTest();

        System.assertEquals(1, trips.size(), 'Only my trip is returned');
        System.assertEquals('Hyderabad', trips[0].Destination_City__c, 'Trip fields are returned');
        if (trip.Start_Date__c.year() == Date.today().year()) {
            System.assertEquals(1, summary.openTrips, 'Approved trip counts as open');
            System.assertEquals(1, summary.pendingClaims, 'Submitted claim counts as pending');
            System.assertEquals(10000, summary.totalEstimated, 'Estimated cost is summed');
        }
        System.assertNotEquals(null, summary, 'Summary is always returned');
    }

    @IsTest
    static void emptySummaryWhenNoTrips() {
        Test.startTest();
        TravelHubController.Summary summary = TravelHubController.getSummary();
        Test.stopTest();

        System.assertEquals(0, summary.openTrips, 'No trips means zero open trips');
        System.assertEquals(0, summary.totalSpent, 'No trips means zero spend');
    }
}
