//
//  DataLayer.h
//  SworIM
//
//  Created by Anurodh Pokharel on 3/28/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import "PasswordManager.h"
#import "presence.h"

@interface DataLayer : NSObject {

	NSString* dbPath;
	sqlite3* database;
    NSLock* dbversionCheck; 
}


+ (id)sharedInstance;

-(void) initDB;
-(void) version; 

//lowest level command handlers
-(NSObject*) executeScalar:(NSString*) query; 
-(NSArray*) executeReader:(NSString*) query; 
-(BOOL) executeNonQuery:(NSString*) query; 

// Buddy Commands
-(BOOL) addBuddy:(NSString*) buddy :(NSString*) accountNo:(NSString*) fullName:(NSString*) nickName;
-(BOOL) removeBuddy:(NSString*) buddy :(NSString*) accountNo; 
-(BOOL) clearBuddies:(NSString*) accountNo; 

-(BOOL) resetBuddies;
-(NSArray*) onlineBuddies:(NSString*) accountNo;
-(NSArray*) offlineBuddies:(NSString*) accountNo;

-(NSArray*) newBuddies:(NSString*) accountNo;
-(NSArray*) removedBuddies:(NSString*) accountNo;
-(NSArray*) updatedBuddies:(NSString*) accountNo;
-(BOOL) markBuddiesRead:(NSString*) accountNo;


#pragma mark  presence functions
-(BOOL) setResourceOnline:(presence*)presenceObj: (NSString*) accountNo;
-(BOOL) setOnlineBuddy:(presence*)presenceObj: (NSString*) accountNo;
-(BOOL) setOfflineBuddy:(presence*)presenceObj: (NSString*) accountNo;

-(BOOL) setBuddyStatus:(presence*)presenceObj: (NSString*) accountNo;
-(NSString*) buddyStatus:(NSString*) buddy :(NSString*) accountNo;

-(BOOL) setBuddyState:(presence*)presenceObj: (NSString*) accountNo;
-(NSString*) buddyState:(NSString*) buddy :(NSString*) accountNo;


#pragma mark Contact info

-(BOOL) setFullName:(NSString*) buddy :(NSString*) accountNo:(NSString*) fullName;
-(NSString*) fullName:(NSString*) buddy :(NSString*) accountNo; 

-(BOOL) setFileName:(NSString*) buddy :(NSString*) accountNo:(NSString*) fileName;



-(BOOL) setBuddyHash:(NSString*) buddy :(NSString*) accountNo:(NSString*) theHash;
-(NSString*) buddyHash:(NSString*) buddy :(NSString*) accountNo; 

-(bool) isBuddyOnline:(NSString*) buddy :(NSString*) accountNo ;
-(bool) isBuddyMuc:(NSString*) buddy :(NSString*) accountNo;

-(bool) isBuddyAdded:(NSString*) buddy :(NSString*) accountNo ;
-(bool) isBuddyRemoved:(NSString*) buddy :(NSString*) accountNo ;

-(bool) isBuddyInList:(NSString*) buddy :(NSString*) accountNo ;

//vcard commands

-(BOOL) setIconName:(NSString*) buddy :(NSString*) accountNo:(NSString*) icon;
-(NSString*) iconName:(NSString*) buddy :(NSString*) accountNo; 
 

-(BOOL) setNickName:(NSString*) buddy :(NSString*) accountNo:(NSString*) nickName;


//account commands
-(NSArray*) protocolList;
-(NSArray*) accountList;
-(NSArray*) enabledAccountList;

-(NSArray*) accountVals:(NSString*) accountNo; 
-(BOOL) addAccount: (NSString*) name :(NSString*) theProtocol :(NSString*) username: (NSString*) password: (NSString*) server
				  : (NSString*) otherport: (bool) secure: (NSString*) resource: (NSString*) thedomain:(bool) enabled;
-(BOOL) updateAccount: (NSString*) name :(NSString*) theProtocol :(NSString*) username: (NSString*) password: (NSString*) server
					 : (NSString*) otherport: (bool) secure: (NSString*) resource: (NSString*) thedomain: (bool) enabled: (NSString*) accountNo;
-(BOOL) removeAccount:(NSString*) accountNo; 

-(BOOL) removeEnabledAccount; 






//message Commands
-(BOOL) addMessage:(NSString*) from :(NSString*) to :(NSString*) accountNo:(NSString*) message:(NSString*) actualfrom ;
-(BOOL) clearMessages:(NSString*) accountNo; 

//message history
-(NSArray*) messageHistory:(NSString*) buddy :(NSString*) accountNo;
-(NSArray*) messageHistoryAll:(NSString*) buddy :(NSString*) accountNo; //we're going to stop using this.. 

-(NSArray*) messageHistoryListDates:(NSString*) buddy :(NSString*) accountNo; 
-(NSArray*) messageHistoryDate:(NSString*) buddy :(NSString*) accountNo:(NSString*) date; 

-(BOOL) messageHistoryClean:(NSString*) buddy :(NSString*) accountNo;
-(BOOL) messageHistoryCleanAll:(NSString*) accountNo;

-(NSArray*) messageHistoryBuddies:(NSString*) accountNo;
-(BOOL) markAsRead:(NSString*) buddy :(NSString*) accountNo;
-(BOOL) addMessageHistory:(NSString*) from :(NSString*) to :(NSString*) accountNo:(NSString*) message:(NSString*) actualfrom ;



//new messages
-(NSArray*) unreadMessagesForBuddy:(NSString*) buddy :(NSString*) accountNo;
-(NSArray*) unreadMessages:(NSString*) accountNo;
//active chats
-(NSArray*) activeBuddies:(NSString*) accountNo;
-(bool) removeActiveBuddies:(NSString*) buddyname:(NSString*) accountNo;
-(bool) removeAllActiveBuddies:(NSString*) accountNo;
-(bool) addActiveBuddies:(NSString*) buddyname:(NSString*) accountNo;

//count unread
-(int) countUnnoticedMessages:(NSString*) accountNo; 
-(NSArray*) unnoticedMessages:(NSString*) accountNo;
-(BOOL) markAsNoticed:(NSString*) accountNo;


-(int) countUnreadMessages:(NSString*) accountNo; 
-(int) countUserUnreadMessages:(NSString*) buddy :(NSString*) accountNo;
-(int) countOtherUnreadMessages:(NSString*) buddy :(NSString*) accountNo;

@end
