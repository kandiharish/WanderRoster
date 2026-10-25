@IsTest
private class ExpenseTriggerHandlerTest {

    // Test data is isolated from org data, so the rates and trip are created here.
    // Travel_Policy__mdt is visible in tests, so the policy limits come from the org.
    // Each test runs as a G2 test employee (limit: Meals 1200, Hotel 4500 per night),
    // so the results don't depend on the grade of the user running the tests.

    @TestSetup
    static void setup() {
        insert new Currency_Rate__c(Currency_Code__c = 'USD', Rate_To_INR__c = 83);
        TestUserFactory.createEmployee('G2 - Senior Associate', 'g2expense');
    }

    private static User employee() {
        return TestUserFactory.getEmployee('g2expense');
    }

    // Created by the test admin and owned by the employee: employees can't set Status
    // themselves (the approval process does), so this mirrors an already-approved trip.
    private static Trip__c createApprovedTrip() {
        Trip__c trip = new Trip__c(
            OwnerId = employee().Id,
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
    static void inrMealsWithinPolicy() {
        Trip__c trip = createApprovedTrip();
        System.runAs(employee()) {
            Expense__c exp = new Expense__c(
                Trip__c = trip.Id,
                Category__c = 'Meals',
                Expense_Date__c = trip.Start_Date__c,
                Amount__c = 900,
                Currency_Code__c = 'INR'
            );

            Test.startTest();
            insert exp;
            Test.stopTest();

            Expense__c saved = [SELECT Amount_INR__c, Policy_Limit_INR__c, Over_Policy__c FROM Expense__c WHERE Id = :exp.Id];
            System.assertEquals(900, saved.Amount_INR__c, 'INR amount should be copied as-is');
            System.assertEquals(1200, saved.Policy_Limit_INR__c, 'G2 meals limit is 1200');
            System.assertEquals(false, saved.Over_Policy__c, '900 is within 1200');
        }
    }

    @IsTest
    static void foreignCurrencyConvertedToInr() {
        Trip__c trip = createApprovedTrip();
        System.runAs(employee()) {
            Expense__c exp = new Expense__c(
                Trip__c = trip.Id,
                Category__c = 'Other',
                Expense_Date__c = trip.Start_Date__c,
                Amount__c = 10,
                Currency_Code__c = 'USD'
            );

            Test.startTest();
            insert exp;
            Test.stopTest();

            Expense__c saved = [SELECT Amount_INR__c FROM Expense__c WHERE Id = :exp.Id];
            System.assertEquals(830, saved.Amount_INR__c, '10 USD at 83 INR per USD');
        }
    }

    @IsTest
    static void overPolicyFlaggedWhenAboveLimit() {
        Trip__c trip = createApprovedTrip();
        System.runAs(employee()) {
            Expense__c exp = new Expense__c(
                Trip__c = trip.Id,
                Category__c = 'Meals',
                Expense_Date__c = trip.Start_Date__c,
                Amount__c = 1500,
                Currency_Code__c = 'INR',
                Justification__c = 'Client dinner, team of four'
            );

            Test.startTest();
            insert exp;
            Test.stopTest();

            Expense__c saved = [SELECT Over_Policy__c FROM Expense__c WHERE Id = :exp.Id];
            System.assertEquals(true, saved.Over_Policy__c, '1500 is above 1200');
        }
    }

    @IsTest
    static void hotelLimitScalesWithNights() {
        Trip__c trip = createApprovedTrip();
        System.runAs(employee()) {
            Expense__c exp = new Expense__c(
                Trip__c = trip.Id,
                Category__c = 'Hotel',
                Expense_Date__c = trip.Start_Date__c,
                Amount__c = 9000,
                Currency_Code__c = 'INR',
                Nights__c = 2
            );

            Test.startTest();
            insert exp;
            Test.stopTest();

            Expense__c saved = [SELECT Policy_Limit_INR__c, Over_Policy__c FROM Expense__c WHERE Id = :exp.Id];
            System.assertEquals(9000, saved.Policy_Limit_INR__c, '4500 per night x 2 nights');
            System.assertEquals(false, saved.Over_Policy__c, '9000 equals the 2-night limit, so not over');
        }
    }

    @IsTest
    static void bulkInsertUpdatesAllRecords() {
        Trip__c trip = createApprovedTrip();
        System.runAs(employee()) {
            List<Expense__c> expenses = new List<Expense__c>();
            for (Integer i = 0; i < 200; i++) {
                expenses.add(new Expense__c(
                    Trip__c = trip.Id,
                    Category__c = 'Meals',
                    Expense_Date__c = trip.Start_Date__c,
                    Amount__c = 100,
                    Currency_Code__c = 'INR'
                ));
            }

            Test.startTest();
            insert expenses;
            Test.stopTest();

            Integer updated = [SELECT COUNT() FROM Expense__c WHERE Trip__c = :trip.Id AND Amount_INR__c = 100];
            System.assertEquals(200, updated, 'Every record in the batch should get Amount (INR)');
            // All 200 share owner, date, category and amount: the first is the original, the other 199 are flagged.
            Integer flagged = [SELECT COUNT() FROM Expense__c WHERE Trip__c = :trip.Id AND Possible_Duplicate__c = true];
            System.assertEquals(199, flagged, 'Duplicates inside one bulk save should be flagged');
        }
    }

    @IsTest
    static void missingRateBlocksSave() {
        Trip__c trip = createApprovedTrip();
        System.runAs(employee()) {
            Expense__c exp = new Expense__c(
                Trip__c = trip.Id,
                Category__c = 'Other',
                Expense_Date__c = trip.Start_Date__c,
                Amount__c = 50,
                Currency_Code__c = 'EUR'
            );

            Boolean blocked = false;
            Test.startTest();
            try {
                insert exp;
            } catch (DmlException e) {
                blocked = e.getMessage().contains('No exchange rate found for EUR');
            }
            Test.stopTest();

            System.assertEquals(true, blocked, 'Saving without a rate should show a clear error');
        }
    }
}