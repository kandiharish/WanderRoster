// WanderRoster demo data for the CFO dashboard. Expenses are tagged "[Demo]" in Description.
// Run: sf apex run -f scripts/setup/4-demoData.apex
Map<String, Id> u = new Map<String, Id>();
for (User usr : [SELECT Id, Name FROM User WHERE Name IN ('Priya Sharma','Rahul Verma','Anita Rao','Kali Iyer','Harish Kandi')]) {
    u.put(usr.Name, usr.Id);
}

// key => trip
Map<String, Trip__c> trips = new Map<String, Trip__c>{
    'T1' => new Trip__c(OwnerId = u.get('Priya Sharma'), Destination_City__c = 'Mumbai',    Purpose__c = 'Client Visit',     Trip_Type__c = 'Domestic',      Start_Date__c = Date.newInstance(2026,10,19), End_Date__c = Date.newInstance(2026,10,21), Estimated_Cost__c = 25000,  Status__c = 'Approved'),
    'T2' => new Trip__c(OwnerId = u.get('Rahul Verma'),  Destination_City__c = 'Delhi',     Purpose__c = 'Client Visit',     Trip_Type__c = 'Domestic',      Start_Date__c = Date.newInstance(2026,10,22), End_Date__c = Date.newInstance(2026,10,24), Estimated_Cost__c = 45000,  Status__c = 'Approved'),
    'T3' => new Trip__c(OwnerId = u.get('Anita Rao'),    Destination_City__c = 'Hyderabad', Purpose__c = 'Training',         Trip_Type__c = 'Domestic',      Start_Date__c = Date.newInstance(2026,11,3),  End_Date__c = Date.newInstance(2026,11,5),  Estimated_Cost__c = 20000,  Status__c = 'Approved'),
    'T4' => new Trip__c(OwnerId = u.get('Kali Iyer'),    Destination_City__c = 'Singapore', Purpose__c = 'Conference',       Trip_Type__c = 'International', Start_Date__c = Date.newInstance(2026,11,10), End_Date__c = Date.newInstance(2026,11,14), Estimated_Cost__c = 90000,  Status__c = 'Approved'),
    'T5' => new Trip__c(OwnerId = u.get('Priya Sharma'), Destination_City__c = 'Pune',      Purpose__c = 'Internal Meeting', Trip_Type__c = 'Domestic',      Start_Date__c = Date.newInstance(2026,11,17), End_Date__c = Date.newInstance(2026,11,18), Estimated_Cost__c = 12000,  Status__c = 'Approved'),
    'T6' => new Trip__c(OwnerId = u.get('Rahul Verma'),  Destination_City__c = 'Dubai',     Purpose__c = 'Client Visit',     Trip_Type__c = 'International', Start_Date__c = Date.newInstance(2026,12,1),  End_Date__c = Date.newInstance(2026,12,4),  Estimated_Cost__c = 70000,  Status__c = 'Approved'),
    'T7' => new Trip__c(OwnerId = u.get('Harish Kandi'), Destination_City__c = 'Kolkata',   Purpose__c = 'Training',         Trip_Type__c = 'Domestic',      Start_Date__c = Date.newInstance(2026,12,8),  End_Date__c = Date.newInstance(2026,12,9),  Estimated_Cost__c = 15000,  Status__c = 'Approved'),
    'T8' => new Trip__c(OwnerId = u.get('Anita Rao'),    Destination_City__c = 'Bengaluru', Purpose__c = 'Internal Meeting', Trip_Type__c = 'Domestic',      Start_Date__c = Date.newInstance(2026,12,14), End_Date__c = Date.newInstance(2026,12,15), Estimated_Cost__c = 10000,  Status__c = 'Submitted')
};
insert trips.values();

// trip key, category, date, amount, currency, nights
List<Object[]> rows = new List<Object[]>{
    new Object[]{'T1','Flight',          Date.newInstance(2026,10,19),  6500, 'INR', null},
    new Object[]{'T1','Hotel',           Date.newInstance(2026,10,19),  6800, 'INR', 2},
    new Object[]{'T1','Meals',           Date.newInstance(2026,10,20),   650, 'INR', null},
    new Object[]{'T1','Local Transport', Date.newInstance(2026,10,21),  1200, 'INR', null},
    new Object[]{'T2','Flight',          Date.newInstance(2026,10,22), 14500, 'INR', null},
    new Object[]{'T2','Hotel',           Date.newInstance(2026,10,22), 11000, 'INR', 2},
    new Object[]{'T2','Meals',           Date.newInstance(2026,10,23),  1500, 'INR', null},
    new Object[]{'T2','Local Transport', Date.newInstance(2026,10,24),  2000, 'INR', null},
    new Object[]{'T3','Local Transport', Date.newInstance(2026,11,3),   1400, 'INR', null},
    new Object[]{'T3','Hotel',           Date.newInstance(2026,11,3),   8400, 'INR', 2},
    new Object[]{'T3','Meals',           Date.newInstance(2026,11,4),   1100, 'INR', null},
    new Object[]{'T4','Flight',          Date.newInstance(2026,11,9),  30000, 'INR', null},
    new Object[]{'T4','Hotel',           Date.newInstance(2026,11,10),   450, 'SGD', 4},
    new Object[]{'T4','Meals',           Date.newInstance(2026,11,12),    60, 'SGD', null},
    new Object[]{'T5','Local Transport', Date.newInstance(2026,11,17),   800, 'INR', null},
    new Object[]{'T5','Meals',           Date.newInstance(2026,11,17),   750, 'INR', null},
    new Object[]{'T5','Meals',           Date.newInstance(2026,11,17),   750, 'INR', null},   // deliberate duplicate
    new Object[]{'T6','Flight',          Date.newInstance(2026,12,1),  18000, 'INR', null},
    new Object[]{'T6','Hotel',           Date.newInstance(2026,12,1),   1500, 'AED', 3},
    new Object[]{'T6','Meals',           Date.newInstance(2026,12,2),    300, 'AED', null},
    new Object[]{'T7','Hotel',           Date.newInstance(2026,12,8),   4000, 'INR', 1},
    new Object[]{'T7','Meals',           Date.newInstance(2026,12,8),    900, 'INR', null},
    new Object[]{'T7','Local Transport', Date.newInstance(2026,12,9),    600, 'INR', null}
};
List<Expense__c> exps = new List<Expense__c>();
for (Object[] r : rows) {
    exps.add(new Expense__c(Trip__c = trips.get((String) r[0]).Id, Category__c = (String) r[1],
        Expense_Date__c = (Date) r[2], Amount__c = (Integer) r[3], Currency_Code__c = (String) r[4],
        Nights__c = (Integer) r[5], Description__c = '[Demo] ' + r[1] + ' - ' + trips.get((String) r[0]).Destination_City__c));
}
// First pass: in-policy lines save; over-policy lines fail the Justification rule and are retried with one.
List<Database.SaveResult> res = Database.insert(exps, false);
List<Expense__c> retry = new List<Expense__c>();
for (Integer i = 0; i < res.size(); i++) {
    if (!res[i].isSuccess()) {
        Expense__c e = exps[i].clone(false, true);
        e.Justification__c = 'Client-location rates higher than policy; pre-approved by manager.';
        retry.add(e);
    }
}
insert retry;

// Move claims through the pipeline (after expenses, because the lock rule blocks expense edits once submitted)
trips.get('T1').Claim_Status__c = 'Submitted';
trips.get('T2').Claim_Status__c = 'Finance Approved';
trips.get('T3').Claim_Status__c = 'Finance Approved';
trips.get('T4').Claim_Status__c = 'Submitted';
trips.get('T6').Claim_Status__c = 'Manager Approved';
trips.get('T7').Claim_Status__c = 'Submitted';
update trips.values();
// Finance pays T3 -> Trip Reimbursed flow sets Reimbursed + Reimbursed_On
update new Trip__c(Id = trips.get('T3').Id, Payment_Reference__c = 'UTR-DEMO-1001');

System.debug('DEMO: ' + trips.size() + ' trips, ' + (exps.size()) + ' expenses, ' + retry.size() + ' needed justification');
