@IsTest
private class AgentActionsTest {

    // Each test runs as a G2 test employee (Meals 1200, Hotel 4500 per night; receipts above 500 for Meals).

    @TestSetup
    static void setup() {
        insert new Currency_Rate__c(Name = 'US Dollar', Currency_Code__c = 'USD', Rate_To_INR__c = 80);
        TestUserFactory.createEmployee('G2 - Senior Associate', 'g2agent');
    }

    private static User employee() {
        return TestUserFactory.getEmployee('g2agent');
    }

    private static PolicyCheckAction.Result check(String category, Decimal amount, String code, Integer nights) {
        PolicyCheckAction.Request req = new PolicyCheckAction.Request();
        req.category = category;
        req.amount = amount;
        req.currencyCode = code;
        req.nights = nights;
        return PolicyCheckAction.check(new List<PolicyCheckAction.Request>{ req })[0];
    }

    @IsTest
    static void mealsWithinLimit() {
        System.runAs(employee()) {
            PolicyCheckAction.Result res = check('meals', 1000, null, null);
            System.assertEquals(true, res.withinPolicy, '1000 is within the 1200 meals limit');
            System.assertEquals(1200, res.limitInr, 'G2 meals limit');
            System.assertEquals(true, res.receiptRequired, 'Receipt needed above 500');
            System.assert(res.answer.startsWith('Yes.'), 'Positive answer');
        }
    }

    @IsTest
    static void hotelOverLimitUsesNights() {
        System.runAs(employee()) {
            PolicyCheckAction.Result res = check('Hotel', 10000, 'INR', 2);
            System.assertEquals(9000, res.limitInr, '4500 per night x 2 nights');
            System.assertEquals(false, res.withinPolicy, '10000 is above 9000');
            System.assert(res.answer.startsWith('No.'), 'Negative answer mentions justification');
        }
    }

    @IsTest
    static void foreignCurrencyIsConverted() {
        System.runAs(employee()) {
            PolicyCheckAction.Result res = check('taxi', 10, 'usd', null);
            System.assertEquals(800, res.amountInr, '10 USD at 80');
            System.assert(res.answer.contains('USD'), 'Answer shows the original currency');
        }
    }

    @IsTest
    static void unknownCategoryAndCurrencyGiveHelpfulAnswers() {
        System.runAs(employee()) {
            System.assert(check('spa', 100, null, null).answer.contains('could not match'), 'Unknown category');
            System.assert(check('Meals', 100, 'JPY', null).answer.contains('no exchange rate'), 'Unknown currency');
        }
    }

    @IsTest
    static void tripStatusSummary() {
        System.runAs(employee()) {
            System.assertEquals(0, MyTripStatusAction.getStatus(new List<MyTripStatusAction.Request>{ new MyTripStatusAction.Request() })[0].tripCount, 'No trips yet');

            insert new Trip__c(
                Purpose__c = 'Training', Trip_Type__c = 'Domestic', Destination_City__c = 'Kochi',
                Start_Date__c = Date.today().addDays(2), End_Date__c = Date.today().addDays(3),
                Estimated_Cost__c = 8000
            );
            MyTripStatusAction.Result res = MyTripStatusAction.getStatus(new List<MyTripStatusAction.Request>{ new MyTripStatusAction.Request() })[0];
            System.assertEquals(1, res.tripCount, 'One trip');
            System.assert(res.summary.contains('Kochi'), 'Summary lists the trip');
        }
    }
}
