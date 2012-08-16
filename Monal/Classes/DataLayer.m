//
//  DataLayer.m
//  SworIM
//
//  Created by Anurodh Pokharel on 3/28/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "DataLayer.h"


@implementation DataLayer

static DataLayer *sharedInstance=nil;

+ (DataLayer* )sharedInstance
{
    if (sharedInstance == nil) {
        sharedInstance = [DataLayer alloc] ;
        [sharedInstance initDB];
    }
    
    return sharedInstance;
}


//lowest level command handlers
-(NSObject*) executeScalar:(NSString*) query
{/*
	sqlite3_stmt *statement1;
	if (sqlite3_prepare_v2(database, [@"begin"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement1, NULL) == SQLITE_OK) {
		sqlite3_step(statement1);
	}
	*/
	
	sqlite3_stmt *statement;
	if (sqlite3_prepare_v2(database, [query  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK) {
		if (sqlite3_step(statement) == SQLITE_ROW)
		{
			//debug_NSLog(@"got a row"); 
			//get type
			switch(sqlite3_column_type(statement,0))
			{
					// SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_BLOB, or SQLITE_NULL
				case (SQLITE_INTEGER):
				{
					NSNumber* returnInt= [NSNumber numberWithInt:sqlite3_column_int(statement,0)];
					while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
					/*sqlite3_stmt *statement2;
					if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
						sqlite3_step(statement2);
					}*/
					return returnInt; 
				}
					
				case (SQLITE_FLOAT):
				{
					NSNumber* returnInt= [NSNumber numberWithDouble:sqlite3_column_double(statement,0)];
						while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
				/*	sqlite3_stmt *statement2;
					if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
						sqlite3_step(statement2);
					}*/
					return returnInt;
				}
					
				case (SQLITE_TEXT):
				{
					NSString* returnString = [NSString stringWithUTF8String:sqlite3_column_text(statement,0)];
					//	debug_NSLog(@"got %@", returnString); 
							while(sqlite3_step(statement)== SQLITE_ROW ){} //clear
					/*sqlite3_stmt *statement2;
					 if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
					 sqlite3_step(statement2);
					 }*/
					return [returnString  stringByReplacingOccurrencesOfString:@"''" withString:@"'"]; 
					
				}
					
			    case (SQLITE_BLOB):
				{
					//trat as string for now 					
					NSString* returnString = [NSString stringWithUTF8String:sqlite3_column_text(statement,0)];
					//	debug_NSLog(@"got %@", returnString); 
							while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
					/*sqlite3_stmt *statement2;
					 if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
					 sqlite3_step(statement2);
					 }*/
					return [returnString  stringByReplacingOccurrencesOfString:@"''" withString:@"'"]; 

					
					
					//Note: add blob support later 
					
					//char* data= sqlite3_value_text(statement); 
					///NSData* returnData =[NSData dataWithBytes:]
					return nil;
				}
				
				case (SQLITE_NULL):
				{
					debug_NSLog(@"return nil with sql null"); 
									while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
					/*sqlite3_stmt *statement2;
					 if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
					 sqlite3_step(statement2);
					 }*/
					return nil;
				}
					
			
					
			}
			
		
		
		} else 	
		{debug_NSLog(@"return nil with no row"); 
			/*sqlite3_stmt *statement2;
			 if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
			 sqlite3_step(statement2);
			 }*/
			return nil;}; 
	}
	//if noting else
	debug_NSLog(@"returning nil with out OK %@", query); 
	/*sqlite3_stmt *statement2;
	 if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
	 sqlite3_step(statement2);
	 }*/
	
	return nil;
}
-(BOOL) executeNonQuery:(NSString*) query
{
	
	/*sqlite3_stmt *statement1;
	if (sqlite3_prepare_v2(database, [@"begin"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement1, NULL) == SQLITE_OK) {
		sqlite3_step(statement1);
	}*/
	bool val=false; 
	sqlite3_stmt *statement;
	if (sqlite3_prepare_v2(database, [query  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK) 
	{
		if(sqlite3_step(statement)==SQLITE_DONE) 
		val=true;
		else 
			val=false;
	}	
	
	else 
	{
		debug_NSLog(@"nonquery returning false with out OK %@", query); 
		val=false;
	}
	
	
	/*sqlite3_stmt *statement2;
	 if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
	 sqlite3_step(statement2);
	 }*/
	return val; 
}


-(NSArray*) executeReader:(NSString*) query
{	

	/*sqlite3_stmt *statement1;
	if (sqlite3_prepare_v2(database, [@"begin"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement1, NULL) == SQLITE_OK) {
		sqlite3_step(statement1);
	}
	*/
	
	NSMutableArray* toReturn =  [[NSMutableArray alloc] init] ; 
	sqlite3_stmt *statement;
	if (sqlite3_prepare_v2(database, [query cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK) {
	
		while (sqlite3_step(statement) == SQLITE_ROW) {
	//while there are rows		
				//debug_NSLog(@" has rows"); 
			NSMutableArray* row= [[NSMutableArray alloc] init]; 
			int counter=0; 
			 while(counter< sqlite3_column_count(statement) )
			 {
				 
				 switch(sqlite3_column_type(statement,counter))
				 {
						 // SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_BLOB, or SQLITE_NULL
					 case (SQLITE_INTEGER):
					 {
						 NSNumber* returnInt= [NSNumber numberWithInt:sqlite3_column_int(statement,counter)];
						 [row addObject:returnInt];
						 break; 
					 }
						 
					 case (SQLITE_FLOAT):
					 {
						 NSNumber* returnInt= [NSNumber numberWithDouble:sqlite3_column_double(statement,counter)];
							 [row addObject:returnInt];
						  break; 
					 }
						 
					 case (SQLITE_TEXT):
					 {
						 NSString* returnString = [NSString stringWithUTF8String:sqlite3_column_text(statement,counter)];
						 //	debug_NSLog(@"got string %@", returnString); 
						 	 [row addObject:[returnString stringByReplacingOccurrencesOfString:@"''" withString:@"'"]];
						  break; 
						 
					 }
						 
					 case (SQLITE_BLOB):
					 {
						 //trat as string for now 					
						 NSString* returnblob = [NSString stringWithUTF8String:sqlite3_column_text(statement,counter)];
						//debug_NSLog(@"got blob %@", returnblob); 
						 [row addObject:[returnblob stringByReplacingOccurrencesOfString:@"''" withString:@"'"]];
						  break; 
						 
						 
						 //Note: add blob support  as nsdata later 
						 
						 //char* data= sqlite3_value_text(statement); 
						 ///NSData* returnData =[NSData dataWithBytes:]
						 
					 }
						 
					 case (SQLITE_NULL):
					 {
						 debug_NSLog(@"return nil with sql null"); 
						  [row addObject:@""];
						  break; 
					 }
						 
				 }
				 
				 counter++; 
			 }
			
			[toReturn addObject:row];
		} 
		 
		/*sqlite3_stmt *statement2;
		 if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
		 sqlite3_step(statement2);
		 }*/
		;
		
		return toReturn; 
	}  
	debug_NSLog(@"reader nil with sql not ok: %@", query ); 
	/*sqlite3_stmt *statement2;
	 if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
	 sqlite3_step(statement2);
	 }*/
	
	;
		return nil; 
}



//account commands

-(NSArray*) protocolList
{
	//returns a buddy's message history
	
	
	

	
	
	NSString* query=[NSString stringWithFormat:@"select * from protocol where protocol_id<=3 or protocol_id=5 order by protocol_id asc"];
	NSArray* toReturn = [self executeReader:query];
	
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" count: %d",  [toReturn count] ); 
		;
		
		return toReturn; //[toReturn autorelease];
	}
	else 
	{
		debug_NSLog(@"protocol list  is empty or failed to read"); 
		;
		return nil; 
	}
}

-(NSArray*) accountList
{
	//returns a buddy's message history
	
	
	
	NSString* query=[NSString stringWithFormat:@"select * from account order by account_id asc "];
	NSArray* toReturn = [self executeReader:query];
	
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" count: %d",  [toReturn count] ); 
		;
		
		return toReturn; //[toReturn autorelease];
	}
	else 
	{
		debug_NSLog(@"account list  is empty or failed to read"); 
		;
		return nil; 
	}
	
}

-(NSArray*) enabledAccountList
{
	//returns a buddy's message history
	
	
	
	NSString* query=[NSString stringWithFormat:@"select * from account where enabled=1 order by account_id asc "];
	NSArray* toReturn = [self executeReader:query];
	
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" count: %d",  [toReturn count] ); 
		;
		
		return toReturn; //[toReturn autorelease];
	}
	else 
	{
		debug_NSLog(@"account list  is empty or failed to read"); 
		;
		return nil; 
	}
	
}

-(NSArray*) accountVals:(NSString*) accountNo
{
	//returns a buddy's message history
	
	
	
	NSString* query=[NSString stringWithFormat:@"select * from account where  account_id=%@ ", accountNo];
	NSArray* toReturn = [self executeReader:query];
	
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" count: %d",  [toReturn count] ); 
		;
		
		return toReturn; //[toReturn autorelease];
	}
	else 
	{
		debug_NSLog(@"account list  is empty or failed to read"); 
		;
		return nil; 
	}
	
}

-(BOOL) addAccount: (NSString*) name :(NSString*) theProtocol :(NSString*) username: (NSString*) password: (NSString*) server
				  : (NSString*) otherport: (bool) secure: (NSString*) resource: (NSString*) thedomain:(bool) enabled
{

	
	
	if(enabled==true) [self removeEnabledAccount];//reset all 
	
	NSString* query=
	[NSString stringWithFormat:@"insert into account values(null, '%@', %@, '%@', '%@', '%@', '%@', %d, '%@', '%@', %d) ",
	 username, theProtocol,server, otherport, username, password, secure, resource, thedomain, enabled];

	if([self executeNonQuery:query]!=false) 
	{
		;
		return true; 
	}
	else 
	{
		;
		return false; 
	}
}

-(BOOL) updateAccount: (NSString*) name :(NSString*) theProtocol :(NSString*) username: (NSString*) password: (NSString*) server
					 : (NSString*) otherport: (bool) secure: (NSString*) resource: (NSString*) thedomain:(bool) enabled:(NSString*) accountNo
{
	
	
	
	if(enabled==true) [self removeEnabledAccount];//reset all 
	
	NSString* query=
	[NSString stringWithFormat:@"update account  set account_name='%@', protocol_id=%@, server='%@', other_port='%@', username='%@', password='%@', secure=%d, resource='%@', domain='%@', enabled=%d where account_id=%@", 
	 username, theProtocol,server, otherport, username, password, secure, resource, thedomain,enabled,  accountNo];
 //debug_NSLog(query); 		
	
	
	if([self executeNonQuery:query]!=false) 
	{
		;
		return true; 
	}
	else 
	{
		;
		return false; 
	}
}

-(BOOL) removeAccount:(NSString*) accountNo
{
	
	
	// remove all other traces of the account_id
	NSString* query1=[NSString stringWithFormat:@"delete from buddylist  where account_id=%@ ;", accountNo];
	[self executeNonQuery:query1];
	
	NSString* query2=[NSString stringWithFormat:@"delete from messages  where account_id=%@ ;", accountNo];
	[self executeNonQuery:query2];
	
	NSString* query3=[NSString stringWithFormat:@"delete from message_history  where account_id=%@ ;", accountNo];
	[self executeNonQuery:query3];
	
	
	NSString* query=[NSString stringWithFormat:@"delete from account  where account_id=%@ ;", accountNo];
	if([self executeNonQuery:query]!=false) 
	{
		;
		return true; 
	}
	else 
	{
		;
		return false; 
	}
}


-(BOOL) removeEnabledAccount
{
	

	NSString* query=[NSString stringWithFormat:@"update account set enabled=0  ;"];
	if([self executeNonQuery:query]!=false) 
	{
		;
		return true; 
	}
	else 
	{
		;
		return false; 
	}
}








#pragma mark Buddy Commands


-(BOOL) addBuddy:(NSString*) buddy :(NSString*) accountNo:(NSString*) fullName:(NSString*) nickName
{
	if([self isBuddyInList:buddy :accountNo]) return false; // hard condition check ..no dupes!
	
		
	
	// no blank full names
	NSString* actualfull; 
	if([fullName isEqualToString:@""])
		actualfull=buddy; 
	
	else actualfull=fullName;
	
	NSString* query=[NSString stringWithFormat:@"insert into buddylist values(null, %@, '%@', '%@','%@','','','','','',0, 0, 1);", accountNo, buddy, actualfull, nickName];
	if([self executeNonQuery:query]!=false) 
	{
		;
		return true; 
	}
	else 
	{
		;
		return false; 
	}
	
}
-(BOOL) removeBuddy:(NSString*) buddy :(NSString*) accountNo
{
		
	//clean up logs 
	[self messageHistoryClean:buddy :accountNo];
	
	NSString* query=[NSString stringWithFormat:@"delete from buddylist  where account_id=%@ and buddy_name='%@';", accountNo, buddy];
	if([self executeNonQuery:query]!=false) 
	{
		;
		return true; 
	}
	else 
	{
		;
		return false; 
	}
} 
-(BOOL) clearBuddies:(NSString*) accountNo
{
		
	NSString* query=[NSString stringWithFormat:@"delete from buddylist  where account_id=%@ ;", accountNo];
	if([self executeNonQuery:query]!=false) 
	{
		;
		return true; 
	}
	else 
	{
		;
		return false; 
	}
}


#pragma mark Buddy Property commands

-(BOOL) resetBuddies
{
	
	
    NSString* query2=[NSString stringWithFormat:@"delete from  buddy_resources ;   "];
	[self executeNonQuery:query2];

    
	NSString* query=[NSString stringWithFormat:@"update buddylist set dirty=0, new=0, online=0, state='', status='';   "];
	if([self executeNonQuery:query]!=false) 
	{
		;
		return true; 
	}
	else 
	{
		;
		return false; 
	}
	
}

-(NSArray*)getResourcesForUser:(NSString*)user 
{
    NSString* query1=[NSString stringWithFormat:@" select resource from buddy_resources as A inner join buddylist as B on a.buddy_id=b.buddy_id where  buddy_name='%@'  ", user ];
	
    NSArray* resources = [self executeReader:query1];
    
    return resources;
    
}


-(NSArray*) onlineBuddies:(NSString*) accountNo
{
	
	
	
	NSString* query1=[NSString stringWithFormat:@"select username, domain from account where account_id=%@", accountNo];
	//debug_NSLog(query); 
	NSArray* user = [self executeReader:query1];
	
	if(user!=nil)
		if([user count]>0)//sanity check
	{

	NSString* query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0, ifnull(full_name, buddy_name) as full_name from buddylist where account_id=%@ and online=1  and buddy_name!='%@'  and buddy_name!='%@@%@'  order by full_name COLLATE NOCASE ", accountNo
					 , [[user objectAtIndex:0] objectAtIndex:0], [[user objectAtIndex:0] objectAtIndex:0],  [[user objectAtIndex:0] objectAtIndex:1]  ];
	//debug_NSLog(query); 
	NSArray* toReturn = [self executeReader:query];
	
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" count: %d",  [toReturn count] ); 
		;
		
		return toReturn; //[toReturn autorelease];
	}
	else 
	{
		debug_NSLog(@"buddylist is empty or failed to read"); 
		;
		return nil; 
	}
	} else return nil; 
	
}

-(NSArray*) offlineBuddies:(NSString*) accountNo
{
	
	
	
	NSString* query1=[NSString stringWithFormat:@"select username, domain from account where account_id=%@", accountNo];
	//debug_NSLog(query); 
	NSArray* user = [self executeReader:query1];
	
	if(user!=nil)
		if([user count]>0)//sanity check
		{
			
			NSString* query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0, ifnull(full_name, buddy_name) as full_name from buddylist where account_id=%@ and online=0  and buddy_name!='%@'  and buddy_name!='%@@%@'  order by full_name COLLATE NOCASE ", accountNo
							 , [[user objectAtIndex:0] objectAtIndex:0], [[user objectAtIndex:0] objectAtIndex:0],  [[user objectAtIndex:0] objectAtIndex:1]  ];
			//debug_NSLog(query); 
			NSArray* toReturn = [self executeReader:query];
			
			if(toReturn!=nil)
			{
				
				debug_NSLog(@" count: %d",  [toReturn count] ); 
				;
				
				return toReturn; //[toReturn autorelease];
			}
			else 
			{
				debug_NSLog(@"buddylist is empty or failed to read"); 
				;
				return nil; 
			}
		} else return nil; 
	
}


-(NSArray*) newBuddies:(NSString*) accountNo;
{
	//get domain
	
	
	NSString* query1=[NSString stringWithFormat:@"select username, domain from account where account_id=%@", accountNo];
	//debug_NSLog(query); 
	NSArray* user = [self executeReader:query1];
	
	if(user!=nil)
		if([user count]>0)//sanity check
	{
		
		NSString* query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0, full_name from buddylist where account_id=%@ and online=1  and (buddy_name!='%@'  and buddy_name!='%@@%@'  ) and new=1 order by full_name, buddy_name ", accountNo
						 , [[user objectAtIndex:0] objectAtIndex:0], [[user objectAtIndex:0] objectAtIndex:0],  [[user objectAtIndex:0] objectAtIndex:1]  ];
		//debug_NSLog(query); 
		NSArray* toReturn = [self executeReader:query];
		
		if(toReturn!=nil)
		{
			
			debug_NSLog(@" count: %d",  [toReturn count] ); 
			;
			
			return toReturn; //[toReturn autorelease];
		}
		else 
		{
			debug_NSLog(@"buddylist is empty or failed to read"); 
			;
			return nil; 
		}
	} else return nil; 
	
}


-(NSArray*) removedBuddies:(NSString*) accountNo;
{
	//returns a buddy's message history
	
	
	NSString* query1=[NSString stringWithFormat:@"select username, domain  from account where account_id=%@", accountNo];
	//debug_NSLog(query); 
	NSArray* user = [self executeReader:query1];
	
	if(user!=nil)
		if([user count]>0)//sanity check
	{
		
		NSString* query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0, full_name from buddylist where account_id=%@ and online=0  and (buddy_name!='%@'  and buddy_name!='%@@%@'  ) and dirty=1  order by full_name, buddy_name ", accountNo
						 , [[user objectAtIndex:0] objectAtIndex:0], [[user objectAtIndex:0] objectAtIndex:0],  [[user objectAtIndex:0] objectAtIndex:1]  ];
		//debug_NSLog(query); 
		NSArray* toReturn = [self executeReader:query];
		
		if(toReturn!=nil)
		{
			
			debug_NSLog(@" count: %d",  [toReturn count] ); 
			;
			
			return toReturn; //[toReturn autorelease];
		}
		else 
		{
			debug_NSLog(@"buddylist is empty or failed to read"); 
			;
			return nil; 
		}
	} else return nil; 
	
}

-(NSArray*) updatedBuddies:(NSString*) accountNo;
{
	//returns a buddy's message history
	
	
	NSString* query1=[NSString stringWithFormat:@"select username, domain  from account where account_id=%@", accountNo];
	//debug_NSLog(query); 
	NSArray* user = [self executeReader:query1];
	
	if(user!=nil)
		if([user count]>0)//sanity check
	{
		
		NSString* query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0, full_name from buddylist where account_id=%@ and online=1  and (buddy_name!='%@'  and buddy_name!='%@@%@'  ) and dirty=1 order by full_name, buddy_name ", accountNo
						 , [[user objectAtIndex:0] objectAtIndex:0], [[user objectAtIndex:0] objectAtIndex:0],  [[user objectAtIndex:0] objectAtIndex:1]  ];
		//debug_NSLog(query); 
		NSArray* toReturn = [self executeReader:query];
		
		if(toReturn!=nil)
		{
			
			debug_NSLog(@" count: %d",  [toReturn count] ); 
			;
			
			return toReturn; //[toReturn autorelease];
		}
		else 
		{
			debug_NSLog(@"buddylist is empty or failed to read"); 
			;
			return nil; 
		}
	} else return nil; 
	
}


-(BOOL) markBuddiesRead:(NSString*) accountNo
{
	
	
	NSString* query=[NSString stringWithFormat:@"update buddylist set dirty=0, new=0 where account_id=%@ and (new!=0 or dirty!=0)  ;", accountNo];
	if([self executeNonQuery:query]!=false) 
	{
		
		;
		return true; 
	}
	else 
	{
		
		;
		return false; 
	}
}

#pragma mark Ver string and Capabilities  

-(BOOL) setResourceVer:(presence*)presenceObj: (NSString*) accountNo
{
    
    
    
    //get buddyid for name and account
    
    NSString* query1=[NSString stringWithFormat:@" select buddy_id from buddylist where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user ];
	
    NSString* buddyid = [self executeScalar:query1];
    
    if(buddyid==nil) return NO;
    

    
    NSString* query=[NSString stringWithFormat:@"update buddy_resources set ver='%@' where buddy_id=%@ and resource='%@'", presenceObj.ver, buddyid, presenceObj.resource ];
	if([self executeNonQuery:query]!=false)
	{
		
		;
		return true;
	}
	else
	{
        ;
		return false;
	}
}

-(NSArray*) capsforVer:(NSString*) verString
{
   
            
            NSString* query=[NSString stringWithFormat:@"select cap from ver_info where ver='%@'", verString];
                             
                             //debug_NSLog(query);
            NSArray* toReturn = [self executeReader:query];
            
            if(toReturn!=nil)
            {
                
                if([toReturn count]==0) return nil;
                
                debug_NSLog(@" caps  count: %d",  [toReturn count] );
                ;
                
                return toReturn; //[toReturn autorelease];
            }
            else 
            {
                debug_NSLog(@"caps list is empty"); 
                ;
                return nil; 
            }
       
}

-(NSString*)getVerForUser:(NSString*)user Resource:(NSString*) resource
{
    NSString* query1=[NSString stringWithFormat:@" select ver from buddy_resources as A inner join buddylist as B on a.buddy_id=b.buddy_id where resource='%@' and buddy_name='%@'", resource, user ];
	
    NSString* ver = [self executeScalar:query1];
    
    return ver;

}

-(BOOL)setFeature:(NSString*)feature  forVer:(NSString*) ver
{
    NSString* query=[NSString stringWithFormat:@"insert into ver_info values ('%@', '%@')", ver,feature];
	if([self executeNonQuery:query]!=false)
	{
		
		;
		return true;
	}
	else
	{
        ;
		return false;
	}
}



#pragma mark presence functions 

-(BOOL) setResourceOnline:(presence*)presenceObj: (NSString*) accountNo
{
    

    
    //get buddyid for name and account
    
    NSString* query1=[NSString stringWithFormat:@" select buddy_id from buddylist where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user ];
	
    NSString* buddyid = [self executeScalar:query1];

    if(buddyid==nil) return NO; 
    
//make sure not already there
    
    //see how many left
    NSString* query3=[NSString stringWithFormat:@" select count(buddy_id) from buddy_resources where buddy_id=%@ and resource='%@';", buddyid, presenceObj.resource ];
	
    NSString* resourceCount = [self executeScalar:query3];
   	
    if([resourceCount integerValue]  >0) return false;
    
    NSString* query=[NSString stringWithFormat:@"insert into buddy_resources values (%@, '%@', '')", buddyid, presenceObj.resource ];
	if([self executeNonQuery:query]!=false)
	{
		
		;
		return true;
	}
	else
	{
        ;
		return false;
	}
}




-(BOOL) setOnlineBuddy:(presence*)presenceObj: (NSString*) accountNo
{
    
    [self setResourceOnline:presenceObj:accountNo];
    
    if([self isBuddyOnline:presenceObj.user:accountNo]) return false; // pervent setting something as new
		

	NSString* query=[NSString stringWithFormat:@"update buddylist set online=1, new=1  where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user];
	if([self executeNonQuery:query]!=false) 
	{
		
		;
		return true; 
	}
	else 
	{
				;
		return false; 
	}
	
}

-(BOOL) setOfflineBuddy:(presence*)presenceObj: (NSString*) accountNo
{
    
    
    NSString* query1=[NSString stringWithFormat:@" select buddy_id from buddylist where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user ];
	
    NSString* buddyid = [self executeScalar:query1];
    
    if(buddyid==nil) return NO;
    
    
    NSString* query2=[NSString stringWithFormat:@"delete from   buddy_resources where buddy_id=%@ and resource='%@'", buddyid, presenceObj.resource ];
	if([self executeNonQuery:query2]==false) return false;


    //see how many left
    NSString* query3=[NSString stringWithFormat:@" select count(buddy_id) from buddy_resources where buddy_id=%@;", buddyid ];
	
    NSString* resourceCount = [self executeScalar:query3];
    
    
    if([resourceCount integerValue]<1)
    {
    
	
	NSString* query=[NSString stringWithFormat:@"update buddylist set online=0, dirty=1  where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user];
	if([self executeNonQuery:query]!=false) 
	{
		
		;
		return true; 
	}
	else 
	{
		
		;
		return false; 
	}
	}
    else return YES; 
    
}


-(BOOL) setBuddyState:(presence*)presenceObj: (NSString*) accountNo
{
	
	NSString* toPass;
	//data length check
	
	if([presenceObj.show length]>20) toPass=[presenceObj.show substringToIndex:19]; else toPass=presenceObj.show;
	NSString* query=[NSString stringWithFormat:@"update buddylist set state='%@', dirty=1 where account_id=%@ and  buddy_name='%@';",toPass, accountNo, presenceObj.show];
	if([self executeNonQuery:query]!=false)
	{
		
		;
		return true;
	}
	else
	{
		
		;
		return false;
	}
}

-(NSString*) buddyState:(NSString*) buddy :(NSString*) accountNo
{
	
	
	NSString* query=[NSString stringWithFormat:@"select state from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy];
	NSString* iconname= [self executeScalar:query];
    ;
	return iconname;
}


-(BOOL) setBuddyStatus:(presence*)presenceObj: (NSString*) accountNo
{
	
	
	NSString* toPass;
	//data length check
	if([presenceObj.status length]>200) toPass=[[presenceObj.status substringToIndex:199] stringByReplacingOccurrencesOfString:@"'"
																								  withString:@"''"];
	else toPass=[presenceObj.status  stringByReplacingOccurrencesOfString:@"'"
                                                      withString:@"''"];;
	NSString* query=[NSString stringWithFormat:@"update buddylist set status='%@', dirty=1 where account_id=%@ and  buddy_name='%@';",[toPass stringByReplacingOccurrencesOfString:@"'" withString:@"''"], accountNo, presenceObj.user];
	if([self executeNonQuery:query]!=false)
	{
		
		;
		return true;
	}
	else
	{
		
		;
		return false;
	}
}

-(NSString*) buddyStatus:(NSString*) buddy :(NSString*) accountNo
{
	
	
	NSString* query=[NSString stringWithFormat:@"select status from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy];
	NSString* iconname= [self executeScalar:query];
    ; 
	return iconname; 
}



#pragma mark Contact info


-(BOOL) setFullName:(NSString*) buddy :(NSString*) accountNo:(NSString*) fullName
{
	
	NSString* toPass;
	//data length check
	
	if([fullName length]>50) toPass=[fullName substringToIndex:49]; else toPass=fullName;
	// sometimes the buddyname comes from a roster so it might notbe in the lit yet, add first and if that fails (ie already there) then set fullname
	
	if(![self addBuddy:buddy : accountNo: fullName:@""])
	{
		
	
	
	NSString* query=[NSString stringWithFormat:@"update buddylist set full_name='%@',dirty=1 where account_id=%@ and  buddy_name='%@';",[toPass stringByReplacingOccurrencesOfString:@"'" withString:@"''"], accountNo, buddy];
	if([self executeNonQuery:query]!=false) 
	{
		
		;
		return true; 
	}
	else 
	{
		
		;
		return false; 
	}
	
	}
	else
	{
		;
		return true; 
	}
}

-(BOOL) setNickName:(NSString*) buddy :(NSString*) accountNo:(NSString*) nickName
{
	
	NSString* toPass;
	//data length check
	
	if([nickName length]>50) toPass=[nickName substringToIndex:49]; else toPass=nickName;
	NSString* query=[NSString stringWithFormat:@"update buddylist set nick_name='%@',dirty=1 where account_id=%@ and  buddy_name='%@';",[toPass stringByReplacingOccurrencesOfString:@"'" withString:@"''"], accountNo, buddy];
	if([self executeNonQuery:query]!=false) 
	{
		
		;
		return true; 
	}
	else 
	{
		
		;
		return false; 
	}
}


-(NSString*) fullName:(NSString*) buddy :(NSString*) accountNo
{
	
	
	NSString* query=[NSString stringWithFormat:@"select full_name from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy];
	NSString* iconname= [self executeScalar:query];
	 ; 
	return iconname; 
}



-(BOOL) setBuddyHash:(NSString*) buddy :(NSString*) accountNo:(NSString*) theHash
{
	
	NSString* toPass;
	//data length check
	NSString* query=[NSString stringWithFormat:@"update buddylist set iconhash='%@', dirty=1 where account_id=%@ and  buddy_name='%@';",theHash,
					 accountNo, buddy];
	if([self executeNonQuery:query]!=false) 
	{
		;
		return true; 
	}
	else 
	{
		;
		return false; 
	}
}

-(NSString*) buddyHash:(NSString*) buddy :(NSString*) accountNo
{
	
	
	
	//if there isnt a file name icon wasnt downloaded
	
	
	NSString* query2=[NSString stringWithFormat:@"select filename from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy];
	NSString* filename= [self executeScalar:query2];
	if([filename isEqualToString:@""])
	{
		
		return @"";
	}
	
	
	NSString* query=[NSString stringWithFormat:@"select iconhash from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy];
	NSString* iconname= [self executeScalar:query];
	 ; 
	return iconname; 
}


-(bool) isBuddyInList:(NSString*) buddy :(NSString*) accountNo 
{
	// count # of meaages in message table
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=%@ and buddy_name='%@' ", accountNo, buddy];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil) 
	{
		int val=[count integerValue];
		if(val>0) {
			;
			return true; } else 
			{
				;
				return false;
			}
	}
	else 
	{
		;
		return false; 
	}
	
	
}

-(bool) isBuddyOnline:(NSString*) buddy :(NSString*) accountNo 
{
	// count # of meaages in message table
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=%@ and buddy_name='%@' and online=1 ", accountNo, buddy];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil) 
	{
		int val=[count integerValue];
		if(val>0) {
			;
			return true; } else 
			{
				;
				return false;
			}
	}
	else 
	{
		;
		return false; 
	}
	
	
}

-(bool) isBuddyMuc:(NSString*) buddy :(NSString*) accountNo 
{
	// seeif it is muc chat name
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"SELECT	message_history_id from message_history where account_id=%@ and message_from!=actual_from and message_from='%@'  limit 1", accountNo, buddy];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil) 
	{
		int val=[count integerValue];
		if(val>0) {
		;
			return true; } else 
			{
				;
				return false;
			}
	}
	else 
	{
		;
		return false; 
	}
	
	
}




-(bool) isBuddyAdded:(NSString*) buddy :(NSString*) accountNo 
{
	// count # of meaages in message table
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=%@ and buddy_name='%@' and online=1 and new=1", accountNo, buddy];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil) 
	{
		int val=[count integerValue];
		if(val>0) {
            ;
			return true; } else 
			{
				;
				return false;
			}
	}
	else 
	{
		;
		return false; 
	}
	
	
}



-(bool) isBuddyRemoved:(NSString*) buddy :(NSString*) accountNo
{
	// count # of meaages in message table
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=%@ and buddy_name='%@' and online=0 and dirty=1", accountNo, buddy];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil) 
	{
		int val=[count integerValue];
		if(val>0) {
			;
			return true; } else 
			{
				;
				return false;
			}
	
	}
	else 
	{
		;
		return false; 
	}
	
	
}


#pragma mark icon Commands


-(BOOL) setIconName:(NSString*) buddy :(NSString*) accountNo:(NSString*) icon
{
	
	
	NSString* query=[NSString stringWithFormat:@"update buddylist set filename='%@',dirty=1 where account_id=%@ and  buddy_name='%@';",icon, accountNo, buddy];
	if([self executeNonQuery:query]!=false) 
	{
		;
		return true; 
	}
	else 
	{
		;
		return false; 
	}
}

-(NSString*) iconName:(NSString*) buddy :(NSString*) accountNo
{
	/*
	 NSString* query=[NSString stringWithFormat:@"select data  from buddyicon as A inner join buddylist as B on a.buddyid=b.buddyid where account_id=%@ and buddy_name='%@'", accountNo, buddy];
	 NSString* iconname= [self executeScalar:query];
	 [iconname retain];
	  ; 
	 return iconname; */
}





#pragma mark message Commands
-(BOOL) addMessage:(NSString*) from :(NSString*) to :(NSString*) accountNo:(NSString*) message:(NSString*) actualfrom 
{
	//MEssaes coming in. in messages table, to is always the local user
	
	
	
	
	NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
	NSDate* sourceDate=[NSDate date];
	
	NSTimeZone* sourceTimeZone = [NSTimeZone systemTimeZone];
	NSTimeZone* destinationTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
	
	NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
	NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
	NSTimeInterval interval = destinationGMTOffset - sourceGMTOffset;
	
	NSDate* destinationDate = [[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate];
	
	// note: if it isnt the same day we want to show tehful day
	
	
	NSString* dateString = [formatter stringFromDate:destinationDate];
	int notice=0; 
    
    // in the event it is a message from the room 
	 
    
	NSString* query=[NSString stringWithFormat:@"insert into messages values (null, %@, '%@',  '%@', '%@', '%@', %d, '%@');", accountNo, from, to, 	dateString, [message stringByReplacingOccurrencesOfString:@"'" withString:@"''"], notice, actualfrom];
	debug_NSLog(@"%@",query); 
	if([self executeNonQuery:query]!=false) 
	{
		
		;
		return true; 
	}
	else 
	{
		debug_NSLog(@"failed to insert "); 
		;
		return false; 
	}
	
}




-(BOOL) clearMessages:(NSString*) accountNo
{
	
	
	NSString* query=[NSString stringWithFormat:@"delete from messages where account_id=%@", accountNo];
	if([self executeNonQuery:query]!=false) 
	{
		;
		return true; 
	}
	else 
	{
		;
		return false; 
	}
}

-(NSArray*) messageHistoryListDates:(NSString*) buddy :(NSString*) accountNo
{
    //returns a list of  buddy's with message history
	
	NSString* query1=[NSString stringWithFormat:@"select username, domain from account where account_id=%@", accountNo];
	//debug_NSLog(query); 
	NSArray* user = [self executeReader:query1];
	
	if(user!=nil)
	{
        
        NSString* query=[NSString stringWithFormat:@"select distinct date(timestamp) from message_history where account_id=%@ and  message_from='%@' or  message_to='%@'   order by timestamp desc", accountNo, buddy, buddy  ];
        //debug_NSLog(query); 
        NSArray* toReturn = [self executeReader:query];
        
        if(toReturn!=nil)
        {
            
            debug_NSLog(@" count: %d",  [toReturn count] ); 
            ;
            
            return toReturn; //[toReturn autorelease];
        }
        else 
        {
            debug_NSLog(@"message history buddy date list is empty or failed to read"); 
            ;
            return nil; 
        }
        
	} else return nil; 
	
}

-(NSArray*) messageHistoryDate:(NSString*) buddy :(NSString*) accountNo:(NSString*) date
{
	//returns a buddy's message history
	
	
	
	//NSArray* parts=[[[NSDate date] description] componentsSeparatedByString:@" "]; 
	
	
	NSString* query=[NSString stringWithFormat:@"select message_from, message, thetime from (select message_from, message, timestamp as thetime, message_history_id from message_history where account_id=%@ and (message_from='%@' or message_to='%@')  and date(timestamp)='%@' order by message_history_id desc) order by message_history_id asc ", accountNo, buddy, buddy, date];
	debug_NSLog(@"%@",query); 
	NSArray* toReturn = [self executeReader:query];
	
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" count: %d",  [toReturn count] ); 
		;
		
		return toReturn; //[toReturn autorelease];
	}
	else 
	{
		debug_NSLog(@"message history is empty or failed to read"); 
		;
		return nil; 
	}
	
}



-(NSArray*) messageHistoryAll:(NSString*) buddy :(NSString*) accountNo
{
	//returns a buddy's message history
	
	
	
	//NSArray* parts=[[[NSDate date] description] componentsSeparatedByString:@" "]; 
	
	
	NSString* query=[NSString stringWithFormat:@"select message_from, message, thetime from (select message_from, message, timestamp as thetime, message_history_id from message_history where account_id=%@ and (message_from='%@' or message_to='%@') order by message_history_id desc) order by message_history_id asc ", accountNo, buddy, buddy];
	//debug_NSLog(query); 
	NSArray* toReturn = [self executeReader:query];
	
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" count: %d",  [toReturn count] ); 
		;
		
		return toReturn; //[toReturn autorelease];
	}
	else 
	{
		debug_NSLog(@"message history is empty or failed to read"); 
		;
		return nil; 
	}
	
}

-(BOOL) messageHistoryClean:(NSString*) buddy :(NSString*) accountNo
{
	//returns a buddy's message history
	
	
	
	NSString* query=[NSString stringWithFormat:@"delete from message_history where account_id=%@ and (message_from='%@' or message_to='%@') ",accountNo, buddy, buddy];
	//debug_NSLog(query); 
	if( [self executeNonQuery:query])

	{
		debug_NSLog(@" cleaned messages for %@",  buddy ); 
		
		;
		return true; 
	}
	else 
	{
		debug_NSLog(@"message history failed to clean"); 
		;
		return false; 
	}
	
}


-(BOOL) messageHistoryCleanAll:(NSString*) accountNo
{
	//cleans a buddy's message history
	

	NSString* query=[NSString stringWithFormat:@"delete from message_history where account_id=%@  ",accountNo];
	//debug_NSLog(query); 
	if( [self executeNonQuery:query])
		
	{
		
		debug_NSLog(@" cleaned messages " ); 
		
		;
		return true; 
	}
	else 
	{
		debug_NSLog(@"message history failed to clean all"); 
		;
		return false; 
	}
	
}

-(NSArray*) messageHistoryBuddies:(NSString*) accountNo
{
	//returns a list of  buddy's with message history
	
	NSString* query1=[NSString stringWithFormat:@"select username, domain from account where account_id=%@", accountNo];
	//debug_NSLog(query); 
	NSArray* user = [self executeReader:query1];
	
	if(user!=nil)
	{
	
	NSString* query=[NSString stringWithFormat:@"select x.* from(select distinct message_from,'', ifnull(full_name, message_from) as full_name, filename from message_history as a left outer join buddylist as b on a.message_from=b.buddy_name and a.account_id=b.account_id where a.account_id=%@  union select distinct message_to  ,'', ifnull(full_name, message_to) as full_name, filename from message_history as a left outer join buddylist as b on a.message_to=b.buddy_name and a.account_id=b.account_id where a.account_id=%@  )  as x where message_from!='%@' and message_from!='%@@%@'  order by full_name COLLATE NOCASE ", accountNo, accountNo,[[user objectAtIndex:0] objectAtIndex:0], [[user objectAtIndex:0] objectAtIndex:0],  [[user objectAtIndex:0] objectAtIndex:1]  ];
	//debug_NSLog(query); 
	NSArray* toReturn = [self executeReader:query];
	
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" count: %d",  [toReturn count] ); 
		;
		
		return toReturn; //[toReturn autorelease];
	}
	else 
	{
		debug_NSLog(@"message history buddy list is empty or failed to read"); 
		;
		return nil; 
	}
	
	} else return nil; 
}

-(NSArray*) unreadMessagesForBuddy:(NSString*) buddy :(NSString*) accountNo
{
	//returns a buddy's message history
	
	
	
	//NSArray* parts=[[[NSDate date] description] componentsSeparatedByString:@" "]; 
	
	
	NSString* query=[NSString stringWithFormat:@"select af, message, thetime from (select ifnull(actual_from, message_from) as af, message,  timestamp as thetime, message_id from messages where account_id=%@ and (message_from='%@' or message_to='%@') order by message_id desc limit 10) order by message_id asc", accountNo, buddy, buddy];
	//debug_NSLog(query); 
	NSArray* toReturn = [self executeReader:query];
	
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" message list  count: %d",  [toReturn count] ); 
		;
		
		return toReturn; //[toReturn autorelease];
	}
	else 
	{
		debug_NSLog(@"message list  is empty or failed to read"); 
		;
		return nil; 
	}
}

//message history
-(NSArray*) messageHistory:(NSString*) buddy :(NSString*) accountNo
{
	//returns a buddy's message history
	
	
	
	//NSArray* parts=[[[NSDate date] description] componentsSeparatedByString:@" "]; 
	
	
	NSString* query=[NSString stringWithFormat:@"select af, message, thetime from (select ifnull(actual_from, message_from) as af, message,     timestamp  as thetime, message_history_id from message_history where account_id=%@ and (message_from='%@' or message_to='%@') order by message_history_id desc limit 10) order by message_history_id asc",accountNo, buddy, buddy];
	debug_NSLog(@"%@", query); 
	NSArray* toReturn = [self executeReader:query];
		
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" message history count: %d",  [toReturn count] ); 
		;
	
		return toReturn; //[toReturn autorelease];
	}
	else 
	{
		debug_NSLog(@"message history is empty or failed to read"); 
		;
		return nil; 
	}
	
}
-(BOOL) markAsRead:(NSString*) buddy :(NSString*) accountNo
{
	
	//called when a buddy is clicked
		//moves messages from a buddy from messages to history (thus marking them as read) 
	

	
	NSString* query2=[NSString stringWithFormat:@"  insert into message_history (account_id,message_from, message_to, timestamp, message, actual_from) select account_id,message_from, message_to, timestamp, message, actual_from  from messages where account_id=%@ and message_from='%@';", accountNo, buddy];
	if([self executeNonQuery:query2]!=false) 
	{
	//	debug_NSLog(query2);
	
	NSString* query=[NSString stringWithFormat:@"delete from messages where account_id=%@ and message_from='%@'; ", accountNo, buddy];
	if([self executeNonQuery:query]!=false) 
	{
		;
		return true; 
	}
	else 
	{
			debug_NSLog(@"Messages clean  failed"); 
		;
		return false; 
	}
	}
	else 
	{
		debug_NSLog(@"Message history insert failed"); 
		; 
		return false; 
	}
	
}

-(BOOL) addMessageHistory:(NSString*) from :(NSString*) to :(NSString*) accountNo:(NSString*) message:(NSString*) actualfrom 
{
	//MEssaes_history ging out, from is always the local user
	
	
	
	
	NSArray* parts=[[[NSDate date] description] componentsSeparatedByString:@" "]; 
	

	NSString* query=[NSString stringWithFormat:@"insert into message_history values (null, %@, '%@',  '%@', '%@ %@', '%@', '%@');", accountNo, from, to, 
					 [parts objectAtIndex:0],[parts objectAtIndex:1], [message stringByReplacingOccurrencesOfString:@"'" withString:@"''"], actualfrom];
	
	if([self executeNonQuery:query]!=false) 
	{
		;
		return true; 
	}
	else 
	{
		;
		return false; 
	}
	
}


//count unread
-(int) countUnreadMessages:(NSString*) accountNo
{
	// count # of meaages in message table
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"select count(message_id) from  messages where account_id=%@", accountNo];

	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil) 
	{
		int val=[count integerValue];
		;
		return val; 
	}
	else 
	{
		;
		return 0; 
	}
	
	
}

#pragma mark active chats
-(NSArray*) activeBuddies:(NSString*) accountNo
{
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"select distinct a.buddy_name,'', ifnull(full_name, a.buddy_name) as full_name, filename,0 from activechats as a left outer join buddylist as b on a.buddy_name=b.buddy_name and a.account_id=b.account_id where a.account_id=%@ order by full_name COLLATE NOCASE ", accountNo ];
	//	debug_NSLog(query); 
	NSArray* toReturn = [self executeReader:query];
	
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" count: %d",  [toReturn count] ); 
		;
		
		return toReturn; //[toReturn autorelease];
	}
	else 
	{
		debug_NSLog(@"message history is empty or failed to read"); 
		;
		return nil; 
	}
	
}

-(bool) removeActiveBuddies:(NSString*) buddyname:(NSString*) accountNo
{
	
	//mark messages as read
	[self markAsRead: buddyname : accountNo];
	
	NSString* query=[NSString stringWithFormat:@"delete from activechats where buddy_name='%@' and account_id=%@ ", buddyname, accountNo ];
	//	debug_NSLog(query); 

	
	bool result=[self executeNonQuery:query];
	; 
	return result; 
	
}

-(bool) removeAllActiveBuddies:(NSString*) accountNo
{
	
	NSString* query2=[NSString stringWithFormat:@"  insert into message_history (account_id,message_from, message_to, timestamp, message, actual_from) select a.account_id,message_from, message_to, timestamp, message, actual_from  from messages  as a inner join activechats as b on a.account_id=b.account_id and a.message_from=b.buddy_name where a.account_id=%@ ", accountNo];
    
	if([self executeNonQuery:query2]!=false)
    {
    
    }
    
    NSString* query3=[NSString stringWithFormat:@"delete from messages where account_id=%@ and message_from in (select buddy_name from activechats where account_id=%@); ", accountNo, accountNo];
    
    if([self executeNonQuery:query3]!=false)
    {
        
    }
    
	
	NSString* query=[NSString stringWithFormat:@"delete from activechats where  account_id=%@ ",  accountNo ];
	//	debug_NSLog(query); 
    
	
	bool result=[self executeNonQuery:query];
	; 
	return result; 
	
}



-(bool) addActiveBuddies:(NSString*) buddyname:(NSString*) accountNo;
{
	
	
	//check if in active chat already 
	
	
	NSString* query=[NSString stringWithFormat:@"select count(buddy_name) from activechats where account_id=%@ and buddy_name='%@' ", accountNo, buddyname];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil) 
	{
		int val=[count integerValue];
		if(val>0) {
			;
			return false; 
			} else 
			{
				//no
				NSString* query2=[NSString stringWithFormat:@"insert into activechats values ( %@,'%@') ",  accountNo,buddyname ];
				//	debug_NSLog(query); 
				
				
				bool result=[self executeNonQuery:query2];
				; 
				return result; 
			}
	}
	/*else 
	{
		//no
		NSString* query2=[NSString stringWithFormat:@"insert into activechats values ( %@,'%@') ",  accountNo,buddyname ];
		//	debug_NSLog(query); 
		
		
		bool result=[self executeNonQuery:query2];
		;
		return result; 
	}*/
	
	;
	return false; 
	
}


#pragma mark unread messages

-(NSArray*) unreadMessages:(NSString*) accountNo
{
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"select message_from,message from messages where account_id=%@", accountNo ];
	//	debug_NSLog(query); 
	NSArray* toReturn = [self executeReader:query];
	
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" unread msg count: %d",  [toReturn count] ); 
		;
		
		return toReturn; //[toReturn autorelease];
	}
	else 
	{
		debug_NSLog(@"message history is empty or failed to read"); 
		;
		return nil; 
	}
}

-(int) countUserUnreadMessages:(NSString*) buddy :(NSString*) accountNo
{
	// count # messages from a specific user in messages table
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"select count(message_id) from  messages where account_id=%@ and message_from='%@'", accountNo, buddy];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil) 
	{
		int val=[count integerValue];
		;
		return val; 
	}
	else 
	{
		;
		return 0; 
	}
}

-(int) countOtherUnreadMessages:(NSString*) buddy :(NSString*) accountNo
{
	// count # messages from a specific user in messages table
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"select count(message_id) from  messages where account_id=%@ and not message_from='%@'", accountNo, buddy];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil) 
	{
		int val=[count integerValue];
		;
		return val; 
	}
	else 
	{
		;
		return 0; 
	}
}

#pragma mark message notice Commands

//messages for which a notification has not been shown
-(BOOL) markAsNoticed:(NSString*) accountNo
{
	
	
	
	NSString* query=[NSString stringWithFormat:@"update messages set notice=1  where account_id=%@", accountNo ];
	
	bool result=[self executeNonQuery:query];
	
	;
	return result; 
}

-(int) countUnnoticedMessages:(NSString*) accountNo
{
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"select count(*) from messages where notice=0  and account_id=%@", accountNo ];
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil) 
	{
		int val=[count integerValue];
		;
		return val; 
	}
	else 
	{
		;
		return 0; 
	}
}


-(NSArray*) unnoticedMessages:(NSString*) accountNo
{
	
	
	
	
	NSString* query=[NSString stringWithFormat:@" select message_from,message,filename, full_name  from messages as a left outer join buddylist as b on a.message_from=b.buddy_name  and a.account_id=b.account_id where notice=0 and a.account_id=%@", accountNo ];
	//	debug_NSLog(query); 
	NSArray* toReturn = [self executeReader:query];
	
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" count: %d",  [toReturn count] ); 
		;
		
		return toReturn; //[toReturn autorelease];
	}
	else 
	{
		debug_NSLog(@"message history is empty or failed to read"); 
		;
		return nil; 
	}
}

#pragma db Commands

-(void) initDB
{
	NSFileManager* fileManager = [NSFileManager defaultManager]; 
	
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];
	NSString *writableDBPath = [documentsDirectory stringByAppendingPathComponent:@"sworim.sqlite"];
	if( ![fileManager fileExistsAtPath:writableDBPath])
	{
	// The writable database does not exist, so copy the default to the appropriate location.
	NSString *defaultDBPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"sworim.sqlite"];
		NSError* error; 
		[fileManager copyItemAtPath:defaultDBPath toPath:writableDBPath error:&error];
	}
	
	if (sqlite3_config(SQLITE_CONFIG_SERIALIZED) == SQLITE_OK) {
		debug_NSLog(@"Database configured ok"); 
	} else debug_NSLog(@"Database not configured ok"); 
	
	dbPath = writableDBPath; //[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"sworim.sqlite"];
	if (sqlite3_open([dbPath UTF8String], &database) == SQLITE_OK) {
		debug_NSLog(@"Database opened"); 
	}
	else 
	{
		//database error message
		debug_NSLog(@"Error opening database"); 
	}

	
	//truncate faster than del 
	[self executeNonQuery:@"pragma truncate;"];
	
    
    dbversionCheck=[NSLock alloc];
	[self version];
	
	
}

-(void) version
{
    [dbversionCheck lock];
    
	// checking db version and upgrading if necessary
	debug_NSLog(@"Database version check");
	
	//<1.02 has no db version table but gtalk port is 443 . this is an identifier
	NSNumber* gtalkport= [self executeScalar:@"select default_port from  protocol   where protocol_name='GTalk';"];
	if([gtalkport intValue]==443)
	{
			debug_NSLog(@"Database version <1.02 detected. Performing upgrade");
		[self executeNonQuery:@"drop table account;"]; 
		[self executeNonQuery:@"create table account( account_id integer not null primary key AUTOINCREMENT,account_name varchar(20) not null, protocol_id integer not null, server varchar(50) not null, other_port integer, username varchar(30), password varchar(30), secure bool,resource varchar(30), domain varchar(50), enabled bool);"]; 
		[self executeNonQuery:@"update protocol set default_port=5223 where protocol_name='GTalk';"]; 
		[self executeNonQuery:@"create table dbversion(dbversion varchar(10) );"]; 
		[self executeNonQuery:@"insert into dbversion values('1.02');"]; 
		
		
		debug_NSLog(@"Upgrade to 1.02 success importing default account");
		NSString* importAcc= [NSString stringWithFormat:@"insert into account values(null, '%@', 0, '%@', %@, '%@', '%@', %@, '%@', '%@', 1); ",
							  [[NSUserDefaults standardUserDefaults] stringForKey:@"username"] ,
							  [ [NSUserDefaults standardUserDefaults] stringForKey:@"server"] ,
							  [ [NSUserDefaults standardUserDefaults] stringForKey:@"portno"] ,
							  [ [NSUserDefaults standardUserDefaults] stringForKey:@"username"] ,
							  [ [NSUserDefaults standardUserDefaults] stringForKey:@"password"] ,
							  [ [NSUserDefaults standardUserDefaults] stringForKey:@"SSL"] ,  
							  [[NSUserDefaults standardUserDefaults] stringForKey:@"resource"] ,
							  [[NSUserDefaults standardUserDefaults] stringForKey:@"thedomain"] 
							  
							  ];
		
		[self executeNonQuery:importAcc]; 
		
		
		
		debug_NSLog(@"Done");
		
		
	}
	
	
	
	// < 1.04 has google talk on 5223 or 443
	
	if( ([gtalkport intValue]==5223) || ([gtalkport intValue]==443))
	{
		debug_NSLog(@"Database version <1.04 detected. Performing upgrade");
		[self executeNonQuery:@"update protocol set default_port=5222 where protocol_name='GTalk';"]; 
		[self executeNonQuery:@"insert into protocol values (null,'Facebook',5222); "];
			
		[self executeNonQuery:@"drop table buddylist; "];
		[self executeNonQuery:@"drop table buddyicon; "];
		[self executeNonQuery:@"create table buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(50), full_name varchar(50), nick_name varchar(50)); "];
		[self executeNonQuery:@"create table buddyicon(buddyicon_id integer null primary key AUTOINCREMENT,buddy_id integer not null,hash varchar(255),  filename varchar(50)); "];
	
		[self executeNonQuery:@"drop table dbversion;"];
		[self executeNonQuery:@"create table dbversion(dbversion real);"];
		[self executeNonQuery:@"insert into dbversion values(1.04);"];
		debug_NSLog(@"Upgrade to 1.04 success ");
	
	
	}
	
	
	NSNumber* dbversion= [self executeScalar:@"select dbversion from dbversion"];
	debug_NSLog(@"Got db version %@", dbversion); 
	
	
	if([dbversion doubleValue]<1.07)
	{
		debug_NSLog(@"Database version <1.07 detected. Performing upgrade");
		[self executeNonQuery:@"create table buddylistOnline (buddy_id integer not null primary key AUTOINCREMENT,account_id integer not null,buddy_name varchar(50), group_name varchar(100)); "]; 
		[self executeNonQuery:@"update dbversion set dbversion='1.07'; "];
		
		[[NSUserDefaults standardUserDefaults] setBool:true forKey:@"IdleAlert"];
		
		debug_NSLog(@"Upgrade to 1.07 success ");
		
	}
	
	if([dbversion doubleValue]<1.071)
	{
		debug_NSLog(@"Database version <1.071 detected. Performing upgrade");
		[self executeNonQuery:@"drop table buddylistOnline;  "]; 
		
		[self executeNonQuery:@"drop table buddylist;  "]; 
		[self executeNonQuery:@"drop table messages;  "]; 
		[self executeNonQuery:@"drop table message_history;  "]; 
		[self executeNonQuery:@"drop table buddyicon;  "]; 
		
		
	
		[self executeNonQuery:@"create table buddylist(buddy_id integer not null primary key AUTOINCREMENT,account_id integer not null, buddy_name varchar(50) collate nocase, full_name varchar(50),nick_name varchar(50), group_name varchar(50),iconhash varchar(200),filename varchar(100),state varchar(20), status varchar(200),online bool, dirty bool, new bool); "]; 
		
		
	
		
		[self executeNonQuery:@"create table messages(message_id integer not null primary key AUTOINCREMENT,account_id integer, message_from varchar(50) collate nocase,message_to varchar(50) collate nocase, timestamp datetime, message blob,notice integer,actual_from varchar(50) collate nocase);"]; 
		
		
		
		[self executeNonQuery:@"create table message_history(message_history_id integer not null primary key AUTOINCREMENT,account_id integer, message_from varchar(50) collate nocase,message_to varchar(50) collate nocase,timestamp datetime , message blob,actual_from varchar(50) collate nocase);"]; 
		
		
		
		
		[self executeNonQuery:@"create table activechats(account_id integer not null, buddy_name varchar(50) collate nocase); "]; 
		
		
		[self executeNonQuery:@"update dbversion set dbversion='1.071'; "];
		
		[[NSUserDefaults standardUserDefaults] setBool:true forKey:@"IdleAlert"];
		
		debug_NSLog(@"Upgrade to 1.071 success ");
		
	}
	
	if([dbversion doubleValue]<1.072)
	{
		debug_NSLog(@"Database version <1.072 detected. Performing upgrade on passwords. ");
		NSArray* rows = [self executeReader:@"select account_id, password from account"]; 
		int counter=0; 
		PasswordManager* pass; 
		while(counter<[rows count])
		{
			//debug_NSLog(@" %@ %@",[[rows objectAtIndex:counter] objectAtIndex:0], [[rows objectAtIndex:counter] objectAtIndex:1] );
			 pass= [PasswordManager alloc] ; 
			
			[pass init:[NSString stringWithFormat:@"%@",[[rows objectAtIndex:counter] objectAtIndex:0]]];
			[pass setPassword:[[rows objectAtIndex:counter] objectAtIndex:1]] ;
			//debug_NSLog(@"got:%@", [pass getPassword] ); 
			
			counter++; 
		}
		

		//wipe passwords 
		
		[self executeNonQuery:@"update account set password=''; "];
        

		
	}
    
    
    if([dbversion doubleValue]<1.073)
    {
        debug_NSLog(@"Database version <1.073 detected. Performing upgrade on passwords. ");
        
        //set defaults on upgrade
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"OfflineContact"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"MessagePreview"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"Logging"];
        
        [self executeNonQuery:@"update dbversion set dbversion='1.073'; "];
        debug_NSLog(@"Upgrade to 1.073 success ");
        
    }
	

    
    if([dbversion doubleValue]<1.074)
    {
        debug_NSLog(@"Database version <1.074 detected. Performing upgrade on protocols. ");
        

        [self executeNonQuery:@"delete from protocol where protocol_id=3 "];
        [self executeNonQuery:@"delete from protocol where protocol_id=4 "];
        
        
        [self executeNonQuery:@" create table legacy_caps(capid integer not null primary key autoincrement,captext  varchar(20))"];
        
       
       
        
        [self executeNonQuery:@" insert into legacy_caps values (null,'pmuc-v1');"];
        [self executeNonQuery:@" insert into legacy_caps values (null,'voice-v1');"];
        [self executeNonQuery:@" insert into legacy_caps values (null,'camera-v1');"];
        [self executeNonQuery:@" insert into legacy_caps values (null, 'video-v1');"];
        
        
        
         [self executeNonQuery:@"create table buddy_resources(buddy_id integer,resource varchar(255),ver varchar(20))"];
        
         [self executeNonQuery:@"create table ver_info(ver varchar(20),cap varchar(255), primary key (ver,cap))"];

        
        
        [self executeNonQuery:@"update dbversion set dbversion='1.074'; "];
        debug_NSLog(@"Upgrade to 1.074 success ");
        
    }
	
    [dbversionCheck unlock];


	return;
	

	
}

-(void) dealloc
{
	sqlite3_close(database); 
}



@end