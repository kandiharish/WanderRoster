trigger ExpenseTrigger on Expense__c (before insert, before update, before delete) {
    // One trigger per object. All logic lives in the handler.
    if (Trigger.isDelete) {
        ExpenseTriggerHandler.preventLockedDeletes(Trigger.old);
    } else {
        ExpenseTriggerHandler.applyPolicy(Trigger.new);
        ExpenseTriggerHandler.flagDuplicates(Trigger.new);
    }
}
