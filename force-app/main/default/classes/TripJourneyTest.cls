@IsTest
private class TripJourneyTest {

    // End-to-end journey with real approvals and the real users' access:
    // employee submits trip -> manager approves -> travel agency enters booking reference
    // -> employee adds an expense -> employee submits the claim.

    @TestSetup
    static void setup() {
        User manager = TestUserFactory.createEmployee('G3 - Manager', 'jmanager');
        User employee = TestUserFactory.createEmployee('G1 - Associate', 'jemployee');

        // Setup DML (roles, users, group members) and normal DML (account, contact)
        // must run in separate runAs blocks to avoid MIXED_DML_OPERATION.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Same shape as production: the manager's role is above the employee's role.
            UserRole managerRole = new UserRole(Name = 'Journey Manager', DeveloperName = 'Journey_Manager');
            insert managerRole;
            UserRole employeeRole = new UserRole(Name = 'Journey Associate', DeveloperName = 'Journey_Associate', ParentRoleId = managerRole.Id);
            insert employeeRole;
            manager.UserRoleId = managerRole.Id;
            employee.UserRoleId = employeeRole.Id;
            employee.ManagerId = manager.Id;
            update new List<User>{ manager, employee };
        }

        Account agency = new Account(Name = 'Journey Travels', OwnerId = manager.Id);
        insert agency;
        agency.IsPartner = true;
        update agency;
        Contact agent = new Contact(LastName = 'Agent', AccountId = agency.Id);
        insert agent;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile agencyProfile = [SELECT Id FROM Profile WHERE Name = 'WR Travel Agency User'];
            User partner = new User(
                LastName = 'Agent', Alias = 'jagent', Username = 'jagent@wanderroster.test',
                Email = 'jagent@wanderroster.test', ContactId = agent.Id, ProfileId = agencyProfile.Id,
                TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
            );
            insert partner;
            PermissionSet agencyAccess = [SELECT Id FROM PermissionSet WHERE Name = 'WR_Travel_Agency'];
            insert new PermissionSetAssignment(AssigneeId = partner.Id, PermissionSetId = agencyAccess.Id);

            // Same as production: the agency's partner role is a member of the Travel Agencies group.
            Id partnerRoleId = [SELECT UserRoleId FROM User WHERE Id = :partner.Id].UserRoleId;
            Group roleGroup = [SELECT Id FROM Group WHERE Type = 'Role' AND RelatedId = :partnerRoleId];
            Group agencies = [SELECT Id FROM Group WHERE DeveloperName = 'Travel_Agencies'];
            insert new GroupMember(GroupId = agencies.Id, UserOrGroupId = roleGroup.Id);
        }
    }

    // Criteria-based sharing rules are not applied inside Apex tests (verified: no 'Rule' shares are
    // created), so the test adds the same share that "Share Approved Trips with Travel Agencies" creates in the org.
    private static void shareWithAgencies(Id tripId) {
        Group agencies = [SELECT Id FROM Group WHERE DeveloperName = 'Travel_Agencies'];
        insert new Trip__Share(ParentId = tripId, UserOrGroupId = agencies.Id, AccessLevel = 'Edit', RowCause = 'Manual');
    }

    @IsTest
    static void approvedTripCanBeBookedExpensedAndClaimed() {
        User employee = TestUserFactory.getEmployee('jemployee');
        User manager = TestUserFactory.getEmployee('jmanager');
        User partner = [SELECT Id FROM User WHERE Username = 'jagent@wanderroster.test'];
        insert new Currency_Rate__c(Currency_Code__c = 'USD', Rate_To_INR__c = 83);

        Trip__c trip = new Trip__c(
            Purpose__c = 'Client Visit', Trip_Type__c = 'Domestic', Destination_City__c = 'Hyderabad',
            Start_Date__c = Date.today().addDays(5), End_Date__c = Date.today().addDays(7),
            Estimated_Cost__c = 25000
        );

        Test.startTest();
        System.runAs(employee) {
            insert trip;
            Approval.ProcessSubmitRequest submit = new Approval.ProcessSubmitRequest();
            submit.setObjectId(trip.Id);
            submit.setProcessDefinitionNameOrId('Trip_Approval');
            Approval.process(submit);
        }
        System.assertEquals('Submitted', [SELECT Status__c FROM Trip__c WHERE Id = :trip.Id].Status__c, 'Trip submitted');

        System.runAs(manager) {
            ProcessInstanceWorkitem item = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :trip.Id];
            Approval.ProcessWorkitemRequest approve = new Approval.ProcessWorkitemRequest();
            approve.setWorkitemId(item.Id);
            approve.setAction('Approve');
            Approval.process(approve);
        }
        System.assertEquals('Approved', [SELECT Status__c FROM Trip__c WHERE Id = :trip.Id].Status__c, 'Manager approved');

        shareWithAgencies(trip.Id);
        System.runAs(partner) {
            update new Trip__c(Id = trip.Id, Booking_Reference__c = 'PNR-TEST01');
        }

        System.runAs(employee) {
            insert new Expense__c(
                Trip__c = trip.Id, Category__c = 'Meals', Expense_Date__c = trip.Start_Date__c,
                Amount__c = 500, Currency_Code__c = 'INR'
            );
            Approval.ProcessSubmitRequest claim = new Approval.ProcessSubmitRequest();
            claim.setObjectId(trip.Id);
            claim.setProcessDefinitionNameOrId('Claim_Approval');
            Approval.process(claim);
        }
        Test.stopTest();

        Trip__c saved = [SELECT Booking_Reference__c, Claim_Status__c, Total_Spent_INR__c FROM Trip__c WHERE Id = :trip.Id];
        System.assertEquals('PNR-TEST01', saved.Booking_Reference__c, 'Agency could book the approved trip');
        System.assertEquals(500, saved.Total_Spent_INR__c, 'Employee could add an expense after approval');
        System.assertEquals('Submitted', saved.Claim_Status__c, 'Employee could submit the claim');
    }

    @IsTest
    static void agencyCannotChangeTripDetails() {
        User partner = [SELECT Id FROM User WHERE Username = 'jagent@wanderroster.test'];
        Trip__c trip = new Trip__c(
            OwnerId = TestUserFactory.getEmployee('jemployee').Id,
            Purpose__c = 'Training', Trip_Type__c = 'Domestic', Destination_City__c = 'Pune',
            Start_Date__c = Date.today().addDays(5), End_Date__c = Date.today().addDays(6),
            Estimated_Cost__c = 9000, Status__c = 'Approved'
        );
        insert trip;

        String error;
        shareWithAgencies(trip.Id);
        Test.startTest();
        System.runAs(partner) {
            try {
                update new Trip__c(Id = trip.Id, Destination_City__c = 'Goa');
            } catch (DmlException e) {
                error = e.getMessage();
            }
        }
        Test.stopTest();

        System.assert(error != null && error.contains('only update the Booking Reference'), 'Agency blocked from changing trip details: ' + error + error);
    }

    @IsTest
    static void employeeCannotChangeApprovedTripDetails() {
        User employee = TestUserFactory.getEmployee('jemployee');
        Trip__c trip = new Trip__c(
            OwnerId = employee.Id,
            Purpose__c = 'Conference', Trip_Type__c = 'Domestic', Destination_City__c = 'Delhi',
            Start_Date__c = Date.today().addDays(3), End_Date__c = Date.today().addDays(4),
            Estimated_Cost__c = 15000, Status__c = 'Approved'
        );
        insert trip;

        String error;
        Test.startTest();
        System.runAs(employee) {
            try {
                update new Trip__c(Id = trip.Id, Estimated_Cost__c = 50000);
            } catch (DmlException e) {
                error = e.getMessage();
            }
        }
        Test.stopTest();

        System.assert(error != null && error.contains('already approved'), 'Approved trip details are locked: ' + error);
    }
}
