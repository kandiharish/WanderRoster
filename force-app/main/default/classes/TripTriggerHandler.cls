/**
 * Sends an in-app notification to the trip owner when the claim status moves
 * to a status they need to know about.
 *
 * Bulk safe: one query for the notification type, no SOQL inside loops.
 */
public with sharing class TripTriggerHandler {

    private static final Set<String> NOTIFY_STATUSES = new Set<String>{
        'Manager Approved', 'Finance Approved', 'Reimbursed', 'Rejected'
    };
    private static final String NOTIFICATION_TYPE_NAME = 'Claim_Status_Update';

    public static void onAfterUpdate(List<Trip__c> trips, Map<Id, Trip__c> oldMap) {
        List<Trip__c> changed = new List<Trip__c>();
        for (Trip__c trip : trips) {
            Trip__c oldTrip = oldMap.get(trip.Id);
            if (trip.Claim_Status__c != oldTrip.Claim_Status__c
                && NOTIFY_STATUSES.contains(trip.Claim_Status__c)) {
                changed.add(trip);
            }
        }
        if (changed.isEmpty()) {
            return;
        }

        Id typeId = getNotificationTypeId();
        if (typeId == null) {
            System.debug(LoggingLevel.WARN, 'Notification type ' + NOTIFICATION_TYPE_NAME + ' not found; skipping alerts.');
            return;
        }
        for (Trip__c trip : changed) {
            sendNotification(typeId, trip);
        }
    }

    private static Id getNotificationTypeId() {
        List<CustomNotificationType> types = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :NOTIFICATION_TYPE_NAME
            LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }

    private static void sendNotification(Id typeId, Trip__c trip) {
        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setNotificationTypeId(typeId);
        notification.setTitle(trip.Name + ' claim: ' + trip.Claim_Status__c);
        notification.setBody('Your claim for ' + trip.Destination_City__c + ' is now ' + trip.Claim_Status__c + '.');
        notification.setTargetId(trip.Id);
        notification.send(new Set<String>{ trip.OwnerId });
    }
}