@isTest
private class DunningCollectionsTriggerHandlerTest {
    @testSetup
    private static void setup() {
        Date planStartDate = System.today();

        // Init Custom settings
        DunningSettings__c newCS = new DunningSettings__c();
        newCS.DisableTriggers__c = false;
        Database.insert(newCS);

        // Dunning Method
        DunningMethod__c dm = new DunningMethod__c(Name='Test Dunning Method');
        Database.insert(dm);

        // insert account
        Account testAcc = new Account(Name='Test Account',
                                        DunningMethod__c=dm.Id);
        Database.insert(testAcc);

        // Contact
        Contact testContact = new Contact(AccountId=testAcc.Id,
                                        FirstName='Test',
                                        LastName='User');
        Database.insert(testContact);

        CollectionsPlan__c colPlan = new CollectionsPlan__c(Status__c='Open',
                                                        StartDate__c=planStartDate,
                                                        Account__c=testAcc.Id,
                                                        DunningMethod__c=dm.Id,
                                                        CollectionsContact__c=testContact.Id);

        Database.insert(colPlan);

        // Collections Tasks
        List<Task> collectTasks = new List<Task>();
        collectTasks.add(new Task(Subject='Call -10', 
                                Description='-10',
                                Status='Not Started',
                                ActivityDate=planStartDate-10,
                                WhatId=colPlan.Id,
                                WhoId=testContact.Id));

        collectTasks.add(new Task(Subject='Email -1', 
                                Description='-1',
                                Status='Not Started', 
                                ActivityDate=planStartDate-1,
                                WhatId=colPlan.Id,
                                WhoId=testContact.Id));

        collectTasks.add(new Task(Subject='Call +10', 
                                Description='10',
                                Status='Not Started',
                                ActivityDate=planStartDate+10,
                                WhatId=colPlan.Id,
                                WhoId=testContact.Id));

        collectTasks.add(new Task(Subject='Email +1',
                                Description='1',
                                Status='Not Started', 
                                ActivityDate=planStartDate+1,
                                WhatId=colPlan.Id,
                                WhoId=testContact.Id));

        Database.insert(collectTasks);

    }

    @isTest
    private static void collectionsUpdateTest() {
        Id planId = [SELECT Id FROM CollectionsPlan__c LIMIT 1].Id;
        Map<Id,CollectionsPlan__c> oldColPlanMap = new Map<Id,CollectionsPlan__c>([SELECT 
                                            Id,
                                            Status__c,
                                            StartDate__c,
                                            Account__c,
                                            DunningMethod__c,
                                            CollectionsContact__c 
                                    FROM CollectionsPlan__c 
                                    LIMIT 1]);

        Map<Id,CollectionsPlan__c> newColPlanMap = oldColPlanMap.deepClone();
        CollectionsPlan__c newPlan = newColPlanMap.get(planId);

        newPlan.Status__c = 'Closed';


        List<Task> collectionTasks = [SELECT Id, 
                                            Subject, 
                                            Description,
                                            Status,
                                            ActivityDate,
                                            WhatId,
                                            WhoId 
                                        FROM Task];
        Integer existingTaskLength = collectionTasks.size();

        for(Task ct :collectionTasks) {
            if(ct.ActivityDate <= System.today()) {
                ct.Status = 'Completed';
            }
        }

        Database.update(collectionTasks);
        
        DunningCollectionsTriggerHandler.handleAfterUpdate(oldColPlanMap,newColPlanMap);

       List<Task> collectionTasksAfter = [SELECT Id, 
                                            Subject, 
                                            Description,
                                            Status,
                                            ActivityDate,
                                            WhatId,
                                            WhoId,
                                            IsClosed
                                        FROM Task];
        System.assert(collectionTasksAfter.size() < existingTaskLength, 'Some Tasks were closed!');
        for(Task ct :collectionTasksAfter) {
            System.assert(ct.IsClosed == true, 'Task is closed');
        }
    }


    @isTest
    private static void triggerDisablerTest() {
        // Turn off triggers in Custom settings
        DunningSettings__c existingCS = DunningSettings__c.getOrgDefaults();
        existingCS.DisableTriggers__c = true;
        Database.update(existingCS);


        List<Task> collectionTasks = [SELECT Id, 
                                            Subject, 
                                            Description,
                                            Status,
                                            ActivityDate,
                                            WhatId,
                                            WhoId 
                                        FROM Task];
        Integer existingTaskLength = collectionTasks.size();

        for(Task ct :collectionTasks) {
            if(ct.ActivityDate <= System.today()) {
                ct.Status = 'Completed';
            }
        }

        Database.update(collectionTasks);

        CollectionsPlan__c upPlan = [SELECT 
                                            Id,
                                            Status__c,
                                            StartDate__c,
                                            Account__c,
                                            DunningMethod__c,
                                            CollectionsContact__c 
                                    FROM CollectionsPlan__c 
                                    LIMIT 1];
        System.debug(upPlan);

        upPlan.Status__c = 'Closed';

        Database.update(upPlan);
        
       List<Task> collectionTasksAfter = [SELECT Id, 
                                            Subject, 
                                            Description,
                                            Status,
                                            ActivityDate,
                                            WhatId,
                                            WhoId
                                        FROM Task];

        System.debug(collectionTasksAfter);
        System.debug(existingTaskLength);
        System.debug(collectionTasksAfter.size());

        System.assert(collectionTasksAfter.size() == existingTaskLength, 'No Tasks were deleted!');
    }

    
}