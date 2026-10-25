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
        // Invocable methods must return one result per request. All requests come from the
        // same running user, so one query (for the largest size asked) serves every request.
        List<Integer> sizes = new List<Integer>();
        Integer largest = 1;
        for (Request req : requests) {
            Integer size = (req == null || req.maxTrips == null) ? DEFAULT_TRIPS : Math.max(1, Math.min(MAX_TRIPS, req.maxTrips));
            sizes.add(size);
            largest = Math.max(largest, size);
        }
        List<Trip__c> trips = [
            SELECT Name, Destination_City__c, Start_Date__c, End_Date__c, Status__c, Claim_Status__c, Total_Spent_INR__c
            FROM Trip__c
            WHERE OwnerId = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY Start_Date__c DESC
            LIMIT :largest
        ];

        List<Result> results = new List<Result>();
        for (Integer size : sizes) {
            results.add(summarise(trips, size));
        }
        return results;
    }

    private static final Integer DEFAULT_TRIPS = 5;
    private static final Integer MAX_TRIPS = 10;

    private static Result summarise(List<Trip__c> trips, Integer size) {
        Result res = new Result();
        res.tripCount = Math.min(size, trips.size());
        if (trips.isEmpty()) {
            res.summary = 'You have no trips yet. Create one from the Travel Hub with New Trip.';
            return res;
        }

        List<String> lines = new List<String>();
        for (Integer i = 0; i < res.tripCount; i++) {
            Trip__c trip = trips[i];
            Decimal spent = trip.Total_Spent_INR__c == null ? 0 : trip.Total_Spent_INR__c;
            lines.add(trip.Name + ' - ' + trip.Destination_City__c + ' (' + trip.Start_Date__c.format() + ' to '
                + trip.End_Date__c.format() + '): trip ' + trip.Status__c + ', claim ' + trip.Claim_Status__c
                + ', spent ' + spent.format() + ' INR');
        }
        res.summary = String.join(lines, '\n');
        return res;
    }
}