/**
 * Data for the "My Travel Hub" Lightning Web Component.
 * Returns only the running user's own trips; queries run WITH USER_MODE so
 * object and field security is enforced.
 */
public with sharing class TravelHubController {

    private static final Set<String> OPEN_TRIP_STATUSES = new Set<String>{ 'Submitted', 'Approved' };
    private static final Set<String> PENDING_CLAIM_STATUSES = new Set<String>{
        'Submitted', 'Manager Approved', 'Finance Approved'
    };

    public class Summary {
        @AuraEnabled public Integer openTrips = 0;
        @AuraEnabled public Integer pendingClaims = 0;
        @AuraEnabled public Integer overPolicyExpenses = 0;
        @AuraEnabled public Decimal totalEstimated = 0;
        @AuraEnabled public Decimal totalSpent = 0;
        @AuraEnabled public Decimal reimbursed = 0;
        @AuraEnabled public String grade;
    }

    @AuraEnabled(cacheable=true)
    public static List<Trip__c> getMyTrips() {
        return [
            SELECT Id, Name, Purpose__c, Destination_City__c, Start_Date__c, End_Date__c,
                   Status__c, Claim_Status__c, Estimated_Cost__c, Total_Spent_INR__c, Over_Policy_Count__c
            FROM Trip__c
            WHERE OwnerId = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY Start_Date__c DESC
            LIMIT 20
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Summary getSummary() {
        Summary result = new Summary();
        for (Trip__c trip : [
            SELECT Status__c, Claim_Status__c, Estimated_Cost__c, Total_Spent_INR__c, Over_Policy_Count__c
            FROM Trip__c
            WHERE OwnerId = :UserInfo.getUserId() AND Start_Date__c = THIS_YEAR
            WITH USER_MODE
        ]) {
            Decimal spent = trip.Total_Spent_INR__c == null ? 0 : trip.Total_Spent_INR__c;
            if (OPEN_TRIP_STATUSES.contains(trip.Status__c)) {
                result.openTrips++;
            }
            if (PENDING_CLAIM_STATUSES.contains(trip.Claim_Status__c)) {
                result.pendingClaims++;
            }
            if (trip.Claim_Status__c == 'Reimbursed') {
                result.reimbursed += spent;
            }
            result.totalEstimated += trip.Estimated_Cost__c == null ? 0 : trip.Estimated_Cost__c;
            result.totalSpent += spent;
            result.overPolicyExpenses += trip.Over_Policy_Count__c == null ? 0 : trip.Over_Policy_Count__c.intValue();
        }
        // The user's own record; Grade decides their policy limits.
        result.grade = [SELECT Grade__c FROM User WHERE Id = :UserInfo.getUserId()].Grade__c;
        return result;
    }
}
