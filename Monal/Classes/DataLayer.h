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
extern NSString* const kAccountState;
extern NSString* const kDomain;
extern NSString* const kEnabled;

extern NSString* const kServer;
extern NSString* const kPort;
extern NSString* const kResource;
extern NSString* const kDirectTLS;
extern NSString* const kRosterName;

extern NSString* const kUsername;

extern NSString* const kMessageTypeStatus;
extern NSString* const kMessageTypeMessageDraft;
extern NSString* const kMessageTypeText;
extern NSString* const kMessageTypeGeo;
extern NSString* const kMessageTypeUrl;
extern NSString* const kMessageTypeFiletransfer;

+(DataLayer*) sharedInstance;
-(NSString* _Nullable) exportDB;
-(void) createTransaction:(monal_void_block_t) block;

//Roster
-(NSString *) getRosterVersionForAccount:(NSString*) accountNo;
-(void) setRosterVersion:(NSString *) version forAccount: (NSString*) accountNo;

// Buddy Commands
-(BOOL) addContact:(NSString*) contact  forAccount:(NSString*) accountNo nickname:(NSString* _Nullable) nickName andMucNick:(NSString* _Nullable) mucNick;
-(void) removeBuddy:(NSString*) buddy forAccount:(NSString*) accountNo;
-(BOOL) clearBuddies:(NSString*) accountNo;
-(NSDictionary* _Nullable) contactDictionaryForUsername:(NSString*) username forAccount: (NSString*) accountNo;

/**
 should be called when a new session needs to be established
 */
-(BOOL) resetContactsForAccount:(NSString*) accountNo;

-(NSMutableArray<MLContact*>*) searchContactsWithString:(NSString*) search;

-(NSMutableArray<MLContact*>*) contactList;
-(NSArray*) resourcesForContact:(NSString*)contact ;
-(NSArray*) getSoftwareVersionInfoForContact:(NSString*)contact resource:(NSString*)resource andAccount:(NSString*)account;
-(void) setSoftwareVersionInfoForContact:(NSString*)contact
                                resource:(NSString*)resource
                              andAccount:(NSString*)account
                             withAppName:(NSString*)appName
                              appVersion:(NSString*)appVersion
                           andPlatformOS:(NSString*)platformOS;

#pragma mark Ver string and Capabilities

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user andAccountNo:(NSString*) acctNo;
-(NSString*) getVerForUser:(NSString*) user andResource:(NSString*) resource;
-(void) setVer:(NSString*) ver forUser:(NSString*) user andResource:(NSString*) resource;
-(NSSet* _Nullable) getCapsforVer:(NSString*) ver;
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

-(BOOL) saveMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo withComment:(NSString*) comment;
-(NSString*) loadMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo;

#pragma mark - MUC

-(BOOL) initMuc:(NSString*) room forAccountId:(NSString*) accountNo andMucNick:(NSString* _Nullable) mucNick;
-(void) cleanupMembersAndParticipantsListFor:(NSString*) room forAccountId:(NSString*) accountNo;
-(void) addMember:(NSDictionary*) member toMuc:(NSString*) room forAccountId:(NSString*) accountNo;
-(void) removeMember:(NSDictionary*) member fromMuc:(NSString*) room forAccountId:(NSString*) accountNo;
-(void) addParticipant:(NSDictionary*) participant toMuc:(NSString*) room forAccountId:(NSString*) accountNo;
-(void) removeParticipant:(NSDictionary*) participant fromMuc:(NSString*) room forAccountId:(NSString*) accountNo;
-(NSString* _Nullable) getParticipantForNick:(NSString*) nick inRoom:(NSString*) room forAccountId:(NSString*) accountNo;
-(NSArray<NSDictionary<NSString*, id>*>*) getMembersAndParticipantsOfMuc:(NSString*) room forAccountId:(NSString*) accountNo;
-(void) addMucFavorite:(NSString*) room forAccountId:(NSString*) accountNo andMucNick:(NSString* _Nullable) mucNick;
-(NSString*) lastStanzaIdForMuc:(NSString* _Nonnull) room andAccount:(NSString* _Nonnull) accountNo;
-(void) setLastStanzaId:(NSString*) lastStanzaId forMuc:(NSString* _Nonnull) room andAccount:(NSString* _Nonnull) accountNo;
-(BOOL) isBuddyMuc:(NSString*) buddy forAccount:(NSString*) accountNo;

-(NSString* _Nullable) ownNickNameforMuc:(NSString*) room forAccount:(NSString*) accountNo;
-(BOOL) updateOwnNickName:(NSString*) nick forMuc:(NSString*) room forAccount:(NSString*) accountNo;

-(BOOL) updateMucSubject:(NSString*) subject forAccount:(NSString*) accountNo andRoom:(NSString*) room;
-(NSString*) mucSubjectforAccount:(NSString*) accountNo andRoom:(NSString*) room;

-(NSMutableArray*) listMucsForAccount:(NSString*) accountNo;
-(BOOL) deleteMuc:(NSString*) room forAccountId:(NSString*) accountNo;

-(void) updateMucTypeTo:(NSString*) type forRoom:(NSString*) room andAccount:(NSString*) accountNo;
-(NSString*) getMucTypeOfRoom:(NSString*) room andAccount:(NSString*) accountNo;

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
-(NSNumber* _Nullable) accountIDForUser:(NSString*) user andDomain:(NSString *) domain;

-(NSMutableDictionary* _Nullable) detailsForAccount:(NSString*) accountNo;
-(NSString* _Nullable) jidOfAccount:(NSString*) accountNo;

-(BOOL) updateAccounWithDictionary:(NSDictionary *) dictionary;
-(NSNumber* _Nullable) addAccountWithDictionary:(NSDictionary *) dictionary;


-(BOOL) removeAccount:(NSString*) accountNo;

/**
 disables account
 */
-(BOOL) disableEnabledAccount:(NSString*) accountNo;

-(NSMutableDictionary* _Nullable) readStateForAccount:(NSString*) accountNo;
-(void) persistState:(NSDictionary*) state forAccount:(NSString*) accountNo;

#pragma mark - message Commands
/**
 returns messages with the provided local id number
 */
-(NSArray<MLMessage*>*) messagesForHistoryIDs:(NSArray<NSNumber*>*) historyIDs;
-(MLMessage* _Nullable) messageForHistoryID:(NSNumber* _Nullable) historyID;
-(NSNumber*) getSmallestHistoryId;

/*
 adds a specified message to the database
 */
-(NSNumber*) addMessageToChatBuddy:(NSString*) buddyName withInboundDir:(BOOL) inbound forAccount:(NSString*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom participantJid:(NSString*_Nullable) participantJid sent:(BOOL) sent unread:(BOOL) unread messageId:(NSString*) messageid serverMessageId:(NSString*) stanzaid messageType:(NSString*) messageType andOverrideDate:(NSDate*) messageDate encrypted:(BOOL) encrypted displayMarkerWanted:(BOOL) displayMarkerWanted usingHistoryId:(NSNumber* _Nullable) historyId checkForDuplicates:(BOOL) checkForDuplicates;

/*
 Marks a message as sent. When the server acked it
 */
-(void) setMessageId:(NSString*_Nonnull) messageid sent:(BOOL) sent;

/**
 Marked when the client on the other end replies with a recived message
 */
-(void) setMessageId:( NSString* _Nonnull ) messageid received:(BOOL) received;
/**
 if the server replies with an error for a message, store it
 */
-(void) setMessageId:(NSString* _Nonnull) messageid errorType:(NSString *_Nonnull) errorType errorReason:(NSString *_Nonnull)errorReason;

/**
 sets a preview info for a specified message
 */
-(void) setMessageId:(NSString*_Nonnull) messageid previewText:(NSString *) text andPreviewImage:(NSString *) image;

-(void) setMessageId:(NSString*) messageid stanzaId:(NSString *) stanzaId;
-(void) setMessageHistoryId:(NSNumber*) historyId filetransferMimeType:(NSString*) mimeType filetransferSize:(NSNumber*) size;
-(void) setMessageHistoryId:(NSNumber*) historyId messageType:(NSString*) messageType;

-(void) clearMessages:(NSString *) accountNo;
-(void) deleteMessageHistory:(NSNumber *) messageNo;
-(void) updateMessageHistory:(NSNumber*) messageNo withText:(NSString*) newText;
-(NSNumber* _Nullable) getHistoryIDForMessageId:(NSString*) messageid from:(NSString*) from andAccount:(NSString*) accountNo;

-(BOOL) checkLMCEligible:(NSNumber*) historyID encrypted:(BOOL) encrypted historyBaseID:(NSNumber* _Nullable) historyBaseID;

#pragma mark - message history

-(NSNumber*) lastMessageHistoryIdForContact:(NSString*) buddy forAccount:(NSString*) accountNo;
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSString*) accountNo beforeMsgHistoryID:(NSNumber* _Nullable) msgHistoryID;
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSString*) accountNo;


-(MLMessage*) lastMessageForContact:(NSString *) contact forAccount:(NSString *) accountNo;
-(NSString*) lastStanzaIdForAccount:(NSString*) accountNo;
-(void) setLastStanzaId:(NSString*) lastStanzaId forAccount:(NSString*) accountNo;

-(BOOL) messageHistoryClean:(NSString*) buddy forAccount:(NSString*) accountNo;

-(NSArray<MLMessage*>*) markMessagesAsReadForBuddy:(NSString*) buddy andAccount:(NSString*) accountNo tillStanzaId:(NSString* _Nullable) stanzaId wasOutgoing:(BOOL) outgoing;

-(NSNumber*) addMessageHistoryTo:(NSString*) to forAccount:(NSString*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString*) messageId encrypted:(BOOL) encrypted messageType:(NSString*) messageType mimeType:(NSString* _Nullable) mimeType size:(NSNumber* _Nullable) size;

#pragma mark active contacts
-(NSMutableArray<MLContact*>*) activeContactsWithPinned:(BOOL) pinned;
-(NSArray<MLContact*>*) activeContactDict;
-(void) removeActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo;
-(void) addActiveBuddies:(NSString*) buddyname forAccount:(NSString*) accountNo;
-(BOOL) isActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo;
-(BOOL) updateActiveBuddy:(NSString*) buddyname setTime:(NSString *)timestamp forAccount:(NSString*) accountNo;



#pragma mark count unread
-(NSNumber*) countUserUnreadMessages:(NSString* _Nullable) buddy forAccount:(NSString* _Nullable) accountNo;
-(NSNumber*) countUnreadMessages;
//set all unread messages to read
-(void) setAllMessagesAsRead;

-(void) muteJid:(NSString*) jid onAccount:(NSString*) accountNo;
-(void) unMuteJid:(NSString*) jid onAccount:(NSString*) accountNo;
-(BOOL) isMutedJid:(NSString*) jid onAccount:(NSString*) accountNo;

-(void) blockJid:(NSString *) jid withAccountNo:(NSString*) accountNo;
-(void) unBlockJid:(NSString *) jid withAccountNo:(NSString*) accountNo;
-(u_int8_t) isBlockedJid:(NSString *) jid withAccountNo:(NSString*) accountNo;
-(void) updateLocalBlocklistCache:(NSSet<NSString*>*) blockedJids forAccountNo:(NSString*) accountNo;
-(NSArray<NSDictionary<NSString*, NSString*>*>*) blockedJidsForAccount:(NSString*) accountNo;

-(BOOL) isPinnedChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid;
-(void) pinChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid;
-(void) unPinChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid;

-(BOOL) shouldEncryptForJid:(NSString *) jid andAccountNo:(NSString*) account;
-(void) encryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo;
-(void) disableEncryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo;

-(NSMutableArray*) allAttachmentsFromContact:(NSString*) contact forAccount:(NSString*) accountNo;
-(NSDate*) lastInteractionOfJid:(NSString* _Nonnull) jid forAccountNo:(NSString* _Nonnull) accountNo;
-(void) setLastInteraction:(NSDate*) lastInteractionTime forJid:(NSString* _Nonnull) jid andAccountNo:(NSString* _Nonnull) accountNo;

-(NSDictionary *) getSubscriptionForContact:(NSString*) contact andAccount:(NSString*) accountNo;
-(void) setSubscription:(NSString *)sub andAsk:(NSString*) ask forContact:(NSString*) contact andAccount:(NSString*) accountNo;

#pragma mark History Message Search
/*
 search message by keyword in message, buddy_name, messageType.
 */
-(NSArray* _Nullable) searchResultOfHistoryMessageWithKeyWords:(NSString* _Nonnull) keyword
                                             accountNo:(NSString*  _Nonnull) accountNo;

/*
 search message by keyword in message, buddy_name, messageType.
 */
-(NSArray* _Nullable) searchResultOfHistoryMessageWithKeyWords:(NSString* _Nonnull) keyword
                                             accountNo:(NSString*  _Nonnull) accountNo
                                             betweenBuddy:(NSString* _Nonnull) contactJid;

-(NSArray*) getAllCachedImages;
-(void) removeImageCacheTables;
-(NSArray*) getAllMessagesForFiletransferUrl:(NSString*) url;
-(void) upgradeImageMessagesToFiletransferMessages;


-(void) invalidateAllAccountStates;

-(void) addShareSheetPayload:(NSDictionary*) payload;
-(NSArray*) getShareSheetPayloadForAccountNo:(NSString*) accountNo;
-(void) deleteShareSheetPayloadWithId:(NSNumber*) payloadId;

@end

NS_ASSUME_NONNULL_END
