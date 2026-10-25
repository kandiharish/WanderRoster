@IsTest
private class CurrencyRateRefreshTest {

    private class FxSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"base_code":"INR","rates":{"USD":0.012,"EUR":0.011,"GBP":0.0095,"AED":0.044,"SGD":0.016}}');
            return response;
        }
    }

    private class FxErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setBody('{}');
            return response;
        }
    }

    @IsTest
    static void refreshStoresRatesAsForeignToInr() {
        Test.setMock(HttpCalloutMock.class, new FxSuccessMock());

        Test.startTest();
        System.enqueueJob(new CurrencyRateRefreshQueueable());
        Test.stopTest();

        Currency_Rate__c usd = [SELECT Rate_To_INR__c FROM Currency_Rate__c WHERE Currency_Code__c = 'USD'];
        System.assertEquals(83.333333, usd.Rate_To_INR__c, '1 / 0.012 = 83.333333 INR per USD');
        System.assertEquals(5, [SELECT COUNT() FROM Currency_Rate__c], 'All five tracked currencies stored');
    }

    @IsTest
    static void parseIgnoresCurrenciesMissingFromResponse() {
        List<Currency_Rate__c> rates = CurrencyRateRefreshQueueable.parseRates(
            '{"rates":{"USD":0.012}}'
        );
        System.assertEquals(1, rates.size(), 'Only USD was in the response');
        System.assertEquals('USD', rates[0].Currency_Code__c);
    }

    @IsTest
    static void failedCalloutLeavesExistingRatesUnchanged() {
        Test.setMock(HttpCalloutMock.class, new FxErrorMock());

        Test.startTest();
        System.enqueueJob(new CurrencyRateRefreshQueueable());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Currency_Rate__c], 'A failed call must not write rates');
    }

    @IsTest
    static void schedulerQueuesTheRefresh() {
        Test.setMock(HttpCalloutMock.class, new FxSuccessMock());

        Test.startTest();
        new CurrencyRateRefreshScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(5, [SELECT COUNT() FROM Currency_Rate__c], 'Scheduled job should queue the refresh');
    }
}