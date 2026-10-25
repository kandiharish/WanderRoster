/**
 * Agentforce action: "What is the status of my trips and claims?"
 * Returns a short, readable summary of the running user's latest trips.
 */
public with sharing class MyTripStatusAction {

    public class Request {
        @InvocableVariable(label='Number of Trips' description='How many of the latest trips to return. Default 5, maximum 10.')
        public Integer maxTrips;
    }

    public class Result {
        @InvocableVariable(label='Summary' description='Readable list of the employee\'s latest trips with trip and claim status.')
        public String summary;
        @InvocableVariable(label='Trip Count')
        public Integer tripCount;
    }

    @InvocableMethod(label='Get My Trip and Claim Status'
        description='Returns the current employee\'s latest trips with destination, dates, trip approval status, claim status and amount spent.')
    public static List<Result> getStatus(List<Request> requests) {
        Integer maxTrips = 5;
        if (requests != null && !requests.isEmpty() && requests[0] != null && requests[0].maxTrips != null) {
            maxTrips = Math.max(1, Math.min(10, requests[0].maxTrips));
        }
        List<Trip__c> trips = [
            SELECT Name, Destination_City__c, Start_Date__c, End_Date__c, Status__c, Claim_Status__c, Total_Spent_INR__c
            FROM Trip__c
            WHERE OwnerId = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY Start_Date__c DESC
            LIMIT :maxTrips
        ];

        Result res = new Result();
        res.tripCount = trips.size();
        if (trips.isEmpty()) {
            res.summary = 'You have no trips yet. Create one from the Travel Hub with New Trip.';
            return new List<Result>{ res };
        }

        List<String> lines = new List<String>();
        for (Trip__c trip : trips) {
            Decimal spent = trip.Total_Spent_INR__c == null ? 0 : trip.Total_Spent_INR__c;
            lines.add(trip.Name + ' - ' + trip.Destination_City__c + ' (' + trip.Start_Date__c.format() + ' to '
                + trip.End_Date__c.format() + '): trip ' + trip.Status__c + ', claim ' + trip.Claim_Status__c
                + ', spent ' + spent.format() + ' INR');
        }
        res.summary = String.join(lines, '\n');
        return new List<Result>{ res };
    }
}