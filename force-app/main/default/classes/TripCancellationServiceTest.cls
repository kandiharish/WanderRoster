@IsTest
private class TripCancellationServiceTest {

    @TestSetup
    static void setup() {
        User manager = TestUserFactory.createEmployee('G3 - Manager', 'cmanager');
        User employee = TestUserFactory.createEmployee('G1 - Associate', 'cemployee');
        TestUserFactory.createEmployee('G1 - Associate', 'cother');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            employee.ManagerId = manager.Id; // Trip Approval routes to the Manager field
            update employee;
        }
    }

    private static Trip__c newTrip(String city) {
        return new Trip__c(
            Purpose__c = 'Client Visit', Trip_Type__c = 'Domestic', Destination_City__c = city,
            Start_Date__c = Date.today().addDays(5), End_Date__c = Date.today().addDays(7),
            Estimated_Cost__c = 20000
        );
    }

    private static TripCancellationService.Result cancel(Id tripId, String reason) {
        TripCancellationService.Request req = new TripCancellationService.Request();
        req.tripId = tripId;
        req.reason = reason;
        return TripCancellationService.cancel(new List<TripCancellationService.Request>{ req })[0];
    }

    @IsTest
    static void ownerCancelsDraftTrip() {
        User employee = TestUserFactory.getEmployee('cemployee');
        TripCancellationService.Result res;
        Trip__c trip = newTrip('Pune');
        Test.startTest();
        System.runAs(employee) {
            insert trip;
            res = cancel(trip.Id, 'Client meeting moved online');
        }
        Test.stopTest();

        Trip__c saved = [SELECT Status__c, Cancellation_Reason__c, Cancelled_On__c FROM Trip__c WHERE Id = :trip.Id WITH SYSTEM_MODE];
        Assert.isTrue(res.success, 'Draft trip should cancel: ' + res.message);
        Assert.areEqual('Cancelled', saved.Status__c);
        Assert.areEqual('Client meeting moved online', saved.Cancellation_Reason__c);
        Assert.areEqual(Date.today(), saved.Cancelled_On__c);
    }

    @IsTest
    static void cancellingSubmittedTripWithdrawsTheApproval() {
        User employee = TestUserFactory.getEmployee('cemployee');
        TripCancellationService.Result res;
        Trip__c trip = newTrip('Delhi');
        Test.startTest();
        System.runAs(employee) {
            insert trip;
            Approval.ProcessSubmitRequest submit = new Approval.ProcessSubmitRequest();
            submit.setObjectId(trip.Id);
            submit.setProcessDefinitionNameOrId('Trip_Approval');
            Approval.process(submit);
            res = cancel(trip.Id, 'Conference cancelled');
        }
        Test.stopTest();

        Assert.isTrue(res.success, 'Submitted trip should cancel: ' + res.message);
        Assert.areEqual('Cancelled', [SELECT Status__c FROM Trip__c WHERE Id = :trip.Id WITH SYSTEM_MODE].Status__c);
        Assert.areEqual(0, [SELECT COUNT() FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :trip.Id],
            'The pending approval request must be withdrawn');
        // The approval request ends as Removed (withdrawn); the Cancelled update above could only
        // succeed because removing it released the approval lock.
        Assert.areEqual('Removed', [SELECT Status FROM ProcessInstance WHERE TargetObjectId = :trip.Id].Status);
    }

    @IsTest
    static void tripWithExpensesCannotBeCancelled() {
        User employee = TestUserFactory.getEmployee('cemployee');
        Trip__c trip = newTrip('Chennai');
        System.runAs(employee) {
            insert trip;
        }
        trip.Status__c = 'Approved'; // as the approval process would
        update trip;

        TripCancellationService.Result res;
        Test.startTest();
        System.runAs(employee) {
            insert new Expense__c(Trip__c = trip.Id, Category__c = 'Meals', Expense_Date__c = trip.Start_Date__c,
                Amount__c = 500, Currency_Code__c = 'INR');
            res = cancel(trip.Id, 'Changed plans');
        }
        Test.stopTest();

        Assert.isFalse(res.success, 'Money already spent: the trip must go through a claim');
        Assert.isTrue(res.message.contains('expenses'), res.message);
        Assert.areEqual('Approved', [SELECT Status__c FROM Trip__c WHERE Id = :trip.Id WITH SYSTEM_MODE].Status__c);
    }

    @IsTest
    static void approvedTripCancelsAndStaysFinal() {
        User employee = TestUserFactory.getEmployee('cemployee');
        Trip__c trip = newTrip('Kochi');
        System.runAs(employee) {
            insert trip;
        }
        trip.Status__c = 'Approved';
        update trip;

        TripCancellationService.Result res;
        Test.startTest();
        System.runAs(employee) {
            res = cancel(trip.Id, 'Project put on hold');
        }
        Test.stopTest();
        Assert.isTrue(res.success, res.message);

        // Cancelled_Trip_Is_Final: nobody can reopen or edit it afterwards.
        trip = [SELECT Id FROM Trip__c WHERE Id = :trip.Id WITH SYSTEM_MODE];
        trip.Status__c = 'Approved';
        Database.SaveResult reopen = Database.update(trip, false);
        Assert.isFalse(reopen.isSuccess(), 'A cancelled trip must not be reopened');
        Assert.isTrue(reopen.getErrors()[0].getMessage().contains('cancelled'), reopen.getErrors()[0].getMessage());
    }

    @IsTest
    static void onlyTheOwnerCanCancelAndReasonIsRequired() {
        User employee = TestUserFactory.getEmployee('cemployee');
        User other = TestUserFactory.getEmployee('cother');
        Trip__c trip = newTrip('Goa');
        System.runAs(employee) {
            insert trip;
        }

        List<TripCancellationService.Result> results;
        Test.startTest();
        System.runAs(other) {
            // Another employee cannot even see the private trip.
            results = new List<TripCancellationService.Result>{ cancel(trip.Id, 'Not mine') };
        }
        System.runAs(employee) {
            results.add(cancel(trip.Id, '   '));
        }
        Test.stopTest();

        Assert.isFalse(results[0].success);
        Assert.isTrue(results[0].message.contains('not found'), results[0].message);
        Assert.isFalse(results[1].success);
        Assert.isTrue(results[1].message.contains('reason'), results[1].message);
        Assert.areEqual('Draft', [SELECT Status__c FROM Trip__c WHERE Id = :trip.Id WITH SYSTEM_MODE].Status__c);
    }

    @IsTest
    static void bulkRequestsGetTheirOwnResults() {
        User employee = TestUserFactory.getEmployee('cemployee');
        Trip__c draft = newTrip('Mysuru');
        Trip__c completed = newTrip('Agra');
        System.runAs(employee) {
            insert new List<Trip__c>{ draft, completed };
        }
        completed.Status__c = 'Completed';
        update completed;

        List<TripCancellationService.Request> requests = new List<TripCancellationService.Request>();
        for (Trip__c trip : new List<Trip__c>{ draft, completed }) {
            TripCancellationService.Request req = new TripCancellationService.Request();
            req.tripId = trip.Id;
            req.reason = 'Budget freeze';
            requests.add(req);
        }
        List<TripCancellationService.Result> results;
        Test.startTest();
        System.runAs(employee) {
            results = TripCancellationService.cancel(requests);
        }
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'One result per request');
        Assert.isTrue(results[0].success, results[0].message);
        Assert.isFalse(results[1].success, 'A completed trip cannot be cancelled');
        Assert.areEqual('Completed', [SELECT Status__c FROM Trip__c WHERE Id = :completed.Id WITH SYSTEM_MODE].Status__c);
    }
}
