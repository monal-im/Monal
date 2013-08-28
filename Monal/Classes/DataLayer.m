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
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sharedInstance = [DataLayer alloc] ;
        [sharedInstance initDB];
    });
    return sharedInstance;
    
}


//lowest level command handlers
-(NSObject*) executeScalar:(NSString*) query
{
    NSObject* __block toReturn;
    dispatch_sync(_dbQueue, ^{
        
        
        /*
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
                        toReturn= returnInt;
                        break;
                    }
                        
                    case (SQLITE_FLOAT):
                    {
                        NSNumber* returnInt= [NSNumber numberWithDouble:sqlite3_column_double(statement,0)];
						while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
                        /*	sqlite3_stmt *statement2;
                         if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
                         sqlite3_step(statement2);
                         }*/
                        toReturn= returnInt;
                        break;
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
                        toReturn= [returnString  stringByReplacingOccurrencesOfString:@"''" withString:@"'"];
                        break;
                        
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
                        toReturn= [returnString  stringByReplacingOccurrencesOfString:@"''" withString:@"'"];
                        
                        
                        
                        //Note: add blob support later
                        
                        //char* data= sqlite3_value_text(statement);
                        ///NSData* returnData =[NSData dataWithBytes:]
                        toReturn= nil;
                        break;
                    }
                        
                    case (SQLITE_NULL):
                    {
                        debug_NSLog(@"return nil with sql null");
                        while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
                        /*sqlite3_stmt *statement2;
                         if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
                         sqlite3_step(statement2);
                         }*/
                        toReturn= nil;
                        break;
                    }
                        
                        
                        
                }
                
                
                
            } else
            {debug_NSLog(@"return nil with no row");
                /*sqlite3_stmt *statement2;
                 if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
                 sqlite3_step(statement2);
                 }*/
                toReturn= nil;};
        }
        else{
            //if noting else
            debug_NSLog(@"returning nil with out OK %@", query);
            /*sqlite3_stmt *statement2;
             if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
             sqlite3_step(statement2);
             }*/
            
            toReturn= nil;
        }
    });
    
    return toReturn;
}

-(BOOL) executeNonQuery:(NSString*) query
{
	
    BOOL __block toReturn;
    dispatch_sync(_dbQueue, ^{
        /*sqlite3_stmt *statement1;
         if (sqlite3_prepare_v2(database, [@"begin"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement1, NULL) == SQLITE_OK) {
         sqlite3_step(statement1);
         }*/
        
        sqlite3_stmt *statement;
        if (sqlite3_prepare_v2(database, [query  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK)
        {
            if(sqlite3_step(statement)==SQLITE_DONE)
                toReturn=YES;
            else
                toReturn=NO;
        }
        
        else
        {
            debug_NSLog(@"nonquery returning NO with out OK %@", query);
            toReturn=NO;
        }
        
        
        /*sqlite3_stmt *statement2;
         if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
         sqlite3_step(statement2);
         }*/
        
    });
    
    return toReturn;
}


-(NSArray*) executeReader:(NSString*) query
{
    
  	NSMutableArray* __block toReturn =  [[NSMutableArray alloc] init] ;
    dispatch_sync(_dbQueue, ^{
        /*sqlite3_stmt *statement1;
         if (sqlite3_prepare_v2(database, [@"begin"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement1, NULL) == SQLITE_OK) {
         sqlite3_step(statement1);
         }
         */
        
        
        sqlite3_stmt *statement;
        if (sqlite3_prepare_v2(database, [query cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK) {
            
            while (sqlite3_step(statement) == SQLITE_ROW) {
                //while there are rows
				//debug_NSLog(@" has rows");
                NSMutableDictionary* row= [[NSMutableDictionary alloc] init];
                int counter=0;
                while(counter< sqlite3_column_count(statement) )
                {
                    NSString* columnName=[NSString stringWithUTF8String:sqlite3_column_name(statement,counter)];
                    
                    switch(sqlite3_column_type(statement,counter))
                    {
                            // SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_BLOB, or SQLITE_NULL
                        case (SQLITE_INTEGER):
                        {
                            NSNumber* returnInt= [NSNumber numberWithInt:sqlite3_column_int(statement,counter)];
                            [row setObject:returnInt forKey:columnName];
                            break;
                        }
                            
                        case (SQLITE_FLOAT):
                        {
                            NSNumber* returnInt= [NSNumber numberWithDouble:sqlite3_column_double(statement,counter)];
                            [row setObject:returnInt forKey:columnName];
                            break;
                        }
                            
                        case (SQLITE_TEXT):
                        {
                            NSString* returnString = [NSString stringWithUTF8String:sqlite3_column_text(statement,counter)];
                            [row setObject:[returnString stringByReplacingOccurrencesOfString:@"''" withString:@"'"] forKey:columnName];
                            break;
                            
                        }
                            
                        case (SQLITE_BLOB):
                        {
                            //trat as string for now
                            NSString* returnblob = [NSString stringWithUTF8String:sqlite3_column_text(statement,counter)];
                            [row setObject:[returnblob stringByReplacingOccurrencesOfString:@"''" withString:@"'"] forKey:columnName];
                            break;
                            
                            
                            //Note: add blob support  as nsdata later
                            
                            //char* data= sqlite3_value_text(statement);
                            ///NSData* returnData =[NSData dataWithBytes:]
                            
                        }
                            
                        case (SQLITE_NULL):
                        {
                            debug_NSLog(@"return nil with sql null");
                            
                            [row setObject:@"" forKey:columnName];
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
            
            
        }
        else
        {
            debug_NSLog(@"reader nil with sql not ok: %@", query );
            /*sqlite3_stmt *statement2;
             if (sqlite3_prepare_v2(database, [@"end"  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement2, NULL) == SQLITE_OK) {
             sqlite3_step(statement2);
             }*/
            
            
            toReturn= nil;
        }
    });
    
    return toReturn;
}



//account commands

-(NSArray*) protocolList
{
    
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
	
		return toReturn; //[toReturn autorelease];
	}
	else
	{
		debug_NSLog(@"account list  is empty or failed to read");
	
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
				  : (NSString*) otherport: (bool) secure: (NSString*) resource: (NSString*) thedomain:(bool) enabled :(bool) selfsigned: (bool) oldstyle
{
    
	
	
	//if(enabled==YES) [self removeEnabledAccount];//reset all
	
	NSString* query=
	[NSString stringWithFormat:@"insert into account values(null, '%@', %@, '%@', '%@', '%@', '%@', %d, '%@', '%@', %d, %d, %d) ",
	 username, theProtocol,server, otherport, username, password, secure, resource, thedomain, enabled, selfsigned, oldstyle];
    
	if([self executeNonQuery:query]!=NO)
	{
		;
		return YES;
	}
	else
	{
		;
		return NO;
	}
}

-(BOOL) updateAccount: (NSString*) name :(NSString*) theProtocol :(NSString*) username: (NSString*) password: (NSString*) server
					 : (NSString*) otherport: (bool) secure: (NSString*) resource: (NSString*) thedomain:(bool) enabled:(NSString*) accountNo
                     :(bool) selfsigned: (bool) oldstyle
{
	
	
	
	//if(enabled==YES) [self removeEnabledAccount];//reset all
	
	NSString* query=
	[NSString stringWithFormat:@"update account  set account_name='%@', protocol_id=%@, server='%@', other_port='%@', username='%@', password='%@', secure=%d, resource='%@', domain='%@', enabled=%d, selfsigned=%d, oldstyleSSL=%d where account_id=%@",
	 username, theProtocol,server, otherport, username, password, secure, resource, thedomain,enabled, selfsigned, oldstyle,accountNo];
    //debug_NSLog(query);
	
	
	if([self executeNonQuery:query]!=NO)
	{
		return YES;
	}
	else
	{
		return NO;
	}
}

-(BOOL) removeAccount:(NSString*) accountNo
{
	
	
	// remove all other traces of the account_id
	NSString* query1=[NSString stringWithFormat:@"delete from buddylist  where account_id=%@ ;", accountNo];
	[self executeNonQuery:query1];
		
	NSString* query3=[NSString stringWithFormat:@"delete from message_history  where account_id=%@ ;", accountNo];
	[self executeNonQuery:query3];
	
    NSString* query4=[NSString stringWithFormat:@"delete from activechats  where account_id=%@ ;", accountNo];
	[self executeNonQuery:query4];
    
	NSString* query=[NSString stringWithFormat:@"delete from account  where account_id=%@ ;", accountNo];
	if([self executeNonQuery:query]!=NO)
	{
		;
		return YES;
	}
	else
	{
		;
		return NO;
	}
}


-(BOOL) disableEnabledAccount:(NSString*) accountNo
{

	NSString* query=[NSString stringWithFormat:@"update account set enabled=0 where account_id=%@  ", accountNo];
	if([self executeNonQuery:query]!=NO)
	{
		;
		return YES;
	}
	else
	{
		;
		return NO;
	}
}








#pragma mark Buddy Commands


-(BOOL) addBuddy:(NSString*) buddy  forAccount:(NSString*) accountNo fullname:(NSString*) fullName nickname:(NSString*) nickName
{
    __block BOOL toReturn=NO;
    //this needs to be one atomic operation
    dispatch_sync(_contactQueue, ^{
        if(![self isBuddyInList:buddy forAccount:accountNo]) {
     
            // no blank full names
            NSString* actualfull;
            if([fullName isEqualToString:@""])
                actualfull=buddy;
            
            else actualfull=fullName;
            
            NSString* query=[NSString stringWithFormat:@"insert into buddylist values(null, %@, '%@', '%@','%@','','','','','',0, 0, 1);", accountNo, buddy, actualfull, nickName];
            if([self executeNonQuery:query]!=NO)
            {
                toReturn= YES;
            }
            else
            {
                
            }
        }
    }      );
    
    return toReturn; 
	
}
-(BOOL) removeBuddy:(NSString*) buddy :(NSString*) accountNo
{
    
	//clean up logs
	[self messageHistoryClean:buddy :accountNo];
	
	NSString* query=[NSString stringWithFormat:@"delete from buddylist  where account_id=%@ and buddy_name='%@';", accountNo, buddy];
	if([self executeNonQuery:query]!=NO)
	{
		;
		return YES;
	}
	else
	{
		;
		return NO;
	}
}
-(BOOL) clearBuddies:(NSString*) accountNo
{
    
	NSString* query=[NSString stringWithFormat:@"delete from buddylist  where account_id=%@ ;", accountNo];
	if([self executeNonQuery:query]!=NO)
	{
		;
		return YES;
	}
	else
	{
		;
		return NO;
	}
}


#pragma mark Buddy Property commands

-(BOOL) resetContacts
{
	
	
    NSString* query2=[NSString stringWithFormat:@"delete from  buddy_resources ;   "];
	[self executeNonQuery:query2];
    
    
	NSString* query=[NSString stringWithFormat:@"update buddylist set dirty=0, new=0, online=0, state='', status='';   "];
	if([self executeNonQuery:query]!=NO)
	{
		return YES;
	}
	else
	{
		return NO;
	}
	
}

-(BOOL) resetContactsForAccount:(NSString*) accountNo
{
	
	
    NSString* query2=[NSString stringWithFormat:@"delete from  buddy_resources  where buddy_id in (select buddy_id from  buddylist where account_id=%@);   ", accountNo];
	[self executeNonQuery:query2];

    
	NSString* query=[NSString stringWithFormat:@"update buddylist set dirty=0, new=0, online=0, state='', status='' where account_id=%@;   ", accountNo];
	if([self executeNonQuery:query]!=NO)
	{
		return YES;
	}
	else
	{
		return NO;
	}
	
}


-(NSArray*)getResourcesForUser:(NSString*)user
{
    NSString* query1=[NSString stringWithFormat:@" select resource from buddy_resources as A inner join buddylist as B on a.buddy_id=b.buddy_id where  buddy_name='%@'  ", user ];
	
    NSArray* resources = [self executeReader:query1];
    
    return resources;
    
}

-(NSArray*) contactForUsername:(NSString*) username forAccount: (NSString*) accountNo
{
    NSString* query= query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0, ifnull(full_name, buddy_name) as full_name, account_id from buddylist where buddy_name='%@' and account_id=%@", username, accountNo];

    //debug_NSLog(query);
    NSArray* toReturn = [self executeReader:query];
    
    if(toReturn!=nil)
    {
        debug_NSLog(@" count: %d",  [toReturn count] );
        return toReturn; //[toReturn autorelease];
    }
    else
    {
        debug_NSLog(@"buddylist is empty or failed to read");
        return nil;
    }
    
}


-(NSArray*) onlineBuddiesSortedBy:(NSString*) sort
{
	     NSString* query=@"";
    
            if([sort isEqualToString:@"Name"])
            {
                query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0 as 'count' , ifnull(full_name, buddy_name) as full_name, account_id from buddylist where online=1    order by full_name COLLATE NOCASE asc "];
            }
            
            if([sort isEqualToString:@"State"])
            {
                query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0 as 'count', ifnull(full_name, buddy_name) as full_name, account_id from buddylist where   online=1   order by state,full_name COLLATE NOCASE  asc "];
            }
            
           //debug_NSLog(query);
            NSArray* toReturn = [self executeReader:query];
            
            if(toReturn!=nil)
            {
                debug_NSLog(@" count: %d",  [toReturn count] );
               return toReturn; //[toReturn autorelease];
            }
            else
            {
                debug_NSLog(@"buddylist is empty or failed to read");
                return nil;
            }
            
}

-(NSArray*) offlineBuddies
{
	

			
			NSString* query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0, ifnull(full_name, buddy_name) as full_name from buddylist where  online=0 order by full_name COLLATE NOCASE "];
			//debug_NSLog(query);
			NSArray* toReturn = [self executeReader:query];
			
			if(toReturn!=nil)
			{
				
				debug_NSLog(@" count: %d",  [toReturn count] );
				return toReturn; //[toReturn autorelease];
			}
			else
			{
				debug_NSLog(@"buddylist is empty or failed to read");
				return nil;
			}
		
	
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
	if([self executeNonQuery:query]!=NO)
	{
		
		;
		return YES;
	}
	else
	{
		
		;
		return NO;
	}
}

#pragma mark Ver string and Capabilities

//-(BOOL) setResourceVer:(presence*)presenceObj: (NSString*) accountNo
//{
//
//    //get buddyid for name and account
//
//    NSString* query1=[NSString stringWithFormat:@" select buddy_id from buddylist where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user ];
//
//    NSString* buddyid = [self executeScalar:query1];
//
//    if(buddyid==nil) return NO;
//
//
//
//    NSString* query=[NSString stringWithFormat:@"update buddy_resources set ver='%@' where buddy_id=%@ and resource='%@'", presenceObj.ver, buddyid, presenceObj.resource ];
//	if([self executeNonQuery:query]!=NO)
//	{
//
//		;
//		return YES;
//	}
//	else
//	{
//        ;
//		return NO;
//	}
//}

-(BOOL) checkCap:(NSString*)cap forUser:(NSString*) user accountNo:(NSString*) acctNo
{
    NSString* query=[NSString stringWithFormat:@"select count(*) from buddylist as a inner join buddy_resources as b on a.buddy_id=b.buddy_id  inner join ver_info as c  on  b.ver=c.ver where buddy_name='%@' and account_id=%@ and cap='%@'", user, acctNo,cap ];
    
    //debug_NSLog(@"%@", query);
    NSNumber* count = [self executeScalar:query];
    
    if([count integerValue]>0) return YES; else return NO;
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
	if([self executeNonQuery:query]!=NO)
	{
		
		;
		return YES;
	}
	else
	{
        ;
		return NO;
	}
}

#pragma mark legacy caps

-(void) clearLegacyCaps
{
    NSString* query=[NSString stringWithFormat:@"delete from buddy_resources_legacy_caps"];
    
    //debug_NSLog(@"%@", query);
    [self executeNonQuery:query];
    
    return;
}

//-(BOOL) setLegacyCap:(NSString*)cap forUser:(presence*)presenceObj accountNo:(NSString*) acctNo
//{
//    if (presenceObj.resource==nil) return NO;
//
//    NSString* query1=[NSString stringWithFormat:@" select buddy_id from buddylist where account_id=%@ and  buddy_name='%@';", acctNo, presenceObj.user ];
//
//    NSString* buddyid = [self executeScalar:query1];
//
//    if(buddyid==nil) return NO;
//
//
//    NSString* query2=[NSString stringWithFormat:@" select capid  from legacy_caps  where captext='%@';", cap ];
//
//    NSString* capid = [self executeScalar:query2];
//
//    if(capid==nil) return NO;
//
//
//    NSString* query=[NSString stringWithFormat:@"insert into buddy_resources_legacy_caps values (%@,'%@',%@)", buddyid, presenceObj.resource, capid ];
//	if([self executeNonQuery:query]!=NO)
//	{
//
//		;
//		return YES;
//	}
//	else
//	{
//        ;
//		return NO;
//	}
//
//
//}

-(BOOL) checkLegacyCap:(NSString*)cap forUser:(NSString*) user accountNo:(NSString*) acctNo
{
    NSString* query=[NSString stringWithFormat:@"select count(*) from buddylist as a inner join buddy_resources_legacy_caps as b on a.buddy_id=b.buddy_id  inner join legacy_caps as c on c.capid=b.capid where buddy_name='%@' and account_id=%@ and captext='%@'", user, acctNo,cap ];
    
    //debug_NSLog(@"%@", query);
    NSNumber* count = [self executeScalar:query];
    
    if([count integerValue]>0) return YES; else return NO;
}

#pragma mark presence functions

-(BOOL) setResourceOnline:(ParsePresence *)presenceObj forAccount:(NSString *)accountNo
{
    
    //get buddyid for name and accoun
    if([presenceObj.user  isEqualToString:@"rob.isakson@gmail.com"])
       {
           debug_NSLog(@"meh");
       }
    
    NSString* query1=[NSString stringWithFormat:@" select buddy_id from buddylist where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user ];
    NSString* buddyid = (NSString*)[self executeScalar:query1];
    if(buddyid==nil) return NO;
    
    //make sure not already there
    
    //see how many left
    NSString* query3=[NSString stringWithFormat:@" select count(buddy_id) from buddy_resources where buddy_id=%@ and resource='%@';", buddyid, presenceObj.resource ];
    NSString* resourceCount =(NSString*) [self executeScalar:query3];
   	
    if([resourceCount integerValue]  >0) return NO;
    
    NSString* query=[NSString stringWithFormat:@"insert into buddy_resources values (%@, '%@', '')", buddyid, presenceObj.resource ];
	if([self executeNonQuery:query]!=NO)
	{
		return YES;
	}
	else
	{
        return NO;
	}
}


-(BOOL) setOnlineBuddy:(ParsePresence *)presenceObj forAccount:(NSString *)accountNo
{
    [self setResourceOnline:presenceObj forAccount:accountNo];
    if([self isBuddyOnline:presenceObj.user forAccount:accountNo]) return NO; // pervent setting something as new
    
	NSString* query=[NSString stringWithFormat:@"update buddylist set online=1, new=1  where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user];
	if([self executeNonQuery:query]!=NO)
	{
		return YES;
	}
	else
	{
		return NO;
	}
	
}

-(BOOL) setOfflineBuddy:(ParsePresence *)presenceObj forAccount:(NSString *)accountNo
{
    
    NSString* query1=[NSString stringWithFormat:@" select buddy_id from buddylist where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user ];
	NSString* buddyid = (NSString*)[self executeScalar:query1];
    if(buddyid==nil) return NO;
    
    NSString* query2=[NSString stringWithFormat:@"delete from   buddy_resources where buddy_id=%@ and resource='%@'", buddyid, presenceObj.resource ];
	if([self executeNonQuery:query2]==NO) return NO;
    
    NSString* query4=[NSString stringWithFormat:@"delete from   buddy_resources_legacy_caps where buddy_id=%@ and resource='%@'",
                      buddyid, presenceObj.resource ];
	if([self executeNonQuery:query4]==NO) return NO;
    
    //see how many left
    NSString* query3=[NSString stringWithFormat:@" select count(buddy_id) from buddy_resources where buddy_id=%@;", buddyid ];
    NSString* resourceCount = (NSString*)[self executeScalar:query3];
    
    if([resourceCount integerValue]<1)
    {
        
        
        NSString* query=[NSString stringWithFormat:@"update buddylist set online=0, dirty=1  where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user];
        if([self executeNonQuery:query]!=NO)
        {
            return YES;
        }
        else
        {
            return NO;
        }
	}
    else return YES;
    
}


-(BOOL) setBuddyState:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
{

	NSString* toPass;
	//data length check

	if([presenceObj.show length]>20) toPass=[presenceObj.show substringToIndex:19]; else toPass=presenceObj.show;
	NSString* query=[NSString stringWithFormat:@"update buddylist set state='%@', dirty=1 where account_id=%@ and  buddy_name='%@';",toPass, accountNo, presenceObj.user];
	if([self executeNonQuery:query]!=NO)
	{
		return YES;
	}
	else
	{
		return NO;
	}
    
}

-(NSString*) buddyState:(NSString*) buddy forAccount:(NSString*) accountNo
{

	NSString* query=[NSString stringWithFormat:@"select state from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy];
	NSString* iconname= (NSString*)[self executeScalar:query];
    ;
	return iconname;
}


-(BOOL) setBuddyStatus:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo
{
	NSString* toPass;
	//data length check
	if([presenceObj.status length]>200) toPass=[[presenceObj.status substringToIndex:199] stringByReplacingOccurrencesOfString:@"'"
																								  withString:@"''"];
	else toPass=[presenceObj.status  stringByReplacingOccurrencesOfString:@"'"
                                                      withString:@"''"];;
	NSString* query=[NSString stringWithFormat:@"update buddylist set status='%@', dirty=1 where account_id=%@ and  buddy_name='%@';",[toPass stringByReplacingOccurrencesOfString:@"'" withString:@"''"], accountNo, presenceObj.user];
	if([self executeNonQuery:query]!=NO)
	{

		return YES;
	}
	else
	{

		return NO;
	}
}

-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSString*) accountNo
{
	NSString* query=[NSString stringWithFormat:@"select status from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy];
	NSString* iconname= [self executeScalar:query];
    return iconname;
}



#pragma mark Contact info

-(BOOL) setFullName:(NSString*) fullName forBuddy:(NSString*) buddy andAccount:(NSString*) accountNo
{
	
	NSString* toPass;
	//data length check
	
	if([fullName length]>50) toPass=[fullName substringToIndex:49]; else toPass=fullName;
	// sometimes the buddyname comes from a roster so it might notbe in the lit yet, add first and if that fails (ie already there) then set fullname
	
	if(![self addBuddy:buddy forAccount: accountNo fullname:fullName nickname:@""])
	{
		NSString* query=[NSString stringWithFormat:@"update buddylist set full_name='%@',dirty=1 where account_id=%@ and  buddy_name='%@';",[toPass stringByReplacingOccurrencesOfString:@"'" withString:@"''"], accountNo, buddy];
        if([self executeNonQuery:query]!=NO)
        {
           return YES;
        }
        else
        {
           return NO;
        }
        
	}
	else
	{
		return YES;
	}
}

-(BOOL) setNickName:(NSString*) buddy :(NSString*) accountNo:(NSString*) nickName
{
	
	NSString* toPass;
	//data length check
	
	if([nickName length]>50) toPass=[nickName substringToIndex:49]; else toPass=nickName;
	NSString* query=[NSString stringWithFormat:@"update buddylist set nick_name='%@',dirty=1 where account_id=%@ and  buddy_name='%@';",[toPass stringByReplacingOccurrencesOfString:@"'" withString:@"''"], accountNo, buddy];
	if([self executeNonQuery:query]!=NO)
	{
		
		;
		return YES;
	}
	else
	{
		
		;
		return NO;
	}
}

-(NSString*) fullName:(NSString*) buddy forAccount:(NSString*) accountNo;
{
	
	
	NSString* query=[NSString stringWithFormat:@"select full_name from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy];
	NSString* iconname= (NSString*)[self executeScalar:query];
	return iconname;
}


-(BOOL) setBuddyHash:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
{
	
	//data length check
	NSString* query=[NSString stringWithFormat:@"update buddylist set iconhash='%@', dirty=1 where account_id=%@ and  buddy_name='%@';",presenceObj.photoHash,
					 accountNo, presenceObj.user];
	if([self executeNonQuery:query]!=NO)
	{
		return YES;
	}
	else
	{
		return NO;
	}
}

-(NSString*) buddyHash:(NSString*) buddy forAccount:(NSString*) accountNo
{
    //if there isnt a file name icon wasnt downloaded
//	NSString* query2=[NSString stringWithFormat:@"select filename from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy];
//	NSString* filename= (NSString*)[self executeScalar:query2];
//	if([filename isEqualToString:@""])
//	{
//		return @"";
//	}
	
	
	NSString* query=[NSString stringWithFormat:@"select iconhash from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy];
	NSString* iconname= (NSString*)[self executeScalar:query];
	return iconname;
}


-(bool) isBuddyInList:(NSString*) buddy forAccount:(NSString*) accountNo
{
    
	NSString* query=[NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=%@ and buddy_name='%@' ", accountNo, buddy];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil)
	{
		int val=[count integerValue];
		if(val>0) {
			;
			return YES; } else
			{
				;
				return NO;
			}
	}
	else
	{
		;
		return NO;
	}
	
	
}

-(bool) isBuddyOnline:(NSString*) buddy forAccount:(NSString*) accountNo
{
	// count # of meaages in message table
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=%@ and buddy_name='%@' and online=1 ", accountNo, buddy];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil)
	{
		int val=[count integerValue];
		if(val>0) {
			;
			return YES; } else
			{
				;
				return NO;
			}
	}
	else
	{
		;
		return NO;
	}
	
	
}

-(bool) isBuddyMuc:(NSString*) buddy forAccount:(NSString*) accountNo
{
	// seeif it is muc chat name
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"SELECT	message_history_id from message_history where account_id=%@ and message_from!=actual_from and message_from='%@'  limit 1", accountNo, buddy];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil)
	{
		int val=[count integerValue];
		if(val>0) {
            ;
			return YES; } else
			{
				;
				return NO;
			}
	}
	else
	{
		;
		return NO;
	}
	
	
}

-(bool) isBuddyAdded:(NSString*) buddy forAccount:(NSString*) accountNo
{
	// count # of meaages in message table
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=%@ and buddy_name='%@' and online=1 and new=1", accountNo, buddy];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil)
	{
		int val=[count integerValue];
		if(val>0) {
            ;
			return YES; } else
			{
				;
				return NO;
			}
	}
	else
	{
		;
		return NO;
	}
	
	
}

-(bool) isBuddyRemoved:(NSString*) buddy forAccount:(NSString*) accountNo
{
	// count # of meaages in message table
	
	
	
	
	NSString* query=[NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=%@ and buddy_name='%@' and online=0 and dirty=1", accountNo, buddy];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil)
	{
		int val=[count integerValue];
		if(val>0) {
			;
			return YES; } else
			{
				;
				return NO;
			}
        
	}
	else
	{
		;
		return NO;
	}
	
	
}


#pragma mark icon Commands


-(BOOL) setIconName:(NSString*) icon forBuddy:(NSString*) buddy inAccount:(NSString*) accountNo
{
	
	NSString* query=[NSString stringWithFormat:@"update buddylist set filename='%@',dirty=1 where account_id=%@ and  buddy_name='%@';",icon, accountNo, buddy];
	if([self executeNonQuery:query]!=NO)
	{
		return YES;
	}
	else
	{
        return NO;
	}
}

-(NSString*) iconName:(NSString*) buddy forAccount:(NSString*) accountNo;
{ 
	 NSString* query=[NSString stringWithFormat:@"select filename from  buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy];
	 NSString* iconname= (NSString*)[self executeScalar:query];
	 return iconname;
}





#pragma mark message Commands
-(BOOL) addMessageFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom 
{
//this is always from a contact 
	NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
	NSDate* sourceDate=[NSDate date];
	
	NSTimeZone* sourceTimeZone = [NSTimeZone systemTimeZone];
	NSTimeZone* destinationTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
	
	NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
	NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
	NSTimeInterval interval = destinationGMTOffset - sourceGMTOffset;
	
	NSDate* destinationDate = [[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate];
	
	// note: if it isnt the same day we want to show the full  day
	
    NSString* dateString = [formatter stringFromDate:destinationDate];
    // in the event it is a message from the room

    NSString* query=[NSString stringWithFormat:@"insert into message_history values (null, %@, '%@',  '%@', '%@', '%@', '%@',0);", accountNo, from, to, 	dateString, [message stringByReplacingOccurrencesOfString:@"'" withString:@"''"], actualfrom];
	debug_NSLog(@"%@",query);
	if([self executeNonQuery:query]!=NO)
	{
		return YES;
	}
	else
	{
		debug_NSLog(@"failed to insert ");
		return NO;
	}
	
}




-(BOOL) clearMessages:(NSString*) accountNo
{
	NSString* query=[NSString stringWithFormat:@"delete from message_history where account_id=%@", accountNo];
	if([self executeNonQuery:query]!=NO)
	{
		return YES;
	}
	else
	{
		return NO;
	}
}



-(BOOL) deleteMessageHistory:(NSString*) messageNo
{
    NSString* query=[NSString stringWithFormat:@"delete from message_history where message_history_id=%@", messageNo];
	if([self executeNonQuery:query]!=NO)
	{
		return YES;
	}
	else
	{
		return NO;
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

-(NSArray*) messageHistoryDate:(NSString*) buddy forAccount:(NSString*) accountNo forDate:(NSString*) date
{
	
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
		return YES;
	}
	else
	{
		debug_NSLog(@"message history failed to clean");
		;
		return NO;
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
		return YES;
	}
	else
	{
		debug_NSLog(@"message history failed to clean all");
		;
		return NO;
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

-(NSArray*) unreadMessages:(NSString*) buddy forAccount:(NSString*) accountNo
{	
	NSString* query=[NSString stringWithFormat:@"select af, message, thetime, message_history_id from (select ifnull(actual_from, message_from) as af, message,  timestamp as thetime, message_history_id from message_history where unread=1 and account_id=%@ and (message_from='%@' or message_to='%@') order by message_history_id desc limit 10) order by message_history_id asc", accountNo, buddy, buddy];
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
-(NSMutableArray*) messageHistory:(NSString*) buddy forAccount:(NSString*) accountNo
{
	//NSArray* parts=[[[NSDate date] description] componentsSeparatedByString:@" "];
	
	
	NSString* query=[NSString stringWithFormat:@"select af, message, thetime, message_history_id from (select ifnull(actual_from, message_from) as af, message,     timestamp  as thetime, message_history_id from message_history where account_id=%@ and (message_from='%@' or message_to='%@') order by message_history_id desc limit 20) order by message_history_id asc",accountNo, buddy, buddy];
	debug_NSLog(@"%@", query);
	NSMutableArray* toReturn = [self executeReader:query];
    
	if(toReturn!=nil)
	{
		
		debug_NSLog(@" message history count: %d",  [toReturn count] );
        return toReturn; //[toReturn autorelease];
	}
	else
	{
		debug_NSLog(@"message history is empty or failed to read");
		return nil;
	}
	
}
-(BOOL) markAsReadBuddy:(NSString*) buddy forAccount:(NSString*) accountNo
{

	NSString* query2=[NSString stringWithFormat:@"  update message_history set unread=0 where account_id=%@ and message_from='%@';", accountNo, buddy];
	if([self executeNonQuery:query2]!=NO)
	{
        return YES;
    }
	else
	{
		debug_NSLog(@"Message history update failed");
		return NO;
	}
	
}

-(BOOL) addMessageHistoryFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom ;
{
	//MEssaes_history ging out, from is always the local user. always read
	
	NSArray* parts=[[[NSDate date] description] componentsSeparatedByString:@" "];
	NSString* query=[NSString stringWithFormat:@"insert into message_history values (null, %@, '%@',  '%@', '%@ %@', '%@', '%@',0);", accountNo, from, to,
					 [parts objectAtIndex:0],[parts objectAtIndex:1], [message stringByReplacingOccurrencesOfString:@"'" withString:@"''"], actualfrom];
	
	if([self executeNonQuery:query]!=NO)
	{
		;
		return YES;
	}
	else
	{
		;
		return NO;
	}
	
}


//count unread
-(int) countUnreadMessages
{
	// count # of meaages in message table
    NSString* query=[NSString stringWithFormat:@"select count(message_history_id) from  message_history where  unread=1"];
    
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
-(NSArray*) activeBuddies
{
    
    

    NSString* query=[NSString stringWithFormat:@"select distinct b.buddy_name,state,status,filename,0 as 'count' , ifnull(b.full_name, b.buddy_name) as full_name, a.account_id from activechats as a inner join buddylist as b on a.buddy_name=b.buddy_name and a.account_id=b.account_id order by full_name COLLATE NOCASE" ];
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

-(bool) removeActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo
{
	
	//mark messages as read
	[self markAsReadBuddy:buddyname forAccount:accountNo];
	
	NSString* query=[NSString stringWithFormat:@"delete from activechats where buddy_name='%@' and account_id=%@ ", buddyname, accountNo ];
	//	debug_NSLog(query);
    
	
	bool result=[self executeNonQuery:query];
	;
	return result;
	
}

-(bool) removeAllActiveBuddies
{
		
	NSString* query=[NSString stringWithFormat:@"delete from activechats " ];
	//	debug_NSLog(query);
    
	
	bool result=[self executeNonQuery:query];
	;
	return result;
	
}



-(bool) addActiveBuddies:(NSString*) buddyname forAccount:(NSString*) accountNo;
{
	
	NSString* query=[NSString stringWithFormat:@"select count(buddy_name) from activechats where account_id=%@ and buddy_name='%@' ", accountNo, buddyname];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil)
	{
		int val=[count integerValue];
		if(val>0) {
			;
			return NO;
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
	
	return NO;
	
}


#pragma mark unread messages



-(int) countUserUnreadMessages:(NSString*) buddy forAccount:(NSString*) accountNo
{
	// count # messages from a specific user in messages table
	NSString* query=[NSString stringWithFormat:@"select count(message_history_id) from  message_history where unread=1 and account_id=%@ and message_from='%@'", accountNo, buddy];
	
	NSNumber* count=(NSNumber*)[self executeScalar:query];
	if(count!=nil)
	{
		int val=[count integerValue];
		return val;
	}
	else
	{
		return 0;
	}
}




#pragma db Commands

-(void) initDB
{
    _dbQueue = dispatch_queue_create(kMonalDBQueue, DISPATCH_QUEUE_SERIAL);
    _contactQueue = dispatch_queue_create(kMonalContactQueue, DISPATCH_QUEUE_SERIAL);
    
    
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
	
    
    dbversionCheck=[NSLock new];
	[self version];
	
	
}

-(void) version
{
    [dbversionCheck lock];
    
	// checking db version and upgrading if necessary
	debug_NSLog(@"Database version check");
	
	//<1.02 has no db version table but gtalk port is 443 . this is an identifier
	NSNumber* gtalkport= (NSNumber*)[self executeScalar:@"select default_port from  protocol   where protocol_name='GTalk';"];
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
	
	
	NSNumber* dbversion= (NSNumber*)[self executeScalar:@"select dbversion from dbversion"];
	debug_NSLog(@"Got db version %@", dbversion);
	
	
	if([dbversion doubleValue]<1.07)
	{
		debug_NSLog(@"Database version <1.07 detected. Performing upgrade");
		[self executeNonQuery:@"create table buddylistOnline (buddy_id integer not null primary key AUTOINCREMENT,account_id integer not null,buddy_name varchar(50), group_name varchar(100)); "];
		[self executeNonQuery:@"update dbversion set dbversion='1.07'; "];
		
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IdleAlert"];
		
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
		
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IdleAlert"];
		
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
            pass=[[PasswordManager alloc]  init:[NSString stringWithFormat:@"%@",[[rows objectAtIndex:counter] objectAtIndex:0]]];
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
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"OfflineContact"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MessagePreview"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Logging"];
        
        [self executeNonQuery:@"update dbversion set dbversion='1.073'; "];
        debug_NSLog(@"Upgrade to 1.073 success ");
        
    }
	
    
    
    if([dbversion doubleValue]<1.074)
    {
        debug_NSLog(@"Database version <1.074 detected. Performing upgrade on protocols. ");
        
        
        [self executeNonQuery:@"delete from protocol where protocol_id=3 "];
        [self executeNonQuery:@"delete from protocol where protocol_id=4 "];
        [self executeNonQuery:@" create table legacy_caps(capid integer not null primary key ,captext  varchar(20))"];
        
        [self executeNonQuery:@" insert into legacy_caps values (1,'pmuc-v1');"];
        [self executeNonQuery:@" insert into legacy_caps values (2,'voice-v1');"];
        [self executeNonQuery:@" insert into legacy_caps values (3,'camera-v1');"];
        [self executeNonQuery:@" insert into legacy_caps values (4, 'video-v1');"];
        
        
        
        [self executeNonQuery:@"create table buddy_resources(buddy_id integer,resource varchar(255),ver varchar(20))"];
        
        [self executeNonQuery:@"create table ver_info(ver varchar(20),cap varchar(255), primary key (ver,cap))"];
        
        [self executeNonQuery:@"create table buddy_resources_legacy_caps (buddy_id integer,resource varchar(255),capid  integer);"];
        
        [self executeNonQuery:@"update dbversion set dbversion='1.074'; "];
        debug_NSLog(@"Upgrade to 1.074 success ");
        
    }
	
    if([dbversion doubleValue]<1.1)
    {
        debug_NSLog(@"Database version <1.1 detected. Performing upgrade on accounts. ");
     
         [self executeNonQuery:@"alter table account add column selfsigned bool;"];
         [self executeNonQuery:@"alter table account add column oldstyleSSL bool; "];
        
        [self executeNonQuery:@"update dbversion set dbversion='1.1'; "];
        debug_NSLog(@"Upgrade to 1.1 success ");
        
    }
    
    
    if([dbversion doubleValue]<1.2)
    {
        debug_NSLog(@"Database version <1.2 detected. Performing upgrade on accounts. ");
        
        [self executeNonQuery:@"update  buddylist set iconhash=NULL;"];
        [self executeNonQuery:@"alter table message_history  add column unread bool;"];
        [self executeNonQuery:@" insert into message_history (account_id,message_from, message_to, timestamp, message, actual_from,unread) select account_id,message_from, message_to, timestamp, message, actual_from, 1  from messages ;"];
        [self executeNonQuery:@""];

        
        [self executeNonQuery:@"update dbversion set dbversion='1.2'; "];
        debug_NSLog(@"Upgrade to 1.2 success ");
        
    }

    
    [dbversionCheck unlock];
    
    [self resetContacts];
    
	return;
	
    
	
}

-(void) dealloc
{
	sqlite3_close(database); 
}



@end