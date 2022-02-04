public with sharing class DunningCollectionsTriggerHandler {
    static final String CLOSED_STATUS = 'Closed';

    public static void handleAfterUpdate(Map<Id,CollectionsPlan__c> oldCollectionsMap, Map<Id,CollectionsPlan__c> newCollectionsMap) {
        Map<Id, CollectionsPlan__c> closedCollectionsPlans = new Map<Id, CollectionsPlan__c>();

        // Check if the Collections Plan Status field is changed to closed
        for(Id colPlanId: oldCollectionsMap.keySet()) {
            String oldStatus = oldCollectionsMap.get(colPlanId).Status__c;
            String newStatus = newCollectionsMap.get(colPlanId).Status__c;

            if(oldStatus != CLOSED_STATUS && newStatus == CLOSED_STATUS) {
                closedCollectionsPlans.put(colPlanId, newCollectionsMap.get(colPlanId));
            }
            
        }

        if(closedCollectionsPlans.isEmpty()) {
            return;
        }

        Map<Id,Task> tasksToDelete = getRelatedOpenFutureTasks(closedCollectionsPlans.keySet());
        if (Schema.sObjectType.Task.isDeletable()) {
            try {
                Database.delete(tasksToDelete.values());
                System.debug('Future open tasks deleted');
            } catch (DmlException e) {
                System.debug(e);
            }
        }
    }

    public static Map<Id,Task> getRelatedOpenFutureTasks(Set<Id> relatedToIds) {
        // Add isAccessible checks
        String [] taskAccessibleFields = new String[]{'Id',
                                                    'IsClosed',
                                                    'ActivityDate',
                                                    'WhatId'};
        DunningUtilities.checkIsAccessible('Task', taskAccessibleFields);
        return new  Map<Id,Task>([SELECT 
                                    Id, 
                                    IsClosed, 
                                    ActivityDate, 
                                    WhatId 
                                FROM Task 
                                WHERE IsClosed = false 
                                AND ActivityDate >= TODAY
                                AND WhatId IN :relatedToIds]);
    }
}