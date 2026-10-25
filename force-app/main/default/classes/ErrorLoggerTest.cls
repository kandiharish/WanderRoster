@IsTest
private class ErrorLoggerTest {

    @IsTest
    static void exceptionIsLoggedWithTypeAndRecord() {
        Trip__c trip = new Trip__c(
            Purpose__c = 'Training', Trip_Type__c = 'Domestic', Destination_City__c = 'Pune',
            Start_Date__c = Date.today().addDays(3), End_Date__c = Date.today().addDays(4), Estimated_Cost__c = 1000
        );
        insert trip;

        Test.startTest();
        try {
            Integer zero = 0;
            Integer boom = 1 / zero;
        } catch (MathException ex) {
            ErrorLogger.log('ErrorLoggerTest', ex, trip.Id);
        }
        Test.stopTest();

        Error_Log__c log = [SELECT Source__c, Message__c, Record_Id__c, Severity__c FROM Error_Log__c WITH SYSTEM_MODE];
        Assert.areEqual('ErrorLoggerTest', log.Source__c);
        Assert.areEqual('Error', log.Severity__c);
        Assert.areEqual(trip.Id, log.Record_Id__c);
        Assert.isTrue(log.Message__c.startsWith('System.MathException'), log.Message__c);
    }

    @IsTest
    static void onlyFailedRowsAreLogged() {
        // The second trip breaks End_Date_Before_Start_Date, so only it fails.
        List<Trip__c> trips = new List<Trip__c>{
            new Trip__c(Purpose__c = 'Training', Trip_Type__c = 'Domestic', Destination_City__c = 'Pune',
                Start_Date__c = Date.today().addDays(3), End_Date__c = Date.today().addDays(4), Estimated_Cost__c = 1000),
            new Trip__c(Purpose__c = 'Training', Trip_Type__c = 'Domestic', Destination_City__c = 'Pune',
                Start_Date__c = Date.today().addDays(4), End_Date__c = Date.today().addDays(3), Estimated_Cost__c = 1000)
        };

        Test.startTest();
        Integer failed = ErrorLogger.logFailures('ErrorLoggerTest', Database.insert(trips, false), trips);
        Test.stopTest();

        Assert.areEqual(1, failed);
        Error_Log__c log = [SELECT Message__c FROM Error_Log__c WITH SYSTEM_MODE];
        Assert.isTrue(log.Message__c.contains('FIELD_CUSTOM_VALIDATION_EXCEPTION'), log.Message__c);
    }

    @IsTest
    static void warningAndLongMessagesAreHandled() {
        Test.startTest();
        ErrorLogger.log(null, 'x'.repeat(40000), null, ErrorLogger.WARNING);
        Test.stopTest();

        Error_Log__c log = [SELECT Source__c, Message__c, Severity__c FROM Error_Log__c WITH SYSTEM_MODE];
        Assert.areEqual('Unknown', log.Source__c, 'A missing source must not stop the log');
        Assert.areEqual('Warning', log.Severity__c);
        Assert.areEqual(32000, log.Message__c.length(), 'Messages are trimmed to fit the field');
    }
}
