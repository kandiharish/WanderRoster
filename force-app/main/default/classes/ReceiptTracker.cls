/**
 * Ticks Has Receipt on an Expense when a file (the receipt) is attached to it.
 *
 * Has Receipt is read-only for employees, so this update runs in system mode on
 * purpose. Uses partial success: if the claim is already locked, the file is
 * still attached and the flag is simply not changed.
 */
public with sharing class ReceiptTracker {

    public static void markReceipts(List<ContentDocumentLink> links) {
        Set<Id> expenseIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            if (link.LinkedEntityId != null
                && link.LinkedEntityId.getSObjectType() == Expense__c.SObjectType) {
                expenseIds.add(link.LinkedEntityId);
            }
        }
        if (expenseIds.isEmpty()) {
            return;
        }

        List<Expense__c> toUpdate = new List<Expense__c>();
        for (Id expenseId : expenseIds) {
            toUpdate.add(new Expense__c(Id = expenseId, Has_Receipt__c = true));
        }

        for (Database.SaveResult result : Database.update(toUpdate, false)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.WARN, 'Has Receipt not set: ' + result.getErrors());
            }
        }
    }
}
