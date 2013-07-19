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
#import "ParsePresence.h"

#define kMonalDBQueue "im.monal.dbQueue"

@interface DataLayer : NSObject {

	NSString* dbPath;
	sqlite3* database;
    NSLock* dbversionCheck;
    
    dispatch_queue_t _dbQueue ;
}


+ (id)sharedInstance;

-(void) initDB;
-(void) version; 

//lowest level command handlers
-(NSObject*) executeScalar:(NSString*) query; 
-(NSArray*) executeReader:(NSString*) query; 
-(BOOL) executeNonQuery:(NSString*) query; 

// Buddy Commands
-(BOOL) addBuddy:(NSString*) buddy  forAccount:(NSString*) accountNo fullname:(NSString*)fullName nickname:(NSString*) nickName;
-(BOOL) removeBuddy:(NSString*) buddy :(NSString*) accountNo; 
-(BOOL) clearBuddies:(NSString*) accountNo; 
-(NSArray*) contactForUsername:(NSString*) username forAccount: (NSString*) accountNo;

/**
 called when an account goes offline. removes all of its contacts state info
 */
-(BOOL) resetContactsForAccount:(NSString*) accountNo;
-(BOOL) resetContacts;

-(NSArray*) onlineBuddiesSortedBy:(NSString*) sort;

-(NSArray*) offlineBuddies;

-(NSArray*) newBuddies:(NSString*) accountNo;
-(NSArray*) removedBuddies:(NSString*) accountNo;
-(NSArray*) updatedBuddies:(NSString*) accountNo;
-(BOOL) markBuddiesRead:(NSString*) accountNo;

#pragma mark Ver string and Capabilities
-(BOOL) setResourceVer:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
-(NSArray*) capsforVer:(NSString*) verString;
-(NSString*)getVerForUser:(NSString*)user Resource:(NSString*) resource;

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user accountNo:(NSString*) acctNo;

-(BOOL)setFeature:(NSString*)feature  forVer:(NSString*) ver;

#pragma mark legacy caps
-(void) clearLegacyCaps;
//-(BOOL) setLegacyCap:(NSString*)cap forUser:(presence*)presenceObj accountNo:(NSString*) acctNo;
-(BOOL) checkLegacyCap:(NSString*)cap forUser:(NSString*) user accountNo:(NSString*) acctNo;



#pragma mark  presence functions
-(BOOL) setResourceOnline:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
-(BOOL) setOnlineBuddy:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
-(BOOL) setOfflineBuddy:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;

-(BOOL) setBuddyStatus:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSString*) accountNo;

-(BOOL) setBuddyState:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
-(NSString*) buddyState:(NSString*) buddy forAccount:(NSString*) accountNo;


#pragma mark Contact info

-(BOOL) setFullName:(NSString*) buddy :(NSString*) accountNo:(NSString*) fullName;
-(NSString*) fullName:(NSString*) buddy :(NSString*) accountNo; 

-(BOOL) setFileName:(NSString*) buddy :(NSString*) accountNo:(NSString*) fileName;



-(BOOL) setBuddyHash:(NSString*) buddy :(NSString*) accountNo:(NSString*) theHash;
-(NSString*) buddyHash:(NSString*) buddy :(NSString*) accountNo; 

-(NSArray*)getResourcesForUser:(NSString*)user ;

-(bool) isBuddyOnline:(NSString*) buddy forAccount:(NSString*) accountNo ;
-(bool) isBuddyMuc:(NSString*) buddy forAccount:(NSString*) accountNo;

-(bool) isBuddyAdded:(NSString*) buddy forAccount:(NSString*) accountNo ;
-(bool) isBuddyRemoved:(NSString*) buddy forAccount:(NSString*) accountNo ;

-(bool) isBuddyInList:(NSString*) buddy forAccount:(NSString*) accountNo ;

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
                  : (NSString*) otherport: (bool) secure: (NSString*) resource: (NSString*) thedomain:(bool) enabled :(bool) selfsigned: (bool) oldstyle;

-(BOOL) updateAccount: (NSString*) name :(NSString*) theProtocol :(NSString*) username: (NSString*) password: (NSString*) server
					 : (NSString*) otherport: (bool) secure: (NSString*) resource: (NSString*) thedomain: (bool) enabled: (NSString*) accountNo :(bool) selfsigned: (bool) oldstyle;

-(BOOL) removeAccount:(NSString*) accountNo; 

-(BOOL) removeEnabledAccount; 

#pragma mark message Commands
-(BOOL) addMessageFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom ;
-(BOOL) clearMessages:(NSString*) accountNo; 

#pragma mark message history
-(NSArray*) messageHistory:(NSString*) buddy forAccount:(NSString*) accountNo;
-(NSArray*) messageHistoryAll:(NSString*) buddy forAccount:(NSString*) accountNo; //we're going to stop using this.. 

-(NSArray*) messageHistoryListDates:(NSString*) buddy :(NSString*) accountNo; 
-(NSArray*) messageHistoryDate:(NSString*) buddy :(NSString*) accountNo:(NSString*) date; 

-(BOOL) messageHistoryClean:(NSString*) buddy :(NSString*) accountNo;
-(BOOL) messageHistoryCleanAll:(NSString*) accountNo;

-(NSArray*) messageHistoryBuddies:(NSString*) accountNo;
-(BOOL) markAsRead:(NSString*) buddy :(NSString*) accountNo;
-(BOOL) addMessageHistoryFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom ;

#pragma mark new messages
-(NSArray*) unreadMessagesForBuddy:(NSString*) buddy :(NSString*) accountNo;
-(NSArray*) unreadMessages:(NSString*) accountNo;
#pragma mark active chats
-(NSArray*) activeBuddies:(NSString*) accountNo;
-(bool) removeActiveBuddies:(NSString*) buddyname:(NSString*) accountNo;
-(bool) removeAllActiveBuddies:(NSString*) accountNo;
-(bool) addActiveBuddies:(NSString*) buddyname:(NSString*) accountNo;

#pragma mark count unread
-(int) countUnnoticedMessages:(NSString*) accountNo; 
-(NSArray*) unnoticedMessages:(NSString*) accountNo;
-(BOOL) markAsNoticed:(NSString*) accountNo;


-(int) countUnreadMessagesForAccount:(NSString*) accountNo;
-(int) countUserUnreadMessages:(NSString*) buddy forAccount:(NSString*) accountNo;
-(int) countOtherUnreadMessages:(NSString*) buddy forAccount:(NSString*) accountNo;

@end
