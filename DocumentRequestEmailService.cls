global class DocumentRequestEmailService implements Messaging.InboundEmailHandler {
 
	global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope env) {

//TODO: error handling - add error to task?

		Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
  
		String emailText = String.isNotBlank(email.plainTextBody) ? email.plainTextBody : '';
		
		if (String.isNotBlank(email.replyTo)) {
			emailText += '\nReply To: ' + email.replyTo; 
		}

		if (email.references != null) {
			emailText += '\nReferences: ' + String.join(email.references,', '); 
		}

		String docRequestId;
		
		// find the document request reference in the subject line
		if (String.isNotBlank(email.Subject)) {
			Pattern ref = Pattern.compile('.*\\[ref:(DR-\\d{6,9})\\]');
			Matcher m = ref.matcher(email.Subject);
			if (m.matches() && m.hitEnd()) {
				docRequestId = m.group(1);
			}
		}
				
		try {
			
			Contact vCon = 
				[SELECT Id, Name, Email
        		FROM Contact
        		WHERE Email = 'cmattheo@tcfbank.com' //:email.fromAddress
        		LIMIT 1];

			// find the original doc request        	
        	List<Document_Request__c> docRequest;
        	if (String.isNotBlank(docRequestId)) {
        		docRequest = 
	        		[SELECT Id, Opportunity__r.AccountId,
    					(SELECT Id, Subject, Status From OpenActivities)
    	    		FROM Document_Request__c
        			WHERE Name = :docRequestId];
        	}
        		
      		// Add a new Task to the contact record we just found above.
      		Task newTask = new Task (
      			Description =  emailText,
           		Priority = 'Normal',
           		Status = 'Completed',
           		Subject = email.subject,
           		IsReminderSet = true,
           		ReminderDateTime = System.now()+1,
           		WhoId =  vCon.Id,
           		ActivityDate = Date.today()
           	);
           	
           	if (!docRequest.isEmpty()) {
           		newTask.WhatId = docRequest[0].Id;
           	}
     
     		// Insert the new Task 
     		insert newTask;
     		
			// add the attachments to the task and the  
   			List<ContentVersion> files = new List<ContentVersion>();
   			if (email.binaryAttachments != null) {
	     		for (Messaging.InboundEmail.BinaryAttachment attachment : email.binaryAttachments) {
	     			ContentVersion file = new ContentVersion (
	     				PathOnClient = attachment.fileName,
		               	Title = attachment.fileName,
						Origin = 'C',
						VersionData = attachment.body, 
						Placeholder__c = 'Uploaded Document',
						Group__c = 'Shared File',
						Category__c = 'Requested Document'
	     			);
	     			files.add(file);
	     		}
   			}
     		
     		if (!files.isEmpty()) {
				
				Savepoint sp = Database.setSavepoint();

				try {
					
					insert files;
					
   					files = 
   						[SELECT Id, ContentDocumentId
            			FROM ContentVersion
            			WHERE Id IN :files];
            			
            		List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            		
            		for (ContentVersion file : files) {
            		
            			// link to the task
            			links.add(new ContentDocumentLink (
							LinkedEntityId = newTask.Id,
            				ShareType = 'I',
            				ContentDocumentId = file.ContentDocumentId
        				));
				        links.add(new ContentDocumentLink (
//TODO: link internally vs. org-wide?				        
							LinkedEntityId = UserInfo.getOrganizationId(),
				            ShareType = 'C',
				            ContentDocumentId = file.ContentDocumentId
				        ));
				        
				        // link to the document request if found
				        if (!docRequest.isEmpty()) {
	            			links.add(new ContentDocumentLink (
								LinkedEntityId = docRequest[0].Id,
	            				ShareType = 'I',
	            				ContentDocumentId = file.ContentDocumentId
	        				));
	        				links.add(new ContentDocumentLink (
								LinkedEntityId = docRequest[0].Opportunity__r.AccountId,
            					ShareType = 'I',
            					ContentDocumentId = file.ContentDocumentId,
            					Visibility = 'AllUsers'
        					)); 
				        }
					
            		}

					insert links;
					
					docRequest[0].Date_Received__c = Date.today();
					update docRequest[0];
					
					DocumentRequestUploadController.completeTasks(docRequest[0]);

				} catch (Exception e) {
					Database.rollback(sp);
					System.debug(e.getMessage());
				}     			
     			
     		}    
     		
    	} catch (QueryException e) {
			System.debug('Query Issue: ' + e);
		}
   
		result.success = true;
   
   		return result;
	}
	
}