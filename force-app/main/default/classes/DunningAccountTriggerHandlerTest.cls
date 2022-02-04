@isTest
private class DunningAccountTriggerHandlerTest {
    @testSetup
    private static void setup() {
        // Init Custom settings
        DunningSettings__c newCS = new DunningSettings__c();
        newCS.DisableTriggers__c = false;
        Database.insert(newCS);

        // Dunning Method
        DunningMethod__c dm = new DunningMethod__c(Name='Test Dunning Method');
        Database.insert(dm);

        // Dunning Activities
        List<DunningActivity__c> actvs = new List<DunningActivity__c>();
        actvs.add(new DunningActivity__c(Name='Test Call',
                                        ActivitySubject__c='Call', 
                                        ActivityDetails__c='Call the customer',
                                        OffsetDays__c=3,
                                        DunningMethod__c=dm.Id));

        actvs.add(new DunningActivity__c(Name='Test Email',
                                        ActivitySubject__c='Email', 
                                        ActivityDetails__c='Email the customer',
                                        OffsetDays__c=2,
                                        DunningMethod__c=dm.Id));

        Database.insert(actvs);

        // insert account
        Account testAcc = new Account(Name='Test Account',
                                        DunningMethod__c=dm.Id);
        Database.insert(testAcc);

        // Contact
        Contact testContact = new Contact(AccountId=testAcc.Id,
                                        FirstName='Test',
                                        LastName='User');
        Database.insert(testContact);

        // Invoice
        blng__Invoice__c inv = new blng__Invoice__c(blng__Account__c=testAcc.Id,
                                                    blng__InvoiceStatus__c='Posted',
                                                    blng__DueDate__c=System.today().addDays(-2));
        Database.insert(inv);

        // Invoice Line
        blng__InvoiceLine__c invLine = new blng__InvoiceLine__c(blng__Invoice__c=inv.Id,
                                                                Name='Test Product',
                                                                blng__Quantity__c=1,
                                                                blng__UnitPrice__c=50,
                                                                blng__Subtotal__c=50,
                                                                blng__TaxAmount__c=0,
                                                                blng__TotalAmount__c=50);
        Database.insert(invLine);
    }

    @isTest
    private static void inCollectionsUpdateTest() {
        Id accId = [SELECT Id FROM Account LIMIT 1].Id;
        Map<Id,Account> oldAccountMap = new Map<Id,Account>([SELECT 
                                                                Id, 
                                                                Name, 
                                                                DunningMethod__c, 
                                                                CollectionsPlanDate__c,
                                                                CollectionsAgent__c,
                                                                CollectionsStatus__c,
                                                                OwnerId,
                                                                blng__BillToContact__c
                                                            FROM Account 
                                                            LIMIT 1]);
        

        Map<Id,Account> newAccountMap = oldAccountMap.deepClone();
        Account newAcc = newAccountMap.get(accId);

        newAcc.CollectionsStatus__c = 'In Collections';
        
        DunningAccountTriggerHandler.handleAfterUpdate(oldAccountMap,newAccountMap);

        List<CollectionsPlan__c> collectPlan = [SELECT Id FROM CollectionsPlan__c];
        System.assert(collectPlan.size()>0, 'Collection Plans were created!');

        List<Task> collectionTasks = [SELECT Id FROM Task];
        System.assert(collectionTasks.size()>0, 'Tasks were created!');

        List<CollectionsInvoice__c> collectJXNs = [SELECT Id, CollectionsPlan__c, Invoice__c FROM CollectionsInvoice__c];
        System.assert(collectJXNs.size()>0, 'Junctions were created!');
    }

    @isTest
    private static void notInCollectionsUpdateTest() {
        Id accId = [SELECT Id FROM Account LIMIT 1].Id;
        Map<Id,Account> oldAccountMap = new Map<Id,Account>([SELECT 
                                                                Id, 
                                                                Name, 
                                                                DunningMethod__c, 
                                                                CollectionsPlanDate__c,
                                                                CollectionsAgent__c,
                                                                CollectionsStatus__c,
                                                                OwnerId,
                                                                blng__BillToContact__c
                                                            FROM Account 
                                                            LIMIT 1]);
        

        Map<Id,Account> newAccountMap = oldAccountMap.deepClone();
        
        // Testing where account is not in collections
        DunningAccountTriggerHandler.handleAfterUpdate(oldAccountMap,newAccountMap);

        List<CollectionsPlan__c> collectPlan = [SELECT Id FROM CollectionsPlan__c];
        System.assert(collectPlan.size() == 0, 'No Collection Plans were created!');

        List<Task> collectionTasks = [SELECT Id FROM Task];
        System.assert(collectionTasks.size() == 0, 'No Tasks were created!');

        List<CollectionsInvoice__c> collectJXNs = [SELECT Id, CollectionsPlan__c, Invoice__c FROM CollectionsInvoice__c];
        System.assert(collectJXNs.size() == 0, 'No Junctions were created!');
    }

    @isTest
    private static void noDunningUpdateTest() {
        Id accId = [SELECT Id FROM Account LIMIT 1].Id;
        Map<Id,Account> oldAccountMap = new Map<Id,Account>([SELECT 
                                                                Id, 
                                                                Name, 
                                                                DunningMethod__c, 
                                                                CollectionsPlanDate__c,
                                                                CollectionsAgent__c,
                                                                CollectionsStatus__c,
                                                                OwnerId,
                                                                blng__BillToContact__c
                                                            FROM Account 
                                                            LIMIT 1]);
        

        Map<Id,Account> newAccountMap = oldAccountMap.deepClone();

        Account newAcc = newAccountMap.get(accId);
        // set dunning method to null
        newAcc.DunningMethod__c = null;
        
        // Testing where account does not have a dunning method associated
        DunningAccountTriggerHandler.handleAfterUpdate(oldAccountMap,newAccountMap);

        List<CollectionsPlan__c> collectPlan = [SELECT Id FROM CollectionsPlan__c];
        System.assert(collectPlan.size() == 0, 'No Collection Plans were created!');

        List<Task> collectionTasks = [SELECT Id FROM Task];
        System.assert(collectionTasks.size() == 0, 'No Tasks were created!');

        List<CollectionsInvoice__c> collectJXNs = [SELECT Id, CollectionsPlan__c, Invoice__c FROM CollectionsInvoice__c];
        System.assert(collectJXNs.size() == 0, 'No Junctions were created!');
    }

    @isTest
    private static void triggerDisablerTest() {
        // Turn off triggers in Custom settings
        DunningSettings__c existingCS = DunningSettings__c.getOrgDefaults();
        existingCS.DisableTriggers__c = true;
        Database.update(existingCS);

        // update account
        Account testAcc = [SELECT 
                                Id, 
                                Name, 
                                DunningMethod__c, 
                                CollectionsPlanDate__c,
                                CollectionsAgent__c,
                                CollectionsStatus__c,
                                OwnerId,
                                blng__BillToContact__c
                            FROM Account 
                            LIMIT 1];
        testAcc.DunningMethod__c = null;
        Database.update(testAcc);

        List<CollectionsPlan__c> collectPlan = [SELECT Id FROM CollectionsPlan__c];
        System.assert(collectPlan.size() == 0, 'No Collection Plans were created!');

        List<Task> collectionTasks = [SELECT Id FROM Task];
        System.assert(collectionTasks.size() == 0, 'No Tasks were created!');

        List<CollectionsInvoice__c> collectJXNs = [SELECT Id, CollectionsPlan__c, Invoice__c FROM CollectionsInvoice__c];
        System.assert(collectJXNs.size() == 0, 'No Junctions were created!');
    }
}