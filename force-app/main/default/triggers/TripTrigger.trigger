trigger TripTrigger on Trip__c (after update) {
    // One trigger per object. All logic lives in the handler.
    TripTriggerHandler.onAfterUpdate(Trigger.new, Trigger.oldMap);
}