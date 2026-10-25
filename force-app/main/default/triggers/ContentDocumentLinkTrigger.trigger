trigger ContentDocumentLinkTrigger on ContentDocumentLink (after insert) {
    // One trigger per object. All logic lives in the handler.
    ReceiptTracker.markReceipts(Trigger.new);
}
