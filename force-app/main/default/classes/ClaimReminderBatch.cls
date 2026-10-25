/**
 * Daily housekeeping for finished trips:
 *  1. Approved trips whose End Date has passed are marked Completed.
 *  2. If the claim is still Not Submitted 7, 14, 21... days after the trip ended,
 *     a high-priority reminder Task is created for the trip owner.
 *
 * Batch Apex so it scales to any number of trips; Schedulable so it runs daily.
 * Schedule once (Anonymous Apex):
 *   System.schedule('Daily Claim Reminder', '0 0 7 * * ?', new ClaimReminderBatch());
 */
public with sharing class ClaimReminderBatch implements Database.Batchable<SObject>, Schedulable {

    private static final Integer REMINDER_EVERY_DAYS = 7;

    // Tests set this to simulate a future date; in production it is today.
    @TestVisible
    private static Date runDate = Date.today();

    public Database.QueryLocator start(Database.BatchableContext context) {
        Date today = runDate;
        return Database.getQueryLocator([
            SELECT Id, Name, OwnerId, End_Date__c, Status__c, Claim_Status__c
            FROM Trip__c
            WHERE End_Date__c < :today
              AND (Status__c = 'Approved'
                   OR (Status__c = 'Completed' AND Claim_Status__c = 'Not Submitted'))
        ]);
    }

    public void execute(Database.BatchableContext context, List<Trip__c> trips) {
        List<Trip__c> tripsToComplete = new List<Trip__c>();
        List<Task> reminders = new List<Task>();

        for (Trip__c trip : trips) {
            if (trip.Status__c == 'Approved') {
                tripsToComplete.add(new Trip__c(Id = trip.Id, Status__c = 'Completed'));
            }

            Integer daysSinceEnd = trip.End_Date__c.daysBetween(runDate);
            if (trip.Claim_Status__c == 'Not Submitted'
                && daysSinceEnd >= REMINDER_EVERY_DAYS
                && Math.mod(daysSinceEnd, REMINDER_EVERY_DAYS) == 0) {
                reminders.add(new Task(
                    OwnerId = trip.OwnerId,
                    WhatId = trip.Id,
                    Subject = 'Submit your expense claim for ' + trip.Name,
                    Description = 'Your trip ended ' + daysSinceEnd
                        + ' days ago and the expense claim is not submitted yet.',
                    ActivityDate = runDate.addDays(2),
                    Priority = 'High',
                    Status = 'Not Started'
                ));
            }
        }

        if (!tripsToComplete.isEmpty()) {
            update tripsToComplete;
        }
        if (!reminders.isEmpty()) {
            insert reminders;
        }
    }

    public void finish(Database.BatchableContext context) {
        System.debug('ClaimReminderBatch finished for ' + runDate);
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(new ClaimReminderBatch(), 200);
    }
}
