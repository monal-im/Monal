//
//  DataLayer.h
//  SworIM
//
//  Created by Anurodh Pokharel on 3/28/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"
#import "XMPPPresence.h"
#import "MLMessage.h"
#import "MLContact.h"

NS_ASSUME_NONNULL_BEGIN

@interface DataLayer : NSObject

extern NSString* const kAccountID;
extern NSString* const kDomain;
extern NSString* const kEnabled;

extern NSString* const kServer;
extern NSString* const kPort;
extern NSString* const kResource;
extern NSString* const kDirectTLS;
extern NSString* const kSelfSigned;
extern NSString* const kRosterName;

extern NSString* const kUsername;

extern NSString* const kMessageType;
extern NSString* const kMessageTypeGeo;
extern NSString* const kMessageTypeImage;
extern NSString* const kMessageTypeMessageDraft;
extern NSString* const kMessageTypeStatus;
extern NSString* const kMessageTypeText;
extern NSString* const kMessageTypeUrl;

+(DataLayer*) sharedInstance;
-(void) version;

//Roster
-(NSString *) getRosterVersionForAccount:(NSString*) accountNo;
-(void) setRosterVersion:(NSString *) version forAccount: (NSString*) accountNo;

// Buddy Commands
-(BOOL) addContact:(NSString*) contact  forAccount:(NSString*) accountNo nickname:(NSString* _Nullable) nickName andMucNick:(NSString* _Nullable) mucNick;
-(void) removeBuddy:(NSString*) buddy forAccount:(NSString*) accountNo;
-(BOOL) clearBuddies:(NSString*) accountNo;
-(MLContact*) contactForUsername:(NSString*) username forAccount: (NSString*) accountNo;

/**
 should be called when a new session needs to be established
 */
-(BOOL) resetContactsForAccount:(NSString*) accountNo;

-(NSArray*) searchContactsWithString:(NSString*) search;

-(NSMutableArray*) onlineContactsSortedBy:(NSString*) sort;
-(NSArray*) resourcesForContact:(NSString*)contact ;
-(NSArray*) getSoftwareVersionInfoForContact:(NSString*)contact resource:(NSString*)resource andAccount:(NSString*)account;
-(void) setSoftwareVersionInfoForContact:(NSString*)contact
                                resource:(NSString*)resource
                              andAccount:(NSString*)account
                             withAppName:(NSString*)appName
                              appVersion:(NSString*)appVersion
                           andPlatformOS:(NSString*)platformOS;
-(NSMutableArray*) offlineContacts;

#pragma mark Ver string and Capabilities

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user andAccountNo:(NSString*) acctNo;
-(NSString*) getVerForUser:(NSString*) user andResource:(NSString*) resource;
-(void) setVer:(NSString*) ver forUser:(NSString*) user andResource:(NSString*) resource;
-(NSSet*) getCapsforVer:(NSString*) ver;
-(void) setCaps:(NSSet*) caps forVer:(NSString*) ver;

#pragma mark  presence functions
-(void) setResourceOnline:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo;
-(void) setOnlineBuddy:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo;
-(BOOL) setOfflineBuddy:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo;

-(void) setBuddyStatus:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo;
-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSString*) accountNo;

-(void) setBuddyState:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo;
-(NSString*) buddyState:(NSString*) buddy forAccount:(NSString*) accountNo;

-(BOOL) hasContactRequestForAccount:(NSString*) accountNo andBuddyName:(NSString*) buddy;
-(NSMutableArray*) contactRequestsForAccount;
-(void) addContactRequest:(MLContact *) requestor;
-(void) deleteContactRequest:(MLContact *) requestor; 

#pragma mark Contact info

-(void) setFullName:(NSString*) fullName forContact:(NSString*) contact andAccount:(NSString*) accountNo;

-(void) setAvatarHash:(NSString*) hash forContact:(NSString*) contact andAccount:(NSString*) accountNo;
-(NSString*) getAvatarHashForContact:(NSString*) buddy andAccount:(NSString*) accountNo;

-(BOOL) isBuddyOnline:(NSString*) buddy forAccount:(NSString*) accountNo;

-(BOOL) saveMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo withComment:(NSString*) comment;
-(NSString*) loadMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo;

#pragma mark - MUC

-(NSString *) ownNickNameforMuc:(NSString*) room andServer:(NSString*) server forAccount:(NSString*) accountNo;
-(BOOL) updateOwnNickName:(NSString *) nick forMuc:(NSString*) room andServer:(NSString*) server forAccount:(NSString*) accountNo;


-(BOOL) isBuddyMuc:(NSString*) buddy forAccount:(NSString*) accountNo;


-(NSMutableArray*) mucFavoritesForAccount:(NSString *) accountNo;
-(BOOL) addMucFavoriteForAccount:(NSString *) accountNo withRoom:(NSString *) room nick:(NSString *)nick autoJoin:(BOOL) autoJoin;
-(BOOL) deleteMucFavorite:(NSNumber *) mucid forAccountId:(NSInteger) accountNo;
-(BOOL) updateMucFavorite:(NSNumber *) mucid forAccountId:(NSInteger) accountNo autoJoin:(BOOL) autoJoin;
-(BOOL) updateMucSubject:(NSString *) subject forAccount:(NSString *) accountNo andRoom:(NSString *) room;
-(NSString*) mucSubjectforAccount:(NSString *) accountNo andRoom:(NSString *) room;

-(void) setMessageId:(NSString*) messageid stanzaId:(NSString *) stanzaId;

/**
 Calls with YES if contact  has already been added to the database for this account
 */
-(BOOL) isContactInList:(NSString*) buddy forAccount:(NSString*) accountNo;

#pragma mark - account commands
-(NSArray*) accountList;
-(NSNumber*) enabledAccountCnts;
-(NSArray*) enabledAccountList;
-(BOOL) isAccountEnabled:(NSString*) accountNo;
-(BOOL) doesAccountExistUser:(NSString*) user andDomain:(NSString *) domain;
-(NSNumber*) accountIDForUser:(NSString*) user andDomain:(NSString *) domain;

-(NSDictionary*) detailsForAccount:(NSString*) accountNo;
-(NSString*) jidOfAccount:(NSString*) accountNo;

-(BOOL) updateAccounWithDictionary:(NSDictionary *) dictionary;
-(NSNumber*) addAccountWithDictionary:(NSDictionary *) dictionary;


-(BOOL) removeAccount:(NSString*) accountNo;

/**
 disables account
 */
-(BOOL) disableEnabledAccount:(NSString*) accountNo;

-(NSMutableDictionary *) readStateForAccount:(NSString*) accountNo;
-(void) persistState:(NSMutableDictionary *) state forAccount:(NSString*) accountNo;

#pragma mark - message Commands
/**
 returns messages with the provided local id number
 */
-(MLMessage*) messageForHistoryID:(NSInteger) historyID;

/*
 adds a specified message to the database
 */
-(void) addMessageFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom sent:(BOOL) sent unread:(BOOL) unread messageId:(NSString *) messageid serverMessageId:(NSString *) stanzaid messageType:(NSString *) messageType andOverrideDate:(NSDate *) messageDate encrypted:(BOOL) encrypted backwards:(BOOL) backwards displayMarkerWanted:(BOOL) displayMarkerWanted withCompletion: (void (^)(BOOL, NSString*, NSNumber*))completion;

/*
 Marks a message as sent. When the server acked it
 */
-(void) setMessageId:(NSString*) messageid sent:(BOOL) sent;

/**
 Marked when the client on the other end replies with a recived message
 */
-(void) setMessageId:(NSString*) messageid received:(BOOL) received;

/**
 if the server replies with an error for a message, store it
 */
-(void) setMessageId:(NSString*) messageid errorType:(NSString *) errorType errorReason:(NSString *)errorReason;

/**
 sets a preview info for a specified message
 */
-(void) setMessageId:(NSString *) messageid previewText:(NSString *) text andPreviewImage:(NSString *) image;

-(void) clearMessages:(NSString *) accountNo;
-(void) deleteMessageHistory:(NSNumber *) messageNo;

#pragma mark - message history

-(NSNumber*) lastMessageHistoryIdForContact:(NSString*) buddy forAccount:(NSString*) accountNo;
-(NSMutableArray*) messagesForContact:(NSString*) buddy forAccount:(NSString*) accountNo beforeMsgHistoryID:(NSNumber*) msgHistoryID;
-(NSMutableArray*) messagesForContact:(NSString*) buddy forAccount:(NSString*) accountNo;


-(NSArray *) allMessagesForContact:(NSString* ) buddy forAccount:(NSString *) accountNo;
-(NSMutableArray*) lastMessageForContact:(NSString *) contact forAccount:(NSString *) accountNo;
-(NSString*) lastStanzaIdForAccount:(NSString*) accountNo;
-(void) setLastStanzaId:(NSString*) lastStanzaId forAccount:(NSString*) accountNo;

-(NSArray *) messageHistoryListDates:(NSString *) buddy forAccount: (NSString *) accountNo;
-(NSArray *) messageHistoryDateForContact:(NSString *) buddy forAccount:(NSString *) accountNo forDate:(NSString*) date;

/**
 retrieves the date of the the last message to or from this contact
 */
-(NSDate*) lastMessageDateForContact:(NSString*) contact andAccount:(NSString*) accountNo;

-(NSDate*) lastMessageDateAccount:(NSString*) accountNo;


-(BOOL) messageHistoryClean:(NSString*) buddy forAccount:(NSString*) accountNo;
-(BOOL) messageHistoryCleanAll;

-(NSMutableArray *) messageHistoryContacts:(NSString*) accountNo;
-(NSArray*) markMessagesAsReadForBuddy:(NSString*) buddy andAccount:(NSString*) accountNo tillStanzaId:(NSString* _Nullable) stanzaId wasOutgoing:(BOOL) outgoing;

-(void) addMessageHistoryFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString *)messageId encrypted:(BOOL) encrypted withCompletion:(void (^)(BOOL, NSString *))completion;

/**
retrieves the actual_from of the the last message from hisroty id
*/
-(NSString*)lastMessageActualFromByHistoryId:(NSNumber*) lastMsgHistoryId;

#pragma mark active contacts
-(NSMutableArray*) activeContactsWithPinned:(BOOL) pinned;
-(NSMutableArray*) activeContactDict;
-(void) removeActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo;
-(BOOL) addActiveBuddies:(NSString*) buddyname forAccount:(NSString*) accountNo;
-(BOOL) isActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo;
-(BOOL) updateActiveBuddy:(NSString*) buddyname setTime:(NSString *)timestamp forAccount:(NSString*) accountNo;



#pragma mark count unread
-(NSNumber*) countUserUnreadMessages:(NSString*) buddy forAccount:(NSString*) accountNo;
-(NSNumber*) countUnreadMessages;
//set all unread messages to read
-(void) setAllMessagesAsRead;

/**
 checks HTTP  head on URL to determine the message type
 */
-(NSString*) messageTypeForMessage:(NSString *) messageString withKeepThread:(BOOL) keepThread;


-(void) muteJid:(NSString *) jid;
-(void) unMuteJid:(NSString *) jid;
-(BOOL) isMutedJid:(NSString *) jid;


-(void) blockJid:(NSString *) jid;
-(void) unBlockJid:(NSString *) jid;
-(BOOL) isBlockedJid:(NSString *) jid;

-(BOOL) isPinnedChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid;
-(void) pinChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid;
-(void) unPinChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid;

-(BOOL) shouldEncryptForJid:(NSString *) jid andAccountNo:(NSString*) account;
-(void) encryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo;
-(void) disableEncryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo;

-(void) createImageCache:(NSString *) path forUrl:(NSString*) url;
-(void) deleteImageCacheForUrl:(NSString*) url;
-(NSString* _Nullable) imageCacheForUrl:(NSString* _Nonnull) url;
-(NSMutableArray*) allAttachmentsFromContact:(NSString*) contact forAccount:(NSString*) accountNo;
-(NSDate*) lastInteractionOfJid:(NSString* _Nonnull) jid forAccountNo:(NSString* _Nonnull) accountNo;
-(void) setLastInteraction:(NSDate*) lastInteractionTime forJid:(NSString* _Nonnull) jid andAccountNo:(NSString* _Nonnull) accountNo;

-(NSDictionary *) getSubscriptionForContact:(NSString*) contact andAccount:(NSString*) accountNo;
-(void) setSubscription:(NSString *)sub andAsk:(NSString*) ask forContact:(NSString*) contact andAccount:(NSString*) accountNo;

#pragma mark History Message Search
/*
 search message by keyword in message, message_from, actual_from, messageType.
 */
-(NSArray* _Nullable) searchResultOfHistoryMessageWithKeyWords:(NSString* _Nonnull) keyword
                                             accountNo:(NSString*  _Nonnull) accountNo;

/*
 search message by keyword in message, message_from, actual_from, messageType.
 */
-(NSArray* _Nullable) searchResultOfHistoryMessageWithKeyWords:(NSString* _Nonnull) keyword
                                             accountNo:(NSString*  _Nonnull) accountNo
                                          betweenBuddy:(NSString*  _Nonnull) accountJid1
                                              andBuddy:(NSString*  _Nonnull) accountJid2;
@end

NS_ASSUME_NONNULL_END
