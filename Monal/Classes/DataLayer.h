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
#import "MLContactSoftwareVersionInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface DataLayer : NSObject

extern NSString* const kAccountID;
extern NSString* const kAccountState;
extern NSString* const kDomain;
extern NSString* const kEnabled;
extern NSString* const kNeedsPasswordMigration;
extern NSString* const kSupportsSasl2;

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
-(NSString *) getRosterVersionForAccount:(NSNumber*) accountNo;
-(void) setRosterVersion:(NSString *) version forAccount: (NSNumber*) accountNo;

// Buddy Commands
-(BOOL) addContact:(NSString*) contact  forAccount:(NSNumber*) accountNo nickname:(NSString* _Nullable) nickName;
-(void) removeBuddy:(NSString*) buddy forAccount:(NSNumber*) accountNo;
-(BOOL) clearBuddies:(NSNumber*) accountNo;
-(NSDictionary* _Nullable) contactDictionaryForUsername:(NSString*) username forAccount: (NSNumber*) accountNo;

/**
 should be called when a new session needs to be established
 */
-(BOOL) resetContactsForAccount:(NSNumber*) accountNo;

-(NSMutableArray<MLContact*>*) searchContactsWithString:(NSString*) search;

-(NSArray<MLContact*>*) contactList;
-(NSArray<MLContact*>*) contactListWithJid:(NSString*) jid;
-(NSArray<MLContact*>*) possibleGroupMembersForAccount:(NSNumber*) accountNo;
-(NSArray<NSString*>*) resourcesForContact:(MLContact* _Nonnull)contact ;
-(MLContactSoftwareVersionInfo* _Nullable) getSoftwareVersionInfoForContact:(NSString*)contact resource:(NSString*)resource andAccount:(NSNumber*)account;
-(void) setSoftwareVersionInfoForContact:(NSString*)contact
                                resource:(NSString*)resource
                              andAccount:(NSNumber*)account
                                withSoftwareInfo:(MLContactSoftwareVersionInfo*) newSoftwareInfo;

#pragma mark Ver string and Capabilities

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user onAccountNo:(NSNumber*) accountNo;
-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user andResource:(NSString*) resource onAccountNo:(NSNumber*) accountNo;
-(NSString*) getVerForUser:(NSString*) user andResource:(NSString*) resource onAccountNo:(NSNumber*) accountNo;
-(void) setVer:(NSString*) ver forUser:(NSString*) user andResource:(NSString*) resource onAccountNo:(NSNumber*) accountNo;
-(NSSet* _Nullable) getCapsforVer:(NSString*) ver onAccountNo:(NSNumber*) accountNo;
-(void) setCaps:(NSSet*) caps forVer:(NSString*) ver onAccountNo:(NSNumber*) accountNo;

#pragma mark  presence functions
-(void) setResourceOnline:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountNo;
-(void) setOnlineBuddy:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountNo;
-(void) setOfflineBuddy:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountNo;

-(void) setBuddyStatus:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountNo;
-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSNumber*) accountNo;

-(void) setBuddyState:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountNo;
-(NSString*) buddyState:(NSString*) buddy forAccount:(NSNumber*) accountNo;

-(BOOL) hasContactRequestForContact:(MLContact*) contact;
-(NSMutableArray*) allContactRequests;
-(void) addContactRequest:(MLContact *) requestor;
-(void) deleteContactRequest:(MLContact *) requestor; 

#pragma mark Contact info

-(void) setFullName:(NSString*) fullName forContact:(NSString*) contact andAccount:(NSNumber*) accountNo;

-(void) setAvatarHash:(NSString*) hash forContact:(NSString*) contact andAccount:(NSNumber*) accountNo;
-(NSString*) getAvatarHashForContact:(NSString*) buddy andAccount:(NSNumber*) accountNo;

-(BOOL) saveMessageDraft:(NSString*) buddy forAccount:(NSNumber*) accountNo withComment:(NSString*) comment;
-(NSString*) loadMessageDraft:(NSString*) buddy forAccount:(NSNumber*) accountNo;

#pragma mark - MUC

-(BOOL) initMuc:(NSString*) room forAccountId:(NSNumber*) accountNo andMucNick:(NSString* _Nullable) mucNick;
-(void) cleanupMembersAndParticipantsListFor:(NSString*) room forAccountId:(NSNumber*) accountNo;
-(void) addMember:(NSDictionary*) member toMuc:(NSString*) room forAccountId:(NSNumber*) accountNo;
-(void) removeMember:(NSDictionary*) member fromMuc:(NSString*) room forAccountId:(NSNumber*) accountNo;
-(void) addParticipant:(NSDictionary*) participant toMuc:(NSString*) room forAccountId:(NSNumber*) accountNo;
-(void) removeParticipant:(NSDictionary*) participant fromMuc:(NSString*) room forAccountId:(NSNumber*) accountNo;
-(NSDictionary* _Nullable) getParticipantForNick:(NSString*) nick inRoom:(NSString*) room forAccountId:(NSNumber*) accountNo;
-(NSArray<NSDictionary<NSString*, id>*>*) getMembersAndParticipantsOfMuc:(NSString*) room forAccountId:(NSNumber*) accountNo;
-(NSString* _Nullable) getOwnAffiliationInGroupOrChannel:(MLContact*) contact;
-(NSString* _Nullable) getOwnRoleInGroupOrChannel:(MLContact*) contact;
-(void) addMucFavorite:(NSString*) room forAccountId:(NSNumber*) accountNo andMucNick:(NSString* _Nullable) mucNick;
-(NSString*) lastStanzaIdForMuc:(NSString* _Nonnull) room andAccount:(NSNumber* _Nonnull) accountNo;
-(void) setLastStanzaId:(NSString*) lastStanzaId forMuc:(NSString* _Nonnull) room andAccount:(NSNumber* _Nonnull) accountNo;
-(BOOL) isBuddyMuc:(NSString*) buddy forAccount:(NSNumber*) accountNo;

-(NSString* _Nullable) ownNickNameforMuc:(NSString*) room forAccount:(NSNumber*) accountNo;
-(BOOL) updateOwnNickName:(NSString*) nick forMuc:(NSString*) room forAccount:(NSNumber*) accountNo;

-(BOOL) updateMucSubject:(NSString*) subject forAccount:(NSNumber*) accountNo andRoom:(NSString*) room;
-(NSString*) mucSubjectforAccount:(NSNumber*) accountNo andRoom:(NSString*) room;

-(NSSet*) listMucsForAccount:(NSNumber*) accountNo;
-(BOOL) deleteMuc:(NSString*) room forAccountId:(NSNumber*) accountNo;

-(void) updateMucTypeTo:(NSString*) type forRoom:(NSString*) room andAccount:(NSNumber*) accountNo;
-(NSString*) getMucTypeOfRoom:(NSString*) room andAccount:(NSNumber*) accountNo;

/**
 Calls with YES if contact  has already been added to the database for this account
 */
-(BOOL) isContactInList:(NSString*) buddy forAccount:(NSNumber*) accountNo;

#pragma mark - account commands
-(NSArray*) accountList;
-(NSNumber*) enabledAccountCnts;
-(NSArray*) enabledAccountList;
-(BOOL) isAccountEnabled:(NSNumber*) accountNo;
-(BOOL) doesAccountExistUser:(NSString*) user andDomain:(NSString *) domain;
-(NSNumber* _Nullable) accountIDForUser:(NSString*) user andDomain:(NSString *) domain;

-(NSMutableDictionary* _Nullable) detailsForAccount:(NSNumber*) accountNo;

-(BOOL) updateAccounWithDictionary:(NSDictionary *) dictionary;
-(NSNumber* _Nullable) addAccountWithDictionary:(NSDictionary *) dictionary;


-(BOOL) removeAccount:(NSNumber*) accountNo;

/**
 password migration
 */
-(BOOL) disableAccountForPasswordMigration:(NSNumber*) accountNo;
-(NSArray*) accountListNeedingPasswordMigration;

-(BOOL) pinSasl2ForAccount:(NSNumber*) accountNo;
-(BOOL) isSasl2PinnedForAccount:(NSNumber*) accountNo;

-(NSMutableDictionary* _Nullable) readStateForAccount:(NSNumber*) accountNo;
-(void) persistState:(NSDictionary*) state forAccount:(NSNumber*) accountNo;

#pragma mark - message Commands
/**
 returns messages with the provided local id number
 */
-(NSArray<MLMessage*>*) messagesForHistoryIDs:(NSArray<NSNumber*>*) historyIDs;
-(MLMessage* _Nullable) messageForHistoryID:(NSNumber* _Nullable) historyID;
-(NSNumber*) getSmallestHistoryId;
-(NSNumber*) getBiggestHistoryId;

/*
 adds a specified message to the database
 */
-(NSNumber*) addMessageToChatBuddy:(NSString*) buddyName withInboundDir:(BOOL) inbound forAccount:(NSNumber*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom participantJid:(NSString*_Nullable) participantJid sent:(BOOL) sent unread:(BOOL) unread messageId:(NSString*) messageid serverMessageId:(NSString*) stanzaid messageType:(NSString*) messageType andOverrideDate:(NSDate*) messageDate encrypted:(BOOL) encrypted displayMarkerWanted:(BOOL) displayMarkerWanted usingHistoryId:(NSNumber* _Nullable) historyId checkForDuplicates:(BOOL) checkForDuplicates;

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
-(void) clearErrorOfMessageId:(NSString* _Nonnull) messageid;

/**
 sets a preview info for a specified message
 */
-(void) setMessageId:(NSString*_Nonnull) messageid previewText:(NSString *) text andPreviewImage:(NSString *) image;

-(void) setMessageId:(NSString*) messageid stanzaId:(NSString *) stanzaId;
-(void) setMessageHistoryId:(NSNumber*) historyId filetransferMimeType:(NSString*) mimeType filetransferSize:(NSNumber*) size;
-(void) setMessageHistoryId:(NSNumber*) historyId messageType:(NSString*) messageType;

-(void) clearMessages:(NSNumber*) accountNo;
-(void) clearMessagesWithBuddy:(NSString*) buddy onAccount:(NSNumber*) accountNo;
-(void) autodeleteAllMessagesAfter3Days;
-(void) deleteMessageHistory:(NSNumber *) messageNo;
-(void) deleteMessageHistoryLocally:(NSNumber*) messageNo;
-(void) updateMessageHistory:(NSNumber*) messageNo withText:(NSString*) newText;
-(NSNumber* _Nullable) getHistoryIDForMessageId:(NSString*) messageid from:(NSString*) from actualFrom:(NSString* _Nullable) actualFrom participantJid:(NSString* _Nullable) participantJid andAccount:(NSNumber*) accountNo;

-(NSDate* _Nullable) returnTimestampForQuote:(NSNumber*) historyID;
-(BOOL) checkLMCEligible:(NSNumber*) historyID encrypted:(BOOL) encrypted historyBaseID:(NSNumber* _Nullable) historyBaseID;

#pragma mark - message history

-(NSNumber*) lastMessageHistoryIdForContact:(NSString*) buddy forAccount:(NSNumber*) accountNo;
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSNumber*) accountNo beforeMsgHistoryID:(NSNumber* _Nullable) msgHistoryID;
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSNumber*) accountNo;


-(MLMessage*) lastMessageForContact:(NSString*) contact forAccount:(NSNumber*) accountNo;
-(NSString*) lastStanzaIdForAccount:(NSNumber*) accountNo;
-(void) setLastStanzaId:(NSString*) lastStanzaId forAccount:(NSNumber*) accountNo;

-(NSArray<MLMessage*>*) markMessagesAsReadForBuddy:(NSString*) buddy andAccount:(NSNumber*) accountNo tillStanzaId:(NSString* _Nullable) stanzaId wasOutgoing:(BOOL) outgoing;

-(NSNumber*) addMessageHistoryTo:(NSString*) to forAccount:(NSNumber*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString*) messageId encrypted:(BOOL) encrypted messageType:(NSString*) messageType mimeType:(NSString* _Nullable) mimeType size:(NSNumber* _Nullable) size;

#pragma mark active contacts
-(NSMutableArray<MLContact*>*) activeContactsWithPinned:(BOOL) pinned;
-(NSArray<MLContact*>*) activeContactDict;
-(void) removeActiveBuddy:(NSString*) buddyname forAccount:(NSNumber*) accountNo;
-(void) addActiveBuddies:(NSString*) buddyname forAccount:(NSNumber*) accountNo;
-(BOOL) isActiveBuddy:(NSString*) buddyname forAccount:(NSNumber*) accountNo;
-(BOOL) updateActiveBuddy:(NSString*) buddyname setTime:(NSString*)timestamp forAccount:(NSNumber*) accountNo;



#pragma mark count unread
-(NSNumber*) countUserUnreadMessages:(NSString* _Nullable) buddy forAccount:(NSNumber* _Nullable) accountNo;
-(NSNumber*) countUnreadMessages;

-(void) muteContact:(MLContact*) contact;
-(void) unMuteContact:(MLContact*) contact;
-(BOOL) isMutedJid:(NSString*) jid onAccount:(NSNumber*) accountNo;

-(void) setMucAlertOnMentionOnly:(NSString*) jid onAccount:(NSNumber*) accountNo;
-(void) setMucAlertOnAll:(NSString*) jid onAccount:(NSNumber*) accountNo;
-(BOOL) isMucAlertOnMentionOnly:(NSString*) jid onAccount:(NSNumber*) accountNo;

-(void) blockJid:(NSString *) jid withAccountNo:(NSNumber*) accountNo;
-(void) unBlockJid:(NSString *) jid withAccountNo:(NSNumber*) accountNo;
-(uint8_t) isBlockedContact:(MLContact*) contact;
-(void) updateLocalBlocklistCache:(NSSet<NSString*>*) blockedJids forAccountNo:(NSNumber*) accountNo;
-(NSArray<NSDictionary<NSString*, NSString*>*>*) blockedJidsForAccount:(NSNumber*) accountNo;

-(BOOL) isPinnedChat:(NSNumber*) accountNo andBuddyJid:(NSString*) buddyJid;
-(void) pinChat:(NSNumber*) accountNo andBuddyJid:(NSString*) buddyJid;
-(void) unPinChat:(NSNumber*) accountNo andBuddyJid:(NSString*) buddyJid;

-(BOOL) shouldEncryptForJid:(NSString *) jid andAccountNo:(NSNumber*) account;
-(void) encryptForJid:(NSString*) jid andAccountNo:(NSNumber*) accountNo;
-(void) disableEncryptForJid:(NSString*) jid andAccountNo:(NSNumber*) accountNo;

-(NSMutableArray*) allAttachmentsFromContact:(NSString*) contact forAccount:(NSNumber*) accountNo;

-(NSDate* _Nullable) lastInteractionOfJid:(NSString* _Nonnull) jid forAccountNo:(NSNumber* _Nonnull) accountNo;
-(NSDate* _Nullable) lastInteractionOfJid:(NSString* _Nonnull) jid andResource:(NSString* _Nonnull) resource forAccountNo:(NSNumber* _Nonnull) accountNo;
-(void) setLastInteraction:(NSDate*) lastInteractionTime forJid:(NSString* _Nonnull) jid andResource:(NSString*) resource onAccountNo:(NSNumber* _Nonnull) accountNo;

-(NSDictionary *) getSubscriptionForContact:(NSString*) contact andAccount:(NSNumber*) accountNo;
-(void) setSubscription:(NSString *)sub andAsk:(NSString*) ask forContact:(NSString*) contact andAccount:(NSNumber*) accountNo;

#pragma mark History Message Search
/*
 search message by keyword in message, buddy_name, messageType.
 */
-(NSArray* _Nullable) searchResultOfHistoryMessageWithKeyWords:(NSString* _Nonnull) keyword
                                             accountNo:(NSNumber*  _Nonnull) accountNo;

/*
 search message by keyword in message, buddy_name, messageType.
 */
-(NSArray*) searchResultOfHistoryMessageWithKeyWords:(NSString*) keyword betweenContact:(MLContact* _Nonnull) contact;

-(NSArray<NSDictionary*>*) getAllCachedImages;
-(void) removeImageCacheTables;
-(NSArray*) getAllMessagesForFiletransferUrl:(NSString*) url;
-(void) upgradeImageMessagesToFiletransferMessages;

-(void) invalidateAllAccountStates;

-(NSString*) lastUsedPushServerForAccount:(NSNumber*) accountNo;
-(void) updateUsedPushServer:(NSString*) pushServer forAccount:(NSNumber*) accountNo;



-(void) deleteDelayedMessageStanzasForAccount:(NSNumber*) accountNo;
-(void) addDelayedMessageStanza:(MLXMLNode*) stanza forArchiveJid:(NSString*) archiveJid andAccountNo:(NSNumber*) accountNo;
-(MLXMLNode* _Nullable) getNextDelayedMessageStanzaForArchiveJid:(NSString*) archiveJid andAccountNo:(NSNumber*) accountNo;

-(void) addShareSheetPayload:(NSDictionary*) payload;
-(NSArray*) getShareSheetPayload;
-(void) deleteShareSheetPayloadWithId:(NSNumber*) payloadId;

-(NSNumber*) addIdleTimerWithTimeout:(NSNumber*) timeout andHandler:(MLHandler*) handler onAccountNo:(NSNumber*) accountNo;
-(void) delIdleTimerWithId:(NSNumber* _Nullable) timerId;
-(void) cleanupIdleTimerOnAccountNo:(NSNumber*) accountNo;
-(void) decrementIdleTimersForAccount:(xmpp*) account;

@end

NS_ASSUME_NONNULL_END
