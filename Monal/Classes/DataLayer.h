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
extern NSString* const kPlainActivated;

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
-(void) vacuum;

//Roster
-(NSString *) getRosterVersionForAccount:(NSNumber*) accountID;
-(void) setRosterVersion:(NSString *) version forAccount: (NSNumber*) accountID;

// Buddy Commands
-(BOOL) addContact:(NSString*) contact  forAccount:(NSNumber*) accountID nickname:(NSString* _Nullable) nickName;
-(void) removeBuddy:(NSString*) buddy forAccount:(NSNumber*) accountID;
-(BOOL) clearBuddies:(NSNumber*) accountID;
-(NSDictionary* _Nullable) contactDictionaryForUsername:(NSString*) username forAccount: (NSNumber*) accountID;

/**
 should be called when a new session needs to be established
 */
-(BOOL) resetContactsForAccount:(NSNumber*) accountID;

-(NSMutableArray<MLContact*>*) searchContactsWithString:(NSString*) search;

-(NSArray<MLContact*>*) contactList;
-(NSArray<MLContact*>*) contactListWithJid:(NSString*) jid;
-(NSArray<MLContact*>*) possibleGroupMembersForAccount:(NSNumber*) accountID;
-(NSArray<NSString*>*) resourcesForContact:(MLContact* _Nonnull)contact ;
-(MLContactSoftwareVersionInfo* _Nullable) getSoftwareVersionInfoForContact:(NSString*)contact resource:(NSString*)resource andAccount:(NSNumber*)account;
-(void) setSoftwareVersionInfoForContact:(NSString*)contact
                                resource:(NSString*)resource
                              andAccount:(NSNumber*)account
                                withSoftwareInfo:(MLContactSoftwareVersionInfo*) newSoftwareInfo;

#pragma mark Ver string and Capabilities

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user onAccountID:(NSNumber*) accountID;
-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user andResource:(NSString*) resource onAccountID:(NSNumber*) accountID;
-(NSString*) getVerForUser:(NSString*) user andResource:(NSString*) resource onAccountID:(NSNumber*) accountID;
-(void) setVer:(NSString*) ver forUser:(NSString*) user andResource:(NSString*) resource onAccountID:(NSNumber*) accountID;
-(NSSet* _Nullable) getCapsforVer:(NSString*) ver onAccountID:(NSNumber*) accountID;
-(void) setCaps:(NSSet*) caps forVer:(NSString*) ver onAccountID:(NSNumber*) accountID;

#pragma mark  presence functions
-(void) setResourceOnline:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountID;
-(void) setOnlineBuddy:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountID;
-(void) setOfflineBuddy:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountID;

-(void) setBuddyStatus:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountID;
-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSNumber*) accountID;

-(void) setBuddyState:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountID;
-(NSString*) buddyState:(NSString*) buddy forAccount:(NSNumber*) accountID;

-(BOOL) hasContactRequestForContact:(MLContact*) contact;
-(NSMutableArray*) allContactRequests;
-(void) addContactRequest:(MLContact *) requestor;
-(void) deleteContactRequest:(MLContact *) requestor; 

#pragma mark Contact info

-(void) setFullName:(NSString*) fullName forContact:(NSString*) contact andAccount:(NSNumber*) accountID;

-(void) setAvatarHash:(NSString*) hash forContact:(NSString*) contact andAccount:(NSNumber*) accountID;
-(NSString*) getAvatarHashForContact:(NSString*) buddy andAccount:(NSNumber*) accountID;

-(BOOL) saveMessageDraft:(NSString*) buddy forAccount:(NSNumber*) accountID withComment:(NSString*) comment;
-(NSString*) loadMessageDraft:(NSString*) buddy forAccount:(NSNumber*) accountID;

#pragma mark - MUC

-(BOOL) initMuc:(NSString*) room forAccountID:(NSNumber*) accountID andMucNick:(NSString* _Nullable) mucNick;
-(void) cleanupParticipantsListFor:(NSString*) room onAccountID:(NSNumber*) accountID;
-(void) cleanupMembersListFor:(NSString*) room andType:(NSString*) type onAccountID:(NSNumber*) accountID;
-(void) addMember:(NSDictionary*) member toMuc:(NSString*) room forAccountID:(NSNumber*) accountID;
-(void) removeMember:(NSDictionary*) member fromMuc:(NSString*) room forAccountID:(NSNumber*) accountID;
-(void) addParticipant:(NSDictionary*) participant toMuc:(NSString*) room forAccountID:(NSNumber*) accountID;
-(void) removeParticipant:(NSDictionary*) participant fromMuc:(NSString*) room forAccountID:(NSNumber*) accountID;
-(NSDictionary* _Nullable) getParticipantForNick:(NSString*) nick inRoom:(NSString*) room forAccountID:(NSNumber*) accountID;
-(NSDictionary* _Nullable) getParticipantForOccupant:(NSString*) occupant inRoom:(NSString*) room forAccountID:(NSNumber*) accountID;
-(NSArray<NSDictionary<NSString*, id>*>*) getMembersAndParticipantsOfMuc:(NSString*) room forAccountID:(NSNumber*) accountID;
-(NSString* _Nullable) getOwnAffiliationInGroupOrChannel:(MLContact*) contact;
-(NSString* _Nullable) getOwnRoleInGroupOrChannel:(MLContact*) contact;
-(void) addMucFavorite:(NSString*) room forAccountID:(NSNumber*) accountID andMucNick:(NSString* _Nullable) mucNick;
-(NSString*) lastStanzaIdForMuc:(NSString* _Nonnull) room andAccount:(NSNumber* _Nonnull) accountID;
-(void) setLastStanzaId:(NSString*) lastStanzaId forMuc:(NSString* _Nonnull) room andAccount:(NSNumber* _Nonnull) accountID;
-(BOOL) isBuddyMuc:(NSString*) buddy forAccount:(NSNumber*) accountID;

-(NSString* _Nullable) ownNickNameforMuc:(NSString*) room forAccount:(NSNumber*) accountID;
-(BOOL) updateOwnNickName:(NSString*) nick forMuc:(NSString*) room forAccount:(NSNumber*) accountID;

-(BOOL) updateOwnOccupantID:(NSString* _Nullable) occupantID forMuc:(NSString*) room onAccountID:(NSNumber*) accountID;
-(NSString* _Nullable) getOwnOccupantIdForMuc:(NSString*) room onAccountID:(NSNumber*) accountID;

-(BOOL) updateMucSubject:(NSString*) subject forAccount:(NSNumber*) accountID andRoom:(NSString*) room;
-(NSString*) mucSubjectforAccount:(NSNumber*) accountID andRoom:(NSString*) room;

-(NSSet*) listMucsForAccount:(NSNumber*) accountID;
-(BOOL) deleteMuc:(NSString*) room forAccountID:(NSNumber*) accountID;

-(void) updateMucTypeTo:(NSString*) type forRoom:(NSString*) room andAccount:(NSNumber*) accountID;
-(NSString*) getMucTypeOfRoom:(NSString*) room andAccount:(NSNumber*) accountID;

/**
 Calls with YES if contact  has already been added to the database for this account
 */
-(BOOL) isContactInList:(NSString*) buddy forAccount:(NSNumber*) accountID;

#pragma mark - account commands
-(NSArray*) accountList;
-(NSNumber*) enabledAccountCnts;
-(NSArray*) enabledAccountList;
-(BOOL) isAccountEnabled:(NSNumber*) accountID;
-(BOOL) doesAccountExistUser:(NSString*) user andDomain:(NSString *) domain;
-(NSNumber* _Nullable) accountIDForUser:(NSString*) user andDomain:(NSString *) domain;

-(NSMutableDictionary* _Nullable) detailsForAccount:(NSNumber*) accountID;

-(BOOL) updateAccounWithDictionary:(NSDictionary *) dictionary;
-(NSNumber* _Nullable) addAccountWithDictionary:(NSDictionary *) dictionary;


-(BOOL) removeAccount:(NSNumber*) accountID;

/**
 password migration
 */
-(BOOL) disableAccountForPasswordMigration:(NSNumber*) accountID;
-(NSArray*) accountListNeedingPasswordMigration;

-(BOOL) isPlainActivatedForAccount:(NSNumber*) accountID;
-(BOOL) deactivatePlainForAccount:(NSNumber*) accountID;

-(NSMutableDictionary* _Nullable) readStateForAccount:(NSNumber*) accountID;
-(void) persistState:(NSDictionary*) state forAccount:(NSNumber*) accountID;

#pragma mark - message Commands
/**
 returns messages with the provided local id number
 */
-(NSArray<MLMessage*>*) messagesForHistoryIDs:(NSArray<NSNumber*>*) historyIDs;
-(MLMessage* _Nullable) messageForHistoryID:(NSNumber* _Nullable) historyID;
-(NSNumber*) getSmallestHistoryId;
-(NSNumber*) getBiggestHistoryId;

-(NSNumber* _Nullable) hasMessageForStanzaId:(NSString*) stanzaId orMessageID:(NSString*) messageId withInboundDir:(BOOL) inbound occupantId:(NSString* _Nullable) occupantId andJid:(NSString*) jid onAccount:(NSNumber*) accountID;

/*
 adds a specified message to the database
 */
-(NSNumber*) addMessageToChatBuddy:(NSString*) buddyName withInboundDir:(BOOL) inbound forAccount:(NSNumber*) accountID withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom occupantId:(NSString* _Nullable) occupantId participantJid:(NSString*_Nullable) participantJid sent:(BOOL) sent unread:(BOOL) unread messageId:(NSString*) messageid serverMessageId:(NSString*) stanzaid messageType:(NSString*) messageType andOverrideDate:(NSDate*) messageDate encrypted:(BOOL) encrypted displayMarkerWanted:(BOOL) displayMarkerWanted usingHistoryId:(NSNumber* _Nullable) historyId checkForDuplicates:(BOOL) checkForDuplicates;

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

-(void) clearMessages:(NSNumber*) accountID;
-(void) clearMessagesWithBuddy:(NSString*) buddy onAccount:(NSNumber*) accountID;
-(NSNumber*) autoDeleteMessagesAfterInterval:(NSTimeInterval)interval;
-(void) retractMessageHistory:(NSNumber *) messageNo;
-(void) deleteMessageHistoryLocally:(NSNumber*) messageNo;
-(void) updateMessageHistory:(NSNumber*) messageNo withText:(NSString*) newText;
-(NSNumber* _Nullable) getLMCHistoryIDForMessageId:(NSString*) messageid from:(NSString*) from occupantId:(NSString* _Nullable) occupantId participantJid:(NSString* _Nullable) participantJid andAccount:(NSNumber*) accountID;
-(NSNumber* _Nullable) getRetractionHistoryIDForMessageId:(NSString*) messageid from:(NSString*) from participantJid:(NSString* _Nullable) participantJid occupantId:(NSString* _Nullable) occupantId andAccount:(NSNumber*) accountID;
-(NSNumber* _Nullable) getRetractionHistoryIDForModeratedStanzaId:(NSString*) stanzaId from:(NSString*) from andAccount:(NSNumber*) accountID;

-(NSDate* _Nullable) returnTimestampForQuote:(NSNumber*) historyID;
-(BOOL) checkLMCEligible:(NSNumber*) historyID encrypted:(BOOL) encrypted historyBaseID:(NSNumber* _Nullable) historyBaseID;

#pragma mark - message history

-(NSNumber*) lastMessageHistoryIdForContact:(NSString*) buddy forAccount:(NSNumber*) accountID;
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSNumber*) accountID beforeMsgHistoryID:(NSNumber* _Nullable) msgHistoryID;
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSNumber*) accountID;


-(MLMessage*) lastMessageForContact:(NSString*) contact forAccount:(NSNumber*) accountID;
-(NSString*) lastStanzaIdForAccount:(NSNumber*) accountID;
-(void) setLastStanzaId:(NSString*) lastStanzaId forAccount:(NSNumber*) accountID;

-(NSArray<MLMessage*>*) markMessagesAsReadForBuddy:(NSString*) buddy andAccount:(NSNumber*) accountID tillStanzaId:(NSString* _Nullable) stanzaId wasOutgoing:(BOOL) outgoing;

-(NSNumber*) addMessageHistoryTo:(NSString*) to forAccount:(NSNumber*) accountID withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString*) messageId encrypted:(BOOL) encrypted messageType:(NSString*) messageType mimeType:(NSString* _Nullable) mimeType size:(NSNumber* _Nullable) size;

#pragma mark active contacts
-(NSMutableArray<MLContact*>*) activeContactsWithPinned:(BOOL) pinned;
-(NSArray<MLContact*>*) activeContactDict;
-(void) removeActiveBuddy:(NSString*) buddyname forAccount:(NSNumber*) accountID;
-(void) addActiveBuddies:(NSString*) buddyname forAccount:(NSNumber*) accountID;
-(BOOL) isActiveBuddy:(NSString*) buddyname forAccount:(NSNumber*) accountID;
-(BOOL) updateActiveBuddy:(NSString*) buddyname setTime:(NSString*)timestamp forAccount:(NSNumber*) accountID;



#pragma mark count unread
-(NSNumber*) countUserUnreadMessages:(NSString* _Nullable) buddy forAccount:(NSNumber* _Nullable) accountID;
-(NSNumber*) countUnreadMessages;

-(void) muteContact:(MLContact*) contact;
-(void) unMuteContact:(MLContact*) contact;
-(BOOL) isMutedJid:(NSString*) jid onAccount:(NSNumber*) accountID;

-(void) setMucAlertOnMentionOnly:(NSString*) jid onAccount:(NSNumber*) accountID;
-(void) setMucAlertOnAll:(NSString*) jid onAccount:(NSNumber*) accountID;
-(BOOL) isMucAlertOnMentionOnly:(NSString*) jid onAccount:(NSNumber*) accountID;

-(void) blockJid:(NSString *) jid withAccountID:(NSNumber*) accountID;
-(void) unBlockJid:(NSString *) jid withAccountID:(NSNumber*) accountID;
-(uint8_t) isBlockedContact:(MLContact*) contact;
-(void) updateLocalBlocklistCache:(NSSet<NSString*>*) blockedJids forAccountID:(NSNumber*) accountID;
-(NSArray<NSDictionary<NSString*, NSString*>*>*) blockedJidsForAccount:(NSNumber*) accountID;

-(BOOL) isPinnedChat:(NSNumber*) accountID andBuddyJid:(NSString*) buddyJid;
-(void) pinChat:(NSNumber*) accountID andBuddyJid:(NSString*) buddyJid;
-(void) unPinChat:(NSNumber*) accountID andBuddyJid:(NSString*) buddyJid;

-(BOOL) shouldEncryptForJid:(NSString *) jid andAccountID:(NSNumber*) account;
-(void) encryptForJid:(NSString*) jid andAccountID:(NSNumber*) accountID;
-(void) disableEncryptForJid:(NSString*) jid andAccountID:(NSNumber*) accountID;

-(NSMutableArray*) allAttachmentsFromContact:(NSString*) contact forAccount:(NSNumber*) accountID;

-(NSDate* _Nullable) lastInteractionOfJid:(NSString* _Nonnull) jid forAccountID:(NSNumber* _Nonnull) accountID;
-(NSDate* _Nullable) lastInteractionOfJid:(NSString* _Nonnull) jid andResource:(NSString* _Nonnull) resource forAccountID:(NSNumber* _Nonnull) accountID;
-(void) setLastInteraction:(NSDate*) lastInteractionTime forJid:(NSString* _Nonnull) jid andResource:(NSString*) resource onAccountID:(NSNumber* _Nonnull) accountID;

-(NSDictionary *) getSubscriptionForContact:(NSString*) contact andAccount:(NSNumber*) accountID;
-(void) setSubscription:(NSString *)sub andAsk:(NSString*) ask forContact:(NSString*) contact andAccount:(NSNumber*) accountID;
-(void) setGroups:(NSSet*) groups forContact:(NSString*) contact inAccount:(NSNumber*) accountID;

#pragma mark History Message Search
/*
 search message by keyword in message, buddy_name, messageType.
 */
-(NSArray* _Nullable) searchResultOfHistoryMessageWithKeyWords:(NSString* _Nonnull) keyword
                                             accountID:(NSNumber*  _Nonnull) accountID;

/*
 search message by keyword in message, buddy_name, messageType.
 */
-(NSArray*) searchResultOfHistoryMessageWithKeyWords:(NSString*) keyword betweenContact:(MLContact* _Nonnull) contact;

-(NSArray<NSDictionary*>*) getAllCachedImages;
-(void) removeImageCacheTables;
-(NSArray*) getAllMessagesForFiletransferUrl:(NSString*) url;
-(void) upgradeImageMessagesToFiletransferMessages;

-(void) invalidateAllAccountStates;

-(NSString*) lastUsedPushServerForAccount:(NSNumber*) accountID;
-(void) updateUsedPushServer:(NSString*) pushServer forAccount:(NSNumber*) accountID;



-(void) deleteDelayedMessageStanzasForAccount:(NSNumber*) accountID;
-(void) addDelayedMessageStanza:(MLXMLNode*) stanza forArchiveJid:(NSString*) archiveJid andAccountID:(NSNumber*) accountID;
-(MLXMLNode* _Nullable) getNextDelayedMessageStanzaForArchiveJid:(NSString*) archiveJid andAccountID:(NSNumber*) accountID;

-(void) addShareSheetPayload:(NSDictionary*) payload;
-(NSArray*) getShareSheetPayload;
-(void) deleteShareSheetPayloadWithId:(NSNumber*) payloadId;

-(NSNumber*) addIdleTimerWithTimeout:(NSNumber*) timeout andHandler:(MLHandler*) handler onAccountID:(NSNumber*) accountID;
-(void) delIdleTimerWithId:(NSNumber* _Nullable) timerId;
-(void) cleanupIdleTimerOnAccountID:(NSNumber*) accountID;
-(void) decrementIdleTimersForAccount:(xmpp*) account;

@end

NS_ASSUME_NONNULL_END
