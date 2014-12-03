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
#import "NSString+SqlLite.h"

#define kMonalDBQueue "im.monal.dbQueue"
#define kMonalContactQueue "im.monal.contactQueue"

@interface DataLayer : NSObject {

	NSString* dbPath;
	sqlite3* database;
    NSLock* dbversionCheck;
    
    dispatch_queue_t _dbQueue ;
    dispatch_queue_t _contactQueue ;
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
-(BOOL) removeBuddy:(NSString*) buddy forAccount:(NSString*) accountNo;
-(BOOL) clearBuddies:(NSString*) accountNo; 
-(NSArray*) contactForUsername:(NSString*) username forAccount: (NSString*) accountNo;

/**
 called when an account goes offline. removes all of its contacts state info
 */
-(BOOL) resetContactsForAccount:(NSString*) accountNo;
-(BOOL) resetContacts;

-(NSArray*) onlineBuddiesSortedBy:(NSString*) sort;
-(NSArray*) resourcesForContact:(NSString*)contact ;
-(NSArray*) offlineContacts;

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

-(BOOL) setFullName:(NSString*) fullName forBuddy:(NSString*) buddy andAccount:(NSString*) accountNo;
-(NSString*) fullName:(NSString*) buddy forAccount:(NSString*) accountNo; 
//-(BOOL) setFileName:(NSString*) fileName forBuddy:(NSString*) buddy andAccount:(NSString*) accountNo;

-(BOOL) setBuddyHash:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
-(NSString*) buddyHash:(NSString*) buddy forAccount:(NSString*) accountNo;

-(bool) isBuddyOnline:(NSString*) buddy forAccount:(NSString*) accountNo ;

-(bool) isBuddyMuc:(NSString*) buddy forAccount:(NSString*) accountNo;


-(bool) isBuddyAdded:(NSString*) buddy forAccount:(NSString*) accountNo ;
-(bool) isBuddyRemoved:(NSString*) buddy forAccount:(NSString*) accountNo ;

-(bool) isBuddyInList:(NSString*) buddy forAccount:(NSString*) accountNo ;

//vcard commands

-(BOOL) setIconName:(NSString*) icon forBuddy:(NSString*) buddy inAccount:(NSString*) accountNo;
-(NSString*) iconName:(NSString*) buddy forAccount:(NSString*) accountNo;
-(BOOL) setNickName:(NSString*) nickName forBuddy:(NSString*) buddy andAccount:(NSString*) accountNo;

//account commands
-(NSArray*) protocolList;
-(NSArray*) accountList;
-(NSArray*) enabledAccountList;
-(BOOL) isAccountEnabled:(NSString*) accountNo;

-(NSArray*) accountVals:(NSString*) accountNo; 
-(BOOL) addAccount: (NSString*) name :(NSString*) theProtocol :(NSString*) username: (NSString*) password: (NSString*) server
                  : (NSString*) otherport: (bool) secure: (NSString*) resource: (NSString*) thedomain:(bool) enabled :(bool) selfsigned: (bool) oldstyle;

-(BOOL) updateAccount: (NSString*) name :(NSString*) theProtocol :(NSString*) username: (NSString*) password: (NSString*) server
					 : (NSString*) otherport: (bool) secure: (NSString*) resource: (NSString*) thedomain: (bool) enabled: (NSString*) accountNo :(bool) selfsigned: (bool) oldstyle;

-(BOOL) removeAccount:(NSString*) accountNo; 

/**
 disables account
 */
-(BOOL) disableEnabledAccount:(NSString*) accountNo;

#pragma mark message Commands
-(NSString *) messageForHistoryID:(NSInteger) historyID;

-(BOOL) addMessageFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom delivered:(BOOL) delivered;
-(BOOL) setMessageId:(NSString*) messageid delivered:(BOOL) delivered;

-(BOOL) clearMessages:(NSString*) accountNo;
-(BOOL) deleteMessage:(NSString*) messageNo;
-(BOOL) deleteMessageHistory:(NSString*) messageNo;

#pragma mark message history
-(NSMutableArray*) messageHistory:(NSString*) buddy forAccount:(NSString*) accountNo;
-(NSArray*) messageHistoryAll:(NSString*) buddy forAccount:(NSString*) accountNo; 

-(NSArray*) messageHistoryListDates:(NSString*) buddy forAccount: (NSString*) accountNo;
-(NSArray*) messageHistoryDate:(NSString*) buddy forAccount:(NSString*) accountNo forDate:(NSString*) date;

-(BOOL) messageHistoryClean:(NSString*) buddy :(NSString*) accountNo;
-(BOOL) messageHistoryCleanAll;

-(NSArray*) messageHistoryBuddies:(NSString*) accountNo;
-(BOOL) markAsReadBuddy:(NSString*) buddy forAccount:(NSString*) accountNo;
-(BOOL) addMessageHistoryFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString *)messageId;

#pragma mark active chats
-(NSArray*) activeBuddies;
-(bool) removeActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo;
-(bool) removeAllActiveBuddies;
-(bool) addActiveBuddies:(NSString*) buddyname forAccount:(NSString*) accountNo;

#pragma mark count unread
-(int) countUnreadMessagesForAccount:(NSString*) accountNo;
-(int) countUserUnreadMessages:(NSString*) buddy forAccount:(NSString*) accountNo;
-(int) countOtherUnreadMessages:(NSString*) buddy forAccount:(NSString*) accountNo;
-(int) countUnreadMessages;

@end
