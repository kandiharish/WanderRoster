/**
 * Cancels trips for the "Cancel Trip" screen flow (also usable from any flow or Apex).
 *
 * Rules:
 *  - Only the trip owner (or a user with Modify All Data) can cancel.
 *  - Allowed while the trip is Draft, Submitted, Approved or Rejected.
 *  - Not allowed once a claim is submitted or any money is spent: spent money goes
 *    through a claim instead.
 *  - A pending trip approval is withdrawn first, which also unlocks the record.
 *  - The manager gets a bell notification if they had already seen the trip.
 *
 * Bulk safe: one query per object, one DML for all trips. Each request gets its own
 * success flag and message, so one bad request never blocks the others.
 */
public with sharing class TripCancellationService {

    private static final String CANCELLED = 'Cancelled';
    private static final String SOURCE = 'TripCancellationService';
    private static final Set<String> CANCELLABLE_STATUSES = new Set<String>{ 'Draft', 'Submitted', 'Approved', 'Rejected' };
    private static final Set<String> MANAGER_INVOLVED_STATUSES = new Set<String>{ 'Submitted', 'Approved' };

    public class Request {
        @InvocableVariable(label='Trip Id' description='The trip to cancel.' required=true)
        public Id tripId;
        @InvocableVariable(label='Reason' description='Why the trip is cancelled.' required=true)
        public String reason;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message' description='Confirmation or the reason the trip could not be cancelled.')
        public String message;
    }

    @InvocableMethod(label='Cancel Trip'
        description='Cancels a trip that has no submitted claim and no spending, withdrawing any pending approval and notifying the manager.')
    public static List<Result> cancel(List<Request> requests) {
        Set<Id> tripIds = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.tripId != null) {
                tripIds.add(req.tripId);
            }
        }
        Map<Id, Trip__c> tripsById = new Map<Id, Trip__c>([
            SELECT Id, Name, OwnerId, Owner.Name, Status__c, Claim_Status__c, Total_Spent_INR__c, Destination_City__c
            FROM Trip__c
            WHERE Id IN :tripIds
        ]);
        Boolean isAdmin = [SELECT PermissionsModifyAllData FROM Profile WHERE Id = :UserInfo.getProfileId()].PermissionsModifyAllData;

        // 1. Check every request; keep the valid ones.
        List<Result> results = new List<Result>();
        Map<Id, String> reasonByTrip = new Map<Id, String>();
        Map<Id, String> previousStatus = new Map<Id, String>();
        Map<Id, Result> resultByTrip = new Map<Id, Result>();
        for (Request req : requests) {
            Result res = new Result();
            results.add(res);
            Trip__c trip = (req == null) ? null : tripsById.get(req.tripId);
            res.message = validate(req, trip, isAdmin);
            res.success = res.message == null;
            if (res.success) {
                reasonByTrip.put(trip.Id, req.reason.trim());
                previousStatus.put(trip.Id, trip.Status__c);
                resultByTrip.put(trip.Id, res);
            }
        }
        if (reasonByTrip.isEmpty()) {
            return results;
        }

        // 2. Withdraw pending approvals (recall), so the record is unlocked.
        withdrawPendingApprovals(reasonByTrip.keySet(), resultByTrip);

        // 3. Cancel the trips that are still valid.
        List<Trip__c> updates = new List<Trip__c>();
        for (Id tripId : reasonByTrip.keySet()) {
            if (resultByTrip.get(tripId).success) {
                updates.add(new Trip__c(
                    Id = tripId,
                    Status__c = CANCELLED,
                    Cancellation_Reason__c = reasonByTrip.get(tripId),
                    Cancelled_On__c = Date.today()
                ));
            }
        }
        // Status is read-only for employees on purpose (it changes only through approvals and this
        // service). The rules above have been checked and the trip was read with sharing, so the
        // write itself runs in system mode.
        List<Database.SaveResult> saves = Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        List<Trip__c> cancelled = new List<Trip__c>();
        for (Integer i = 0; i < saves.size(); i++) {
            Result res = resultByTrip.get(updates[i].Id);
            if (saves[i].isSuccess()) {
                res.message = tripsById.get(updates[i].Id).Name + ' is cancelled.';
                cancelled.add(tripsById.get(updates[i].Id));
            } else {
                res.success = false;
                res.message = 'The trip could not be cancelled: ' + saves[i].getErrors()[0].getMessage();
                ErrorLogger.log(SOURCE, res.message, updates[i].Id, ErrorLogger.ERROR);
            }
        }

        // 4. Tell the manager when they had already been involved.
        notifyManagers(cancelled, previousStatus, reasonByTrip);
        return results;
    }

    /** Returns null when the request is valid, otherwise a message for the user. */
    private static String validate(Request req, Trip__c trip, Boolean isAdmin) {
        if (trip == null) {
            return 'Trip not found, or you do not have access to it.';
        }
        if (trip.OwnerId != UserInfo.getUserId() && !isAdmin) {
            return 'Only the person who owns the trip can cancel it.';
        }
        if (String.isBlank(req.reason)) {
            return 'Please enter a reason for cancelling.';
        }
        if (!CANCELLABLE_STATUSES.contains(trip.Status__c)) {
            return 'A ' + trip.Status__c + ' trip cannot be cancelled.';
        }
        if (trip.Claim_Status__c != null && trip.Claim_Status__c != 'Not Submitted') {
            return 'The expense claim for this trip is already ' + trip.Claim_Status__c + ', so the trip cannot be cancelled.';
        }
        if (trip.Total_Spent_INR__c != null && trip.Total_Spent_INR__c > 0) {
            return 'This trip already has expenses. Submit them as a claim instead of cancelling the trip.';
        }
        return null;
    }

    private static void withdrawPendingApprovals(Set<Id> tripIds, Map<Id, Result> resultByTrip) {
        List<Approval.ProcessWorkitemRequest> removals = new List<Approval.ProcessWorkitemRequest>();
        List<Id> removalTripIds = new List<Id>();
        for (ProcessInstanceWorkitem item : [
            SELECT Id, ProcessInstance.TargetObjectId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId IN :tripIds
              AND ProcessInstance.Status = 'Pending'
        ]) {
            Approval.ProcessWorkitemRequest removal = new Approval.ProcessWorkitemRequest();
            removal.setWorkitemId(item.Id);
            removal.setAction('Removed');
            removal.setComments('Trip cancelled by the employee.');
            removals.add(removal);
            removalTripIds.add(item.ProcessInstance.TargetObjectId);
        }
        if (removals.isEmpty()) {
            return;
        }
        List<Approval.ProcessResult> outcomes = Approval.process(removals, false);
        for (Integer i = 0; i < outcomes.size(); i++) {
            if (!outcomes[i].isSuccess()) {
                Result res = resultByTrip.get(removalTripIds[i]);
                res.success = false;
                res.message = 'The pending approval could not be withdrawn: ' + outcomes[i].getErrors()[0].getMessage();
                ErrorLogger.log(SOURCE, res.message, removalTripIds[i], ErrorLogger.ERROR);
            }
        }
    }

    private static void notifyManagers(List<Trip__c> trips, Map<Id, String> previousStatus, Map<Id, String> reasonByTrip) {
        Set<Id> ownerIds = new Set<Id>();
        for (Trip__c trip : trips) {
            ownerIds.add(trip.OwnerId);
        }
        Map<Id, User> owners = new Map<Id, User>([SELECT Id, ManagerId FROM User WHERE Id IN :ownerIds]);
        List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Trip_Alert' LIMIT 1];
        if (types.isEmpty()) {
            return;
        }
        for (Trip__c trip : trips) {
            User owner = owners.get(trip.OwnerId);
            if (owner == null || owner.ManagerId == null || !MANAGER_INVOLVED_STATUSES.contains(previousStatus.get(trip.Id))) {
                continue;
            }
            try {
                Messaging.CustomNotification bell = new Messaging.CustomNotification();
                bell.setNotificationTypeId(types[0].Id);
                bell.setTitle(trip.Name + ' was cancelled');
                bell.setBody(trip.Owner.Name + ' cancelled the trip to ' + trip.Destination_City__c + '. Reason: ' + reasonByTrip.get(trip.Id));
                bell.setTargetId(trip.Id);
                bell.send(new Set<String>{ owner.ManagerId });
            } catch (Exception ex) {
                // The cancellation stands even if the bell cannot be sent.
                ErrorLogger.log(SOURCE, ex, trip.Id);
            }
        }
    }
}
