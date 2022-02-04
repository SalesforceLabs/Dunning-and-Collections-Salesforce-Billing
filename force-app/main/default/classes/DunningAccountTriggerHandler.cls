public with sharing class DunningAccountTriggerHandler {
   static final String IN_COLLECTIONS = 'In Collections';

    public static void handleAfterUpdate(Map<Id,Account> oldAccountMap, Map<Id,Account> newAccountMap) {
        Map<Id, Account> accountsInCollections = new Map<Id, Account>();

        // Check if the Collections Status field is changed
        for(Id accId: oldAccountMap.keySet()) {
            // Check if the old value was NOT in collections and that the new value IS in collections
            // also check if Dunning Method is set on account
            String oldStatus = oldAccountMap.get(accId).CollectionsStatus__c;
            String newStatus = newAccountMap.get(accId).CollectionsStatus__c;
            Id dunningMethodId = newAccountMap.get(accId).DunningMethod__c;
            if( oldStatus != IN_COLLECTIONS && newStatus == IN_COLLECTIONS && dunningMethodId != null) {
                accountsInCollections.put(accId, newAccountMap.get(accId));
            }
            
        }

        if(accountsInCollections.isEmpty()) {
            return;
        }
        // Get Dunning Methods
        Map<Id,Id> dunningIdByAccountId = DunningUtilities.getDunningIdsFromAccounts(accountsInCollections.values());


        Set<Id> dunningMethodIds = new Set<Id>();
        dunningMethodIds.addAll(dunningIdByAccountId.values());
        // Get Activities by their associated Dunning Id
        Map<Id, List<DunningActivity__c>> activitiesByDunningId = DunningUtilities.getDunningActivities(dunningMethodIds);

        // Create Collections Plans for accounts
        List<CollectionsPlan__c> collectionsPlans = DunningUtilities.createPlansFromAccounts(accountsInCollections.values());

        try {
            Database.insert(collectionsPlans);
        } catch (DmlException e) {
            System.debug(e);
        }

        // Need collections plans by account Ids
        Map<Id,CollectionsPlan__c> plansByAccountId = new Map<Id,CollectionsPlan__c>();
        for (CollectionsPlan__c plan : collectionsPlans) {
            plansByAccountId.put(plan.Account__c, plan);
        }

        // need all Invoices (that should be included) by account Ids
        Map<Id, List<blng__Invoice__c>> invoicesByAccountId = DunningUtilities.getInvoicesFromCollections(plansByAccountId);
        
        // Create the Collection Invoices (link Invoices to Collections plans)
        List<CollectionsInvoice__c> collectInvs = DunningUtilities.createPlanInvoiceJunctions(plansByAccountId, invoicesByAccountId);

        try {
            Database.insert(collectInvs);
        } catch (DmlException e) {
            System.debug(e);
        }


        // Create Tasks on the Collections plans
        List<Task> planTasks = DunningUtilities.createCollectionsTasks(collectionsPlans, activitiesByDunningId);
        // Need Dunning activities from Dunning Method 

        try {
            Database.insert(planTasks);
        } catch (DmlException e) {
            System.debug(e);
        }

    }
}