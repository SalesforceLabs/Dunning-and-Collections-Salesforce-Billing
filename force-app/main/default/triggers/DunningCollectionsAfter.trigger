trigger DunningCollectionsAfter on CollectionsPlan__c (after insert, after update) {

    if(DunningSettings__c.getInstance().DisableTriggers__c) {
      System.debug('Bypassing trigger due to custom setting');
      // Check if Custom Setting Trigger Disabler is on
      return;
    }
    // Don't run during tests
    if(Test.isRunningTest()) {
      return;
    }

    // run the after update process
    if(Trigger.isUpdate && Trigger.isAfter) {
      DunningCollectionsTriggerHandler.handleAfterUpdate(Trigger.oldMap, Trigger.newMap);
    }
}