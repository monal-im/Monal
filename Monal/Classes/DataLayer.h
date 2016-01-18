//
//  DataLayer.h
//  SworIM
//
//  Created by Anurodh Pokharel on 3/28/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sqlite3.h>
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


extern NSString *const kAccountID;
extern NSString *const kAccountName;
extern NSString *const kDomain;
extern NSString *const kEnabled;

extern NSString *const kServer;
extern NSString *const kPort;
extern NSString *const kResource;
extern NSString *const kSSL;
extern NSString *const kOldSSL;
extern NSString *const kSelfSigned;
extern NSString *const kOauth;

extern NSString *const kUsername;
extern NSString *const kFullName;

extern NSString *const kContactName;
extern NSString *const kCount;


+ (DataLayer* )sharedInstance;

-(void) initDB;
-(void) version;

//lowest level command handlers
-(NSObject*) executeScalar:(NSString*) query  __deprecated;
-(NSArray*) executeReader:(NSString*) query __deprecated;
-(BOOL) executeNonQuery:(NSString*) query __deprecated;

// V2 low level
-(void) executeScalar:(NSString*) query withCompletion: (void (^)(NSObject *))completion;
-(void) executeReader:(NSString*) query withCompletion: (void (^)(NSArray *))completion;
-(void) executeNonQuery:(NSString*) query withCompletion: (void (^)(BOOL))completion;

// Buddy Commands
-(BOOL) addBuddy:(NSString*) buddy  forAccount:(NSString*) accountNo fullname:(NSString*)fullName nickname:(NSString*) nickName;
-(BOOL) removeBuddy:(NSString*) buddy forAccount:(NSString*) accountNo;
-(BOOL) clearBuddies:(NSString*) accountNo; 
-(void) contactForUsername:(NSString*) username forAccount: (NSString*) accountNo withCompletion: (void (^)(NSArray *))completion;

/**
 called when an account goes offline. removes all of its contacts state info
 */
-(BOOL) resetContactsForAccount:(NSString*) accountNo;
-(BOOL) resetContacts;


-(NSArray*) searchContactsWithString:(NSString*) search;
-(NSArray*) onlineContactsSortedBy:(NSString*) sort;
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
-(void) setResourceOnline:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
-(void) setOnlineBuddy:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
-(BOOL) setOfflineBuddy:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;

-(void) setBuddyStatus:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSString*) accountNo;

-(void) setBuddyState:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
-(NSString*) buddyState:(NSString*) buddy forAccount:(NSString*) accountNo;


#pragma mark Contact info

-(BOOL) setFullName:(NSString*) fullName forBuddy:(NSString*) buddy andAccount:(NSString*) accountNo;
-(NSString*) fullName:(NSString*) buddy forAccount:(NSString*) accountNo; 
//-(BOOL) setFileName:(NSString*) fileName forBuddy:(NSString*) buddy andAccount:(NSString*) accountNo;

-(BOOL) setBuddyHash:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
-(NSString*) buddyHash:(NSString*) buddy forAccount:(NSString*) accountNo;

-(void) isBuddyOnline:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion: (void (^)(BOOL))completion;

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

-(void) updateAccounWithDictionary:(NSDictionary *) dictionary andCompletion:(void (^)(BOOL))completion;;
-(void) addAccountWithDictionary:(NSDictionary *) dictionary andCompletion: (void (^)(BOOL))completion;;


-(BOOL) removeAccount:(NSString*) accountNo; 

/**
 disables account
 */
-(BOOL) disableEnabledAccount:(NSString*) accountNo;

#pragma mark message Commands
-(NSArray *) messageForHistoryID:(NSInteger) historyID;

-(BOOL) addMessageFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom delivered:(BOOL) delivered unread:(BOOL) unread;
-(void) setMessageId:(NSString*) messageid delivered:(BOOL) delivered;

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
-(void) markAsReadBuddy:(NSString*) buddy forAccount:(NSString*) accountNo;
-(void) addMessageHistoryFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString *)messageId withCompletion:(void (^)(BOOL))completion;

#pragma mark active chats
-(NSArray*) activeBuddies;
-(bool) removeActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo;
-(bool) removeAllActiveBuddies;
-(void) addActiveBuddies:(NSString*) buddyname forAccount:(NSString*) accountNo withCompletion: (void (^)(BOOL))completion;
-(void) isActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo withCompletion: (void (^)(BOOL))completion;


#pragma mark count unread
-(void) countUserUnreadMessages:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion: (void (^)(NSNumber *))completion;
-(void) countUnreadMessagesWithCompletion: (void (^)(NSNumber *))completion;

-(void) countUserMessages:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion: (void (^)(NSNumber *))completion;


@end
