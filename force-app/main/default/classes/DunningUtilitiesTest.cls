/**
  - Copyright (c) 2022, salesforce.com, inc.
  - All rights reserved.
  - SPDX-License-Identifier: BSD-3-Clause
  - For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/BSD-3-Clause
 */

@isTest
private class DunningUtilitiesTest {
    @testSetup
    private static void setup() {

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
    private static void getDunningIdsFromAccountsTest() {
        List<Account> accountList = [SELECT 
                                            Id, 
                                            Name, 
                                            DunningMethod__c,
                                            CollectionsPlanDate__c,
                                            CollectionsAgent__c,
                                            blng__BillToContact__c
                                        FROM Account 
                                        LIMIT 1];

        Map<Id, Id> dunningByAccIds = DunningUtilities.getDunningIdsFromAccounts(accountList);

        // Expect that we get 1 element back in the map
        System.assertEquals(1, dunningByAccIds.size(), 'Got back 1 Account');

        for(Id keyId : dunningByAccIds.keySet()) {
            // Expect to have a Dunning Method for every Account, else there is nothing to generate the collections plans from
            System.assert(dunningByAccIds.get(keyId) != null, 'Non-null value for Account Dunning Method');
        }

    }

    @isTest
    private static void getDunningActivitiesTest() {
        Map<Id, DunningMethod__c> dunningMap = new Map<Id, DunningMethod__c>([SELECT Id, Name FROM DunningMethod__c LIMIT 1]);
        Map<Id, List<DunningActivity__c>> activityByMethodIds = DunningUtilities.getDunningActivities(dunningMap.keySet());

        for (Id dunningId : dunningMap.keySet()) {
            List<DunningActivity__c> activitiesForMethod = [SELECT
                                                                Id,
                                                                DunningMethod__c
                                                            FROM DunningActivity__c 
                                                            WHERE DunningMethod__c = :dunningId];

            // Expect that the list sizes are equal for the returned map and the SOQL select
            System.assertEquals(activitiesForMethod.size(), activityByMethodIds.get(dunningId).size(), 'Activity List lengths are equal');
        }
    }

    
    @isTest
    private static void createPlansFromAccountsTest() {

        List<Account> accountList = [SELECT 
                                        Id, 
                                        Name, 
                                        DunningMethod__c,
                                        CollectionsPlanDate__c,
                                        CollectionsAgent__c,
                                        blng__BillToContact__c,
                                        OwnerId
                                    FROM Account 
                                    LIMIT 1];

        List<CollectionsPlan__c> colPlan = DunningUtilities.createPlansFromAccounts(accountList);

        System.assertEquals(1, colPlan.size(), 'Got 1 Collections Plan');

    }

    @isTest
    private static void createCollectionsTasksTest() {

        Account acct = [SELECT 
                            Id, 
                            Name, 
                            DunningMethod__c,
                            CollectionsPlanDate__c,
                            CollectionsAgent__c,
                            blng__BillToContact__c
                        FROM Account 
                        LIMIT 1];

        List<CollectionsPlan__c> collectPlans = new List<CollectionsPlan__c>();
        collectPlans.add(new CollectionsPlan__c(Account__c=acct.Id,
                                                CollectionsAgent__c=UserInfo.getUserId(),
                                                DunningMethod__c=acct.DunningMethod__c,
                                                StartDate__c=System.Today(),
                                                Status__c='Open'));

        Database.insert(collectPlans);

        Set<Id> dunningSet = new Set<Id>{acct.DunningMethod__c};
        Map<Id, List<DunningActivity__c>> activityByMethodIds = DunningUtilities.getDunningActivities(dunningSet);
        
        List<Task> collectionTasks = DunningUtilities.createCollectionsTasks(collectPlans, activityByMethodIds);
        List<DunningActivity__c> dunActs = activityByMethodIds.get(acct.DunningMethod__c);
        System.assertEquals(dunActs.size(), collectionTasks.size(), 'Equal number of Tasks and Dunning Activities');

    }

    @isTest
    private static void getInvoicesByAccountTest() {
        Account acct = [SELECT 
                            Id, 
                            Name, 
                            DunningMethod__c,
                            CollectionsPlanDate__c,
                            CollectionsAgent__c,
                            blng__BillToContact__c
                        FROM Account 
                        LIMIT 1];

        List<blng__Invoice__c> invoices = [SELECT 
                                                Id,
                                                blng__Account__c
                                            FROM blng__Invoice__c
                                            WHERE blng__Account__c = :acct.Id];

        Set<Id> accSet = new Set<Id>{acct.Id};
        Map<Id, List<blng__Invoice__c>> matchingInvoicesMap = DunningUtilities.getInvoicesByAccount(accSet);

        System.assertEquals(invoices.size(), matchingInvoicesMap.get(acct.Id).size(), 'Invoices List matches the expected return');

    }

    @isTest
    private static void createPlanInvoiceJunctionsTest() {
        Account acct = [SELECT 
                            Id, 
                            Name, 
                            DunningMethod__c,
                            blng__BillToContact__c
                        FROM Account 
                        LIMIT 1];

        CollectionsPlan__c collectPlan = new CollectionsPlan__c(Account__c=acct.Id,
                                                                CollectionsAgent__c=UserInfo.getUserId(),
                                                                DunningMethod__c=acct.DunningMethod__c,
                                                                StartDate__c=System.Today(),
                                                                Status__c='Open');

        Database.insert(collectPlan);
        Map<Id,CollectionsPlan__c> plansToAcc = new Map<Id,CollectionsPlan__c>{acct.Id => collectPlan};
        Set<Id> accSet = new Set<Id>{acct.Id};
        Map<Id, List<blng__Invoice__c>> matchingInvoicesMap = DunningUtilities.getInvoicesByAccount(accSet);
        List<CollectionsInvoice__c> collectJXNs = DunningUtilities.createPlanInvoiceJunctions(plansToAcc, matchingInvoicesMap);

        System.assertEquals(matchingInvoicesMap.get(acct.Id).size(), collectJXNs.size(), 'Junction Object created for each Invoice that matched');
    }

    // Test that tasks get assigned to collections agent

    // Test if no Dunning activities exist
    @isTest
    private static void noActivitiesTasksTest() {

        Account acct = [SELECT 
                            Id, 
                            Name, 
                            DunningMethod__c,
                            CollectionsPlanDate__c,
                            CollectionsAgent__c,
                            blng__BillToContact__c
                        FROM Account 
                        LIMIT 1];

        DunningMethod__c dmna = new DunningMethod__c(Name='Test Method with no Activities');
        Database.insert(dmna);

        acct.DunningMethod__c = dmna.Id;
        Database.update(acct);

        List<CollectionsPlan__c> collectPlans = new List<CollectionsPlan__c>();
        collectPlans.add(new CollectionsPlan__c(Account__c=acct.Id,
                                                CollectionsAgent__c=UserInfo.getUserId(),
                                                DunningMethod__c=dmna.Id,
                                                StartDate__c=System.Today(),
                                                Status__c='Open'));

        Database.insert(collectPlans);

        Set<Id> dunningSet = new Set<Id>{dmna.Id};
        Map<Id, List<DunningActivity__c>> activityByMethodIds = DunningUtilities.getDunningActivities(dunningSet);
        
        List<Task> collectionTasks = DunningUtilities.createCollectionsTasks(collectPlans, activityByMethodIds);

        System.assertEquals(null, activityByMethodIds.get(dmna.Id), 'No Dunning Activities');

    }

    // Test if no Invoices match / are posted

// Test if no Invoices exist
    @isTest
    private static void noInvoicesTest() {

// Dunning Method
        DunningMethod__c dm = new DunningMethod__c(Name='Test Method 1 act');
        Database.insert(dm);

        // Dunning Activities
        List<DunningActivity__c> actvs = new List<DunningActivity__c>();
        actvs.add(new DunningActivity__c(Name='Test Call',
                                        ActivitySubject__c='Call', 
                                        ActivityDetails__c='Call the customer',
                                        OffsetDays__c=3,
                                        DunningMethod__c=dm.Id));

        Database.insert(actvs);

        // insert account
        Account testAcc = new Account(Name='Test Account',
                                        DunningMethod__c=dm.Id);
        Database.insert(testAcc);


        CollectionsPlan__c collectPlan = new CollectionsPlan__c(Account__c=testAcc.Id,
                                                                CollectionsAgent__c=UserInfo.getUserId(),
                                                                DunningMethod__c=testAcc.DunningMethod__c,
                                                                StartDate__c=System.Today(),
                                                                Status__c='Open');

        Database.insert(collectPlan);

        Map<Id,CollectionsPlan__c> plansToAcc = new Map<Id,CollectionsPlan__c>{testAcc.Id => collectPlan};
        Set<Id> accSet = new Set<Id>{testAcc.Id};
        Map<Id, List<blng__Invoice__c>> matchingInvoicesMap = DunningUtilities.getInvoicesByAccount(accSet);
        System.assertEquals(null, matchingInvoicesMap.get(testAcc.Id), 'No Invoices found');

        List<CollectionsInvoice__c> collectJXNs = DunningUtilities.createPlanInvoiceJunctions(plansToAcc, matchingInvoicesMap);
        System.assertEquals(0, collectJXNs.size(), 'No Junction Objects created');
    }


    // Test if 2 Invoices exist
    @isTest
    private static void twoInvoicesTest() {

// Dunning Method
        DunningMethod__c dm = new DunningMethod__c(Name='Test Method 1 act');
        Database.insert(dm);

        // Dunning Activities
        List<DunningActivity__c> actvs = new List<DunningActivity__c>();
        actvs.add(new DunningActivity__c(Name='Test Call',
                                        ActivitySubject__c='Call', 
                                        ActivityDetails__c='Call the customer',
                                        OffsetDays__c=3,
                                        DunningMethod__c=dm.Id));

        Database.insert(actvs);

        // insert account
        Account testAcc = new Account(Name='Test Account',
                                        DunningMethod__c=dm.Id);
        Database.insert(testAcc);

        // Invoice
        List<blng__Invoice__c> invs = new List<blng__Invoice__c>();
        invs.add(new blng__Invoice__c(blng__Account__c=testAcc.Id,
                                    blng__InvoiceStatus__c='Posted',
                                    blng__DueDate__c=System.today().addDays(-5)));
        invs.add(new blng__Invoice__c(blng__Account__c=testAcc.Id,
                                    blng__InvoiceStatus__c='Posted',
                                    blng__DueDate__c=System.today().addDays(-2)));
        Database.insert(invs);


        // Add Invoice Lines
        List<blng__InvoiceLine__c> invLines = new List<blng__InvoiceLine__c>();
        for(blng__Invoice__c inv : invs) {
        // Invoice Line
        invLines.add(new blng__InvoiceLine__c(blng__Invoice__c=inv.Id,
                                            Name='Test Product',
                                            blng__Quantity__c=1,
                                            blng__UnitPrice__c=50,
                                            blng__Subtotal__c=50,
                                            blng__TaxAmount__c=0,
                                            blng__TotalAmount__c=50));

        }

        Database.insert(invLines);


        CollectionsPlan__c collectPlan = new CollectionsPlan__c(Account__c=testAcc.Id,
                                                                CollectionsAgent__c=UserInfo.getUserId(),
                                                                DunningMethod__c=testAcc.DunningMethod__c,
                                                                StartDate__c=System.Today(),
                                                                Status__c='Open');

        Database.insert(collectPlan);

        Map<Id,CollectionsPlan__c> plansToAcc = new Map<Id,CollectionsPlan__c>{testAcc.Id => collectPlan};
        Set<Id> accSet = new Set<Id>{testAcc.Id};
        Map<Id, List<blng__Invoice__c>> matchingInvoicesMap = DunningUtilities.getInvoicesByAccount(accSet);
        System.assertEquals(2, matchingInvoicesMap.get(testAcc.Id).size(), '2 Invoices found');

        List<CollectionsInvoice__c> collectJXNs = DunningUtilities.createPlanInvoiceJunctions(plansToAcc, matchingInvoicesMap);
        System.assertEquals(2, collectJXNs.size(), '2 Junction Objects created');
    }

    @isTest
    private static void getInvoicesFromCollectionsTest() {
        Account acct = [SELECT 
                            Id, 
                            Name, 
                            DunningMethod__c,
                            blng__BillToContact__c
                        FROM Account 
                        LIMIT 1];
                        

        CollectionsPlan__c collectPlan = new CollectionsPlan__c(Account__c=acct.Id,
                                                                CollectionsAgent__c=UserInfo.getUserId(),
                                                                DunningMethod__c=acct.DunningMethod__c,
                                                                StartDate__c=System.Today(),
                                                                Status__c='Open');

        Database.insert(collectPlan);
        Map<Id,CollectionsPlan__c> plansToAcc = new Map<Id,CollectionsPlan__c>{acct.Id => collectPlan};
        Set<Id> accSet = new Set<Id>{acct.Id};
        Map<Id, List<blng__Invoice__c>> matchingInvoicesMap = DunningUtilities.getInvoicesFromCollections(plansToAcc);
        List<CollectionsInvoice__c> collectJXNs = DunningUtilities.createPlanInvoiceJunctions(plansToAcc, matchingInvoicesMap);

        System.assertEquals(matchingInvoicesMap.get(acct.Id).size(), collectJXNs.size(), 'Junction Object created for each Invoice that matched');
    }



    @isTest
    private static void getFutureInvoicesFromCollectionsTest() {
        Account acct = [SELECT 
                            Id, 
                            Name, 
                            DunningMethod__c,
                            blng__BillToContact__c
                        FROM Account 
                        LIMIT 1];


        // Invoice
        List<blng__Invoice__c> invs = new List<blng__Invoice__c>();
        // 5 days out
        invs.add(new blng__Invoice__c(blng__Account__c=acct.Id,
                                    blng__InvoiceStatus__c='Posted',
                                    blng__DueDate__c=System.today().addDays(5)));

        // 15 days out
        invs.add(new blng__Invoice__c(blng__Account__c=acct.Id,
                                    blng__InvoiceStatus__c='Posted',
                                    blng__DueDate__c=System.today().addDays(15)));
        Database.insert(invs);


        // Add Invoice Lines
        List<blng__InvoiceLine__c> invLines = new List<blng__InvoiceLine__c>();
        for(blng__Invoice__c inv : invs) {
        // Invoice Line
        invLines.add(new blng__InvoiceLine__c(blng__Invoice__c=inv.Id,
                                            Name='Test Product',
                                            blng__Quantity__c=1,
                                            blng__UnitPrice__c=50,
                                            blng__Subtotal__c=50,
                                            blng__TaxAmount__c=0,
                                            blng__TotalAmount__c=50));

        }

        Database.insert(invLines);
                        
        // 10 days out collections
        CollectionsPlan__c collectPlan = new CollectionsPlan__c(Account__c=acct.Id,
                                                                CollectionsAgent__c=UserInfo.getUserId(),
                                                                DunningMethod__c=acct.DunningMethod__c,
                                                                StartDate__c=System.Today()+10,
                                                                Status__c='Open');

        Database.insert(collectPlan);
        Map<Id,CollectionsPlan__c> plansToAcc = new Map<Id,CollectionsPlan__c>{acct.Id => collectPlan};
        Set<Id> accSet = new Set<Id>{acct.Id};
        // have 3 invoices now, 1 already past due, 1 that should be within the startdate and 1 in the future
        Map<Id, List<blng__Invoice__c>> matchingInvoicesMap = DunningUtilities.getInvoicesFromCollections(plansToAcc);
        System.assertEquals(2, matchingInvoicesMap.get(acct.Id).size(), '2 matching invoices returned');

        List<CollectionsInvoice__c> collectJXNs = DunningUtilities.createPlanInvoiceJunctions(plansToAcc, matchingInvoicesMap);
        System.assertEquals(matchingInvoicesMap.get(acct.Id).size(), collectJXNs.size(), 'Junction Object created for each Invoice that matched');
    }
}