/**
  - Copyright (c) 2022, salesforce.com, inc.
  - All rights reserved.
  - SPDX-License-Identifier: BSD-3-Clause
  - For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/BSD-3-Clause
 */

public with sharing class DunningUtilities {
    static final String INVOICE_STATUS = 'Posted';
    // Get Dunning Methods from accounts
    public static Map<Id, Id> getDunningIdsFromAccounts(List<Account> accountList) {

        // Account isAccessible checks - these fields get used throughout the rest of the process.
        String [] accountAccessFields = new String[]{'Id',
                                                    'blng__BillToContact__c',
                                                    'OwnerId',
                                                    'SFBD__CollectionsAgent__c',
                                                    'SFBD__CollectionsPlanDate__c',
                                                    'SFBD__CollectionsStatus__c',
                                                    'SFBD__DunningMethod__c'};
        checkIsAccessible('Account', accountAccessFields);

        Map<Id, Id> dunningIdsByAccountIds = new Map<Id, Id>();
        for(Account acc : accountList) {
            dunningIdsByAccountIds.put(acc.Id, acc.DunningMethod__c);
        }

        return dunningIdsByAccountIds;

    }

    // Get Dunning Activities
    public static Map<Id, List<DunningActivity__c>> getDunningActivities(Set<Id> dunningMethodIds) {

        // Add is accessible checks
        String [] activityAccessFields = new String[]{'Id',
                                                    'SFBD__DunningMethod__c',
                                                    'SFBD__ActivityDetails__c',
                                                    'SFBD__ActivitySubject__c',
                                                    'SFBD__OffsetDays__c'};
        checkIsAccessible('SFBD__DunningActivity__c', activityAccessFields);
 
        // safely select the activity list
        String activitySOQL = 'SELECT ' + String.join(activityAccessFields, ',') + ' FROM DunningActivity__c WHERE DunningMethod__c IN :dunningMethodIds';
        List<DunningActivity__c> activities = Database.query(activitySOQL);
        
        Map<Id, List<DunningActivity__c>> activityByDunningId = new Map<Id, List<DunningActivity__c>>();
        for(DunningActivity__c activity: activities) {
            if (activityByDunningId.containsKey(activity.DunningMethod__c)) {
                List<DunningActivity__c> existingActivities = activityByDunningId.get(activity.DunningMethod__c);
                existingActivities.add(activity);
                activityByDunningId.put(activity.DunningMethod__c, existingActivities);
            } else {
                activityByDunningId.put(activity.DunningMethod__c, new List<DunningActivity__c>{activity});
            }
        }

        return activityByDunningId;
    }


    // Create Collections Plans
    public static List<CollectionsPlan__c> createPlansFromAccounts(List<Account> accountList) {

        // isCreateable checks on Collections plan
        String [] planCreatableFields = new String[]{'SFBD__Account__c',
                                                    'SFBD__CollectionsAgent__c',
                                                    'SFBD__CollectionsContact__c',
                                                    'SFBD__DunningMethod__c',
                                                    'SFBD__StartDate__c',
                                                    'SFBD__Status__c'};

        checkIsCreateable('SFBD__CollectionsPlan__c', planCreatableFields);


        List<CollectionsPlan__c> collectionsPlansToInsert = new List<CollectionsPlan__c>();
        for (Account acct : accountList) {
            // create the collections plans

            // isAccessible checks above
            Date startDate = acct.CollectionsPlanDate__c == null ? System.today() : acct.CollectionsPlanDate__c;
            Id collectionsUser = acct.CollectionsAgent__c == null ? acct.OwnerId : acct.CollectionsAgent__c;

            // isCreateable checks above
            CollectionsPlan__c newCollection = new CollectionsPlan__c(Account__c=acct.Id,
                                                                    CollectionsAgent__c=collectionsUser,
                                                                    CollectionsContact__c=acct.blng__BillToContact__c,
                                                                    DunningMethod__c=acct.DunningMethod__c,
                                                                    StartDate__c=startDate,
                                                                    Status__c='Open');
            collectionsPlansToInsert.add(newCollection);
        }

        return collectionsPlansToInsert;
    }

    // Create Tasks from Dunning Activities
    public static List<Task> createCollectionsTasks(List<CollectionsPlan__c> collectionsPlans, Map<Id, List<DunningActivity__c>> activitiesByDunningId) {
        List<Task> collectTasks = new List<Task>();
        
        // Add is creatable checks
        String [] taskCreatableFields = new String[]{'OwnerId',
                                                    'Description',
                                                    'ActivityDate',
                                                    'WhatId',
                                                    'WhoId',
                                                    'Subject',
                                                    'Status'};
        checkIsCreateable('Task', taskCreatableFields);

        // Collections plan access checks
        String [] planAccessFields = new String[]{'Id',
                                                'SFBD__StartDate__c',
                                                'SFBD__CollectionsAgent__c',
                                                'SFBD__CollectionsContact__c'};
        checkIsAccessible('SFBD__CollectionsPlan__c', planAccessFields);

        // Dunnning Activity access checks
        String [] activityAccessFields = new String[]{'SFBD__OffsetDays__c',
                                                    'SFBD__ActivityDetails__c',
                                                    'SFBD__ActivitySubject__c'};
        checkIsAccessible('SFBD__DunningActivity__c', activityAccessFields);

        String defaultTaskStatus = getDefaultTaskStatus();

        for(CollectionsPlan__c thisCollectionsPlan : collectionsPlans) {
            List<DunningActivity__c> dunningActivities = activitiesByDunningId.get(thisCollectionsPlan.DunningMethod__c);
            // skip if no dunning Activities
            if(dunningActivities == null) {
                continue;
            }
            for(DunningActivity__c activity : dunningActivities) {
                // Create new Tasks

                // isAccessible check above
                Date taskDate = Date.valueOf(thisCollectionsPlan.StartDate__c == null ? System.today() : thisCollectionsPlan.StartDate__c);
                Integer offset = Integer.valueOf(activity.OffsetDays__c == null ? 0 : activity.OffsetDays__c);

                // isCreatable & isAccessible checks above
                Task newTask = new Task(OwnerId=thisCollectionsPlan.CollectionsAgent__c,
                                        Description=activity.ActivityDetails__c,
                                        ActivityDate=taskDate.addDays(offset),
                                        WhatId=thisCollectionsPlan.Id,
                                        WhoId=thisCollectionsPlan.CollectionsContact__c,
                                        Subject=activity.ActivitySubject__c,
                                        Status=defaultTaskStatus);

                collectTasks.add(newTask);
            }
        }

        return collectTasks;
    }

    private static String getDefaultTaskStatus() {
        String defaultVal = '';

        List <Schema.PicklistEntry> pickVals = Task.Status.getDescribe().getPicklistValues();
        for (Schema.PicklistEntry pv: pickVals) {
            if (pv.isDefaultValue()) {
                return pv.getValue();
            }
        }
        return defaultVal;
    }

    // Get Invoices from Account
    public static Map<Id, List<blng__Invoice__c>> getInvoicesByAccount(Set<Id> accountIds) {
        
        // Invoice isAccessible checks
        String [] invoiceAccessFields = new String[]{'Id',
                                                    'blng__Account__c',
                                                    'blng__InvoiceStatus__c',
                                                    'blng__DaysOutstanding__c',
                                                    'blng__Balance__c',
                                                    'SFBD__HoldCollections__c'};
        checkIsAccessible('blng__Invoice__c', invoiceAccessFields);

        /* Logic is:
         * - Invoice Status = posted, (INVOICE_STATUS string)
         * - days outstanding is 0 or more, (>= 0)
         * - hold collections is false 
         * - Balance > 0
        */
        String invoiceQuery = 'SELECT ' + String.join(invoiceAccessFields, ', ') + ' FROM blng__Invoice__c WHERE blng__Account__c IN :accountIds AND blng__InvoiceStatus__c = :INVOICE_STATUS AND blng__DaysOutstanding__c >= 0 AND HoldCollections__c = false AND blng__Balance__c > 0';
        List<blng__Invoice__c> matchingInvoices = [SELECT 
                                                        Id,
                                                        blng__Account__c,
                                                        blng__InvoiceStatus__c,
                                                        blng__DaysOutstanding__c,
                                                        blng__Balance__c,
                                                        HoldCollections__c
                                                    FROM blng__Invoice__c
                                                    WHERE blng__Account__c IN :accountIds 
                                                    AND blng__InvoiceStatus__c = :INVOICE_STATUS 
                                                    AND blng__DaysOutstanding__c >= 0 
                                                    AND HoldCollections__c = false 
                                                    AND blng__Balance__c > 0];

        Map<Id, List<blng__Invoice__c>> invoicesByAccountId = new Map<Id, List<blng__Invoice__c>>();
        for(blng__Invoice__c inv: matchingInvoices) {
            if (invoicesByAccountId.containsKey(inv.blng__Account__c)) {
                List<blng__Invoice__c> existingInvs = invoicesByAccountId.get(inv.blng__Account__c);
                existingInvs.add(inv);
                invoicesByAccountId.put(inv.blng__Account__c, existingInvs);
            } else {
                invoicesByAccountId.put(inv.blng__Account__c, new List<blng__Invoice__c>{inv});
            }
        }

        return invoicesByAccountId;
    }


    // Get Invoices from matching Collections Plans
    public static Map<Id, List<blng__Invoice__c>> getInvoicesFromCollections(Map<Id,CollectionsPlan__c> plansByAccountId) {
        Set<Id> accountIds = plansByAccountId.keySet();
        // Invoice isAccessible checks
        String [] invoiceAccessFields = new String[]{'Id',
                                                    'blng__Account__c',
                                                    'blng__InvoiceStatus__c',
                                                    'blng__DueDate__c',
                                                    'blng__Balance__c',
                                                    'SFBD__HoldCollections__c'};
        checkIsAccessible('blng__Invoice__c', invoiceAccessFields);

        /* Logic is:
         * - Invoice Status = posted, (INVOICE_STATUS string)
         * - Filter by collection plan later for date
         * - hold collections is false 
         * - Balance > 0
        */
        String invoiceQuery = 'SELECT ' + String.join(invoiceAccessFields, ', ') + ' FROM blng__Invoice__c WHERE blng__Account__c IN :accountIds AND blng__InvoiceStatus__c = :INVOICE_STATUS AND HoldCollections__c = false AND blng__Balance__c > 0';
        List<blng__Invoice__c> matchingInvoices = Database.query(invoiceQuery);

        Map<Id, List<blng__Invoice__c>> invoicesByAccountId = new Map<Id, List<blng__Invoice__c>>();
        // new logic needs to only add invoices where the due date on the invoice is <= the collections plan date
        for(blng__Invoice__c inv: matchingInvoices) {
            CollectionsPlan__c accCollectPlan = plansByAccountId.get(inv.blng__Account__c);
            // skip this invoice if the due date is beyond the plan start date
            if(inv.blng__DueDate__c > accCollectPlan.StartDate__c) {
                continue;
            }
            // check and add it to the list
            if (invoicesByAccountId.containsKey(inv.blng__Account__c)) {
                List<blng__Invoice__c> existingInvs = invoicesByAccountId.get(inv.blng__Account__c);
                existingInvs.add(inv);
                invoicesByAccountId.put(inv.blng__Account__c, existingInvs);
            } else {
                invoicesByAccountId.put(inv.blng__Account__c, new List<blng__Invoice__c>{inv});
            }
        }

        

        return invoicesByAccountId;
    }

    // get list of junction objects
    public static List<CollectionsInvoice__c> createPlanInvoiceJunctions(Map<Id,CollectionsPlan__c> plansByAccountId, Map<Id, List<blng__Invoice__c>> invoicesByAccountId) {

        // isCreateable checks on CollectionsInvoice__c
        String [] colInvCreateFields = new String[]{'SFBD__CollectionsPlan__c',
                                                    'SFBD__Invoice__c',
                                                    'SFBD__InvoiceBalance__c'};
        checkIsCreateable('SFBD__CollectionsInvoice__c', colInvCreateFields);

        List<CollectionsInvoice__c> invJxns = new List<CollectionsInvoice__c>();

        // loop through and create junction objects between Collections Plans and Invoices
        for(Id acctId : plansByAccountId.keySet()) {
            CollectionsPlan__c collectPlan = plansByAccountId.get(acctId);
            List<blng__Invoice__c> accInvs = invoicesByAccountId.get(acctId);

            // skip to the next account if no Invoices
            if(accInvs == null) {
                continue;
            }

            for(blng__Invoice__c inv : accInvs) {
                // isCreatable checks above
                invJxns.add(new CollectionsInvoice__c(CollectionsPlan__c=collectPlan.Id,
                                                    Invoice__c=inv.Id,
                                                    InvoiceBalance__c=inv.blng__Balance__c));
            }
        }

        return invJxns;
    }


    public static void checkIsAccessible(String obj, String[] fieldsToCheck) {
        System.debug('Object: ' + obj);
        System.debug('Create Fields: ' + String.join(fieldsToCheck, ', '));	
        SObjectType objType = Schema.getGlobalDescribe().get(obj);
        Map<String,Schema.SObjectField> m = objType.getDescribe().fields.getMap();

        for (String fieldToCheck : fieldsToCheck) {
            // Check if the user has access to view field
            if (!m.get(fieldToCheck).getDescribe().isAccessible()) {
                // Pass error back
                System.debug('No access for :: ' + obj + '.' + fieldToCheck);
                throw new System.NoAccessException();
            }
        }
    }

    public static void checkIsCreateable(String obj, String[] fieldsToCheck) {	
        System.debug('Object: ' + obj);
        System.debug('Create Fields: ' + String.join(fieldsToCheck, ', '));
        SObjectType objType = Schema.getGlobalDescribe().get(obj);
        Map<String,Schema.SObjectField> m = objType.getDescribe().fields.getMap();

        for (String fieldToCheck : fieldsToCheck) {
            // Check if the user has access to view field
            if (!m.get(fieldToCheck).getDescribe().isCreateable()) {
                // Pass error back
                System.debug('Not createable :: ' + obj + '.' + fieldToCheck);
                throw new System.NoAccessException();
            }
        }
    }
}