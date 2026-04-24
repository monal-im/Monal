//
//  MLNotificationManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/20/13.
//
//

#import <monalxmpp/HelperTools.h>
#import "MLNotificationManager.h"
#import <monalxmpp/MLImageManager.h>
#import <monalxmpp/MLMessage.h>
#import <monalxmpp/MLContact.h>
#import <monalxmpp/MLChannelContact.h>
#import <monalxmpp/MLReactionsEntry.h>
#import "MLXEPSlashMeHandler.h"
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/xmpp.h>
#import <monalxmpp/MLFileTransfer.h>
#import <monalxmpp/MLFileTransferInfo.h>
#import <monalxmpp/MLNotificationQueue.h>
#import <monalxmpp/MLXMPPManager.h>
#import <monalxmpp/monalxmpp-Swift.h>

@import UserNotifications;
@import CoreServices;
@import Intents;
@import AVFoundation;
@import UniformTypeIdentifiers;

typedef NS_ENUM(NSUInteger, MLNotificationState) {
    MLNotificationStateNone,
    MLNotificationStatePending,
    MLNotificationStateDelivered,
};

@interface MLNotificationManager ()
@property (nonatomic, readonly) NotificationPrivacySettingOption notificationPrivacySetting;
@end

@implementation MLNotificationManager

+(MLNotificationManager*) sharedInstance
{
    static dispatch_once_t once;
    static MLNotificationManager* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [MLNotificationManager new] ;
    });
    return sharedInstance;
}

-(id) init
{
    self = [super init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalUpdatedMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleFiletransferUpdate:) name:kMonalMessageFiletransferUpdateNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleDeletedMessage:) name:kMonalDeletedMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleDisplayedMessages:) name:kMonalDisplayedMessagesNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleXMPPError:) name:kXMPPError object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleContactRefresh:) name:kMonalContactRefresh object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleContactRefresh:) name:kMonalContactRemoved object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOwnRoleOrAffiliationChange:) name:kMonalMucOwnAffiliationOrRoleChanged object:nil];
    return self;
}

-(NotificationPrivacySettingOption) notificationPrivacySetting
{
    NotificationPrivacySettingOption value = (NotificationPrivacySettingOption)[[HelperTools defaultsDB] integerForKey:@"NotificationPrivacySetting"];
    DDLogVerbose(@"Current NotificationPrivacySettingOption: %d", (int)value);
    return value;
}

-(void) handleOwnRoleOrAffiliationChange:(NSNotification*) notification
{
    MLContact* contact = notification.userInfo[@"contact"];
    NSString* oldRole = nilExtractor(notification.userInfo[@"oldRole"]);
    NSString* newRole = nilExtractor(notification.userInfo[@"newRole"]);
    
    //show notification if we were granted voice in a moderated channel
    if(newRole != nil && oldRole != nil && ![newRole isEqualToString:oldRole] && [kMucRoleVisitor isEqualToString:oldRole])
    {
        NSString* idval = [NSString stringWithFormat:@"roleChange(%@, %@)", contact.accountID, contact.contactJid];
        
        UNMutableNotificationContent* content = [UNMutableNotificationContent new];
        content.title = contact.contactDisplayName;
        content.body = NSLocalizedString(@"You were granted voice in this channel.", @"");
        content.threadIdentifier = [self threadIdentifierWithContact:contact];
        content.categoryIdentifier = @"somethingRegardingAContact";
        content.userInfo = @{@"contact": [HelperTools serializeObject:contact]};
        
        DDLogDebug(@"Publishing notification with id %@", idval);
        [self publishNotificationContent:content withID:idval];
    }
}

-(void) handleContactRefresh:(NSNotification*) notification
{
    //these will not survive process switches, but that's enough for now
    static NSMutableSet* displayed;
    static NSMutableSet* removed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        displayed = [NSMutableSet new];
        removed = [NSMutableSet new];
    });
    xmpp* xmppAccount = notification.object;
    MLContact* contact = notification.userInfo[@"contact"];
    NSString* idval = [NSString stringWithFormat:@"subscription(%@, %@)", contact.accountID, contact.contactJid];
    
    //contact request denial or unsubscribe
    if(notification.userInfo[@"unsubscribed"] != nil && [notification.userInfo[@"unsubscribed"] boolValue] == YES)
    {
        idval = [NSString stringWithFormat:@"unsubscription(%@, %@)", contact.accountID, contact.contactJid];
        
        //unsubscribe
        if(contact.isSubscribedTo)
        {
            UNMutableNotificationContent* content = [UNMutableNotificationContent new];
            content.title = xmppAccount.connectionProperties.identity.jid;
            content.body = [NSString stringWithFormat:NSLocalizedString(@"The user %@ (%@) removed you from their contact list. You can send out a new contact request, if you think this was a mistake.", @""), contact.contactDisplayName, contact.contactJid];
            content.threadIdentifier = [self threadIdentifierWithContact:contact];
            content.categoryIdentifier = @"somethingRegardingAContact";
            content.userInfo = @{@"contact": [HelperTools serializeObject:contact]};
            
            DDLogDebug(@"Publishing notification with id %@", idval);
            [self publishNotificationContent:content withID:idval];
        }
        //contact request denial
        else
        {
            UNMutableNotificationContent* content = [UNMutableNotificationContent new];
            content.title = xmppAccount.connectionProperties.identity.jid;
            content.body = [NSString stringWithFormat:NSLocalizedString(@"The user %@ (%@) denied your contact request. You can try again, if you think this was a mistake.", @""), contact.contactDisplayName, contact.contactJid];
            content.threadIdentifier = [self threadIdentifierWithContact:contact];
            content.categoryIdentifier = @"somethingRegardingAContact";
            content.userInfo = @{@"contact": [HelperTools serializeObject:contact]};
            
            DDLogDebug(@"Publishing notification with id %@", idval);
            [self publishNotificationContent:content withID:idval];
        }
        return;
    }
    
    //remove contact requests notification once the contact request has been accepted
    if(!contact.hasIncomingContactRequest)
    {
        monal_void_block_t block = ^{
            [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray* requests) {
                for(UNNotificationRequest* request in requests)
                    if([request.identifier isEqualToString:idval])
                    {
                        DDLogVerbose(@"Removing pending handled subscription request notification with identifier '%@'...", idval);
                        [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[idval]];
                    }
            }];
            [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray* notifications) {
                for(UNNotification* notification in notifications)
                    if([notification.request.identifier isEqualToString:idval])
                    {
                        DDLogVerbose(@"Removing delivered handled subscription request notification with identifier '%@'...", idval);
                        [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[idval]];
                    }
            }];
            @synchronized(removed) {
                [removed addObject:idval];
            }
        };
        
        //only try to remove once
        BOOL isContained = NO;
        @synchronized(removed) {
            isContained = [removed containsObject:idval];
        }
        if(!isContained)
        {
            //do this in its own thread because we don't want to block the main thread or other threads here (the removal can take ~50ms)
            //but DON'T do this in the appex because this can try to mess with notifications after the parse queue was frozen (see appex code for explanation what this means)
            if([HelperTools isAppExtension])
                block();
            else
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), block);
        }
        
        //return because we don't want to display any contact request notification
        return;
    }
    
    //don't alert twice
    @synchronized(displayed) {
        if([displayed containsObject:idval])
            return;
    }
    
    UNMutableNotificationContent* content = [UNMutableNotificationContent new];
    content.title = xmppAccount.connectionProperties.identity.jid;
    content.body = [NSString stringWithFormat:NSLocalizedString(@"The user %@ (%@) wants to add you to their contact list", @""), contact.contactDisplayName, contact.contactJid];
    content.threadIdentifier = [self threadIdentifierWithContact:contact];
    content.categoryIdentifier = @"subscription";
    content.userInfo = @{@"contact": [HelperTools serializeObject:contact]};
    
    DDLogDebug(@"Publishing notification with id %@", idval);
    [self publishNotificationContent:content withID:idval];
    @synchronized(displayed) {
        [displayed addObject:idval];
    }
}

-(void) handleXMPPError:(NSNotification*) notification
{
    //severe errors will be shown as notification (in addition to the banner shown if the app is in foreground)
    if([notification.userInfo[@"isSevere"] boolValue])
    {
        xmpp* xmppAccount = notification.object;
        DDLogError(@"SEVERE XMPP Error(%@): %@", xmppAccount.connectionProperties.identity.jid, notification.userInfo[@"message"]);
#ifdef IS_ALPHA
        NSString* idval = [[NSUUID UUID] UUIDString];
#else
        NSString* idval = xmppAccount.connectionProperties.identity.jid;        //use this to only show the newest error notification per account
#endif
        UNMutableNotificationContent* content = [UNMutableNotificationContent new];
        content.title = xmppAccount.connectionProperties.identity.jid;
        content.body = notification.userInfo[@"message"];
        content.sound = [UNNotificationSound defaultSound];
        UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval content:content trigger:nil];
        NSError* error = [HelperTools postUserNotificationRequest:request];
        if(error)
            DDLogError(@"Error posting xmppError notification: %@", error);
    }
}

#pragma mark message signals

-(AnyPromise*) notificationStateForMessage:(MLMessage*) message
{
    NSString* idval = [self identifierWithMessage:message];
    NSMutableArray* promises = [NSMutableArray new];
    
    [promises addObject:[AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        DDLogVerbose(@"Checking for 'pending' notification state for '%@'...", idval);
        [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray* requests) {
            for(UNNotificationRequest* request in requests)
                if([request.identifier isEqualToString:idval])
                {
                    DDLogDebug(@"Notification state 'pending' for: %@", idval);
                    resolve(@(MLNotificationStatePending));
                    return;
                }
                resolve(@(MLNotificationStateNone));
        }];
    }]];
    
    [promises addObject:[AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        DDLogVerbose(@"Checking for 'delivered' notification state for '%@'...", idval);
        [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray* notifications) {
            for(UNNotification* notification in notifications)
                if([notification.request.identifier isEqualToString:idval])
                {
                    DDLogDebug(@"Notification state 'delivered' for: %@", idval);
                    resolve(@(MLNotificationStateDelivered));
                    return;
                }
                resolve(@(MLNotificationStateNone));
        }];
    }]];
    
    
    return PMKWhen(promises).then(^(NSArray* results) {
        DDLogVerbose(@"Notification state check for '%@' completed...", idval);
        for(NSNumber* entry in results)
            if(entry.integerValue != MLNotificationStateNone)
                return entry;
        return @(MLNotificationStateNone);
    });
}

-(void) handleFiletransferUpdate:(NSNotification*) notification
{
    xmpp* xmppAccount = notification.object;
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    NSString* idval = [self identifierWithMessage:message];
    //do this asynchronously on a background thread
    [self notificationStateForMessage:message].thenInBackground(^(NSNumber* _state) {
        MLNotificationState state = _state.integerValue;
        if(state == MLNotificationStatePending)
        {
            DDLogDebug(@"Already pending or unknown notification '%@', updating/posting it...", idval);
            [self internalMessageHandlerWithMessage:message andAccount:xmppAccount showAlert:YES andSound:YES andLMCReplaced:NO];
        }
        else if(state == MLNotificationStateDelivered)
        {
            DDLogDebug(@"Already displayed notification '%@', updating it...", idval);
            [self internalMessageHandlerWithMessage:message andAccount:xmppAccount showAlert:YES andSound:NO andLMCReplaced:NO];
        }
    });
}

-(void) handleNewMessage:(NSNotification*) notification
{
    xmpp* xmppAccount = notification.object;
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    BOOL showAlert = notification.userInfo[@"showAlert"] ? [notification.userInfo[@"showAlert"] boolValue] : NO;
    BOOL LMCReplaced = notification.userInfo[@"LMCReplaced"] ? [notification.userInfo[@"LMCReplaced"] boolValue] : NO;
    
    //this is either a reactions update or a new message, never both
    if([notification.userInfo[@"reactionsUpdate"] boolValue])
    {
        //only show notifications for reactions from other people to our own messages, but only if configured to do so
        //showAlert will be NO if this is our own reaction and YES it it is from somebody else
        if(!message.inbound && showAlert && [[HelperTools defaultsDB] boolForKey:@"showNotificationsForReactions"] && ([HelperTools isNotInFocus] || ![message isEqualToContact:self.currentContact]))
        {
            DDLogVerbose(@"Notification manager will show notification for reaction: %@", notification.userInfo[@"changedReactions"]);
            [self showNotificationForReactions:notification.userInfo[@"changedReactions"]];
        }
        else
            DDLogVerbose(@"Notification manager will NOT show notification for reaction: %@", notification.userInfo[@"changedReactions"]);
    }
    else
        [self internalMessageHandlerWithMessage:message andAccount:xmppAccount showAlert:showAlert andSound:YES andLMCReplaced:LMCReplaced];
}

-(void) internalMessageHandlerWithMessage:(MLMessage*) message andAccount:(xmpp*) xmppAccount showAlert:(BOOL) showAlert andSound:(BOOL) sound andLMCReplaced:(BOOL) LMCReplaced
{
    if([message.messageType isEqualToString:kMessageTypeStatus])
        return;
    
    DDLogVerbose(@"notification manager should show notification for: %@", message.messageText);
    if(!showAlert)
    {
        DDLogDebug(@"not showing notification: showAlert is NO");
        return;
    }
    
    BOOL muted = [[DataLayer sharedInstance] isMutedJid:message.buddyName onAccount:message.accountID];
    if(!muted && message.isMuc && [[DataLayer sharedInstance] isMucAlertOnMentionOnly:message.buddyName onAccount:message.accountID])
    {
        //check for high mention count and then ignore mentions altogether
        NSSet* words = [NSSet setWithArray:[message.messageText componentsSeparatedByString:@" "]];
        NSMutableSet* participants = [NSMutableSet new];
        for(NSDictionary* entry in [[DataLayer sharedInstance] getMembersAndParticipantsOfMuc:message.buddyName forAccountID:message.accountID])
            [participants addObject:nilWrapper(entry[@"room_nick"])];       //nil wrapper just to make sure, should never intersect with words
        [participants intersectSet:words];
        if([participants count] > 5)
            muted = YES;
        
        NSString* displayName = [MLContact ownDisplayNameForAccount:xmppAccount];
        NSString* ownJid = xmppAccount.connectionProperties.identity.jid;
        NSString* userPart = [HelperTools splitJid:ownJid][@"user"];
        NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:message.buddyName forAccount:message.accountID];
        if(!(
            [message.messageText localizedCaseInsensitiveContainsString:nick] ||
            [message.messageText localizedCaseInsensitiveContainsString:displayName] ||
            [message.messageText localizedCaseInsensitiveContainsString:userPart] ||
            [message.messageText localizedCaseInsensitiveContainsString:ownJid]
        ))
            muted = YES;
    }
    if(muted)
    {
        DDLogDebug(@"not showing notification: this contact got muted");
        return;
    }
    
    //check if we need to replace the still displayed notification or ignore this LMC
    if(LMCReplaced)
    {
        NSString* idval = [self identifierWithMessage:message];
        //wait synchronous for completion (needed for appex)
        MLNotificationState state = PMKHangEnum([self notificationStateForMessage:message]);
        DDLogVerbose(@"Notification state for '%@': %@", idval, @(state));
        if(state == MLNotificationStateNone)
        {
            DDLogDebug(@"not showing notification for LMC: this notification was already removed earlier");
            return;
        }
    }
    
    if([HelperTools isNotInFocus])
    {
        DDLogVerbose(@"notification manager should show notification in background: %@", message.messageText);
        [self showNotificationForMessage:message withSound:sound];
    }
    else
    {
        //don't show notifications for open chats
        if(![message isEqualToContact:self.currentContact])
        {
            DDLogVerbose(@"notification manager should show notification in foreground: %@", message.messageText);
            [self showNotificationForMessage:message withSound:sound];
        }
        else
        {
            DDLogDebug(@"not showing notification and only playing sound: chat is open");
            [self playNotificationSoundForMessage:message withSound:sound];
        }
    }
}

-(void) handleDisplayedMessages:(NSNotification*) notification
{
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    NSArray<MLMessage*>* messages = [notification.userInfo objectForKey:@"messagesArray"];
    DDLogVerbose(@"notification manager got displayed messages notice with %lu entries", [messages count]);
    
    monal_void_block_t block = ^{
        for(MLMessage* msg in messages)
        {
            if([msg.messageType isEqualToString:kMessageTypeStatus])
                return;
            
            NSString* idval = [self identifierWithMessage:msg];
            
            DDLogVerbose(@"Removing pending/delivered notification for message '%@' with identifier '%@'...", msg.messageId, idval);
            [center removePendingNotificationRequestsWithIdentifiers:@[idval]];
            [center removeDeliveredNotificationsWithIdentifiers:@[idval]];
        }
    };
    
    //do this in its own thread because we don't want to block the main thread or other threads here (the removal can take ~50ms)
    //but DON'T do this in the appex because this can try to mess with notifications after the parse queue was frozen (see appex code for explanation what this means)
    if([HelperTools isAppExtension])
        block();
    else
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), block);
    
    //update app badge
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateUnread object:nil];
    
}

-(void) handleDeletedMessage:(NSNotification*) notification
{
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    MLMessage* message = [MLMessage createMessageFromHistoryID:notification.userInfo[@"historyId"]];
    
    if([message.messageType isEqualToString:kMessageTypeStatus])
        return;
    
    NSString* idval = [self identifierWithMessage:message];
    
    DDLogVerbose(@"notification manager got deleted message notice: %@", message.messageId);
    [center removePendingNotificationRequestsWithIdentifiers:@[idval]];
    [center removeDeliveredNotificationsWithIdentifiers:@[idval]];
    
    //update app badge
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateUnread object:nil];
}

-(NSString*) identifierWithMessage:(MLMessage*) message
{
    return [NSString stringWithFormat:@"message(%@, %@)", [self threadIdentifierWithMessage:message], message.messageId];
}

-(NSString*) identifierWithReaction:(MLReactionsEntry*) reactionInfo
{
    return [NSString stringWithFormat:@"reaction(%@, %@)", [self threadIdentifierWithMessage:reactionInfo.message], reactionInfo.message.messageId];
}

-(NSString*) threadIdentifierWithMessage:(MLMessage*) message
{
    return [self threadIdentifierWithContact:message.chatContact];
}

-(NSString*) threadIdentifierWithContact:(MLContact*) contact
{
    return [NSString stringWithFormat:@"thread(%@, %@)", contact.accountID, contact.contactJid];
}

-(UNMutableNotificationContent*) updateBadgeForContent:(UNMutableNotificationContent*) content
{
    NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUnreadMessages];
    DDLogVerbose(@"Raw badge value: %@", unreadMsgCnt);
    content.badge = unreadMsgCnt;
    return content;
}

-(void) publishNotificationContent:(UNNotificationContent*) content withID:(NSString*) idval
{
    //scheduling the notification in 2 seconds will make it possible to be deleted by XEP-0333 chat-markers received directly after the message
    //this is useful in catchup scenarios
    DDLogVerbose(@"notification manager: publishing notification in 2 seconds: %@", content);
    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval content:content trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:2 repeats: NO]];
    NSError* error = [HelperTools postUserNotificationRequest:request];
    if(error)
        DDLogError(@"Error posting local notification: %@", error);
}

-(void) playNotificationSoundForMessage:(MLMessage*) message withSound:(BOOL) sound
{
    UNMutableNotificationContent* content = [UNMutableNotificationContent new];
    NSString* idval = [self identifierWithMessage:message];
    
    if(sound && [[HelperTools defaultsDB] boolForKey:@"Sound"])
    {
        NSString* filename = [[HelperTools defaultsDB] objectForKey:@"AlertSoundFile"];
        if(filename)
        {
            content.sound = [UNNotificationSound soundNamed:[NSString stringWithFormat:@"AlertSounds/%@.aif", filename]];
            DDLogDebug(@"Using user configured alert sound: %@", content.sound);
        }
        else
        {
            content.sound = [UNNotificationSound defaultSound];
            DDLogDebug(@"Using default alert sound: %@", content.sound);
        }
    }
    else
        DDLogDebug(@"Using no alert sound");
    
    DDLogDebug(@"Publishing sound-but-no-body notification with id %@", idval);
    [self publishNotificationContent:[self updateBadgeForContent:content] withID:idval];
}

-(void) showNotificationForReactions:(MLReactionsEntry*) reactionInfo
{
    UNMutableNotificationContent* content = [UNMutableNotificationContent new];
    NSString* idval = [self identifierWithReaction:reactionInfo];
    
    INSendMessageAttachment* audioAttachment = nil;
    NSString* msgText = NSLocalizedString(@"Open app to see more", @"");
    
    if([[HelperTools defaultsDB] boolForKey:@"Sound"])
    {
        NSString* filename = [[HelperTools defaultsDB] objectForKey:@"AlertSoundFile"];
        if(filename)
        {
            content.sound = [UNNotificationSound soundNamed:[NSString stringWithFormat:@"AlertSounds/%@.aif", filename]];
            DDLogDebug(@"Using user configured alert sound: %@", content.sound);
        }
        else
        {
            content.sound = [UNNotificationSound defaultSound];
            DDLogDebug(@"Using default alert sound: %@", content.sound);
        }
    }
    else
        DDLogDebug(@"Using no alert sound");
    
    //these are legacy notifications (no modern communication notifications)
    if(self.notificationPrivacySetting == NotificationPrivacySettingOptionDisplayOnlyPlaceholder)
    {
        content.title = NSLocalizedString(@"New Reaction", @"");
        content.body = msgText;

        DDLogDebug(@"Publishing reaction notification with id %@", idval);
        [self publishNotificationContent:[self updateBadgeForContent:content] withID:idval];
        return;
    }
    
    //everything else is a modern communication notification
    content.threadIdentifier = [self threadIdentifierWithMessage:reactionInfo.message];
    content.categoryIdentifier = @"reaction";
    
    //user info for notification actions
    content.userInfo = @{
        @"contact": [HelperTools serializeObject:reactionInfo.message.chatContact],
        @"message": [HelperTools serializeObject:reactionInfo.message],
        @"reactingContact": [HelperTools serializeObject:reactionInfo.contact],
    };
    
    if(self.notificationPrivacySetting <= NotificationPrivacySettingOptionDisplayOnlyName)
        msgText = NSLocalizedString(@"New reaction, open app to see it", @"");
    if(self.notificationPrivacySetting == NotificationPrivacySettingOptionDisplayNameAndMessage)
    {
        msgText = [NSString stringWithFormat:NSLocalizedString(@"Reacted with %@ to «%@».", @""), [[reactionInfo.reactions array] componentsJoinedByString:@""], [self messageToText:reactionInfo.message]];
        if([reactionInfo.message.messageType isEqualToString:kMessageTypeFiletransfer])
        {
            MLFiletransferInfo* fileInfo = reactionInfo.message.fileInfo;
            if(fileInfo.downloadState == DownloadStateComplete && (fileInfo.isImage || fileInfo.isVideo || fileInfo.isAudio))
            {
                if(fileInfo.isAudio)
                {
                    audioAttachment = [INSendMessageAttachment attachmentWithAudioMessageFile:[INFile fileWithFileURL:[NSURL fileURLWithPath:fileInfo.cacheFilePath] filename:fileInfo.filename typeIdentifier:fileInfo.utType.identifier]];
                    DDLogVerbose(@"Added audio attachment(%@ = %@): %@", fileInfo.mimeType, fileInfo.utType, audioAttachment);
                }
                UNNotificationAttachment* attachment = [self createNotificationAttachmentForFileInfo:fileInfo];
                if(attachment)
                    content.attachments = @[attachment];
            }
        }
    }
    content.body = msgText;
    
    INSendMessageIntent* intent = [self makeIntentForMessage:reactionInfo.message havingReaction:reactionInfo usingText:msgText andAudioAttachment:nil direction:INInteractionDirectionIncoming];
    
    INInteraction* interaction = [[INInteraction alloc] initWithIntent:intent response:nil];
    interaction.direction = INInteractionDirectionIncoming;
    
    NSError* error = nil;
    UNNotificationContent* updatedContent = [content contentByUpdatingWithProvider:intent error:&error];
    if(error)
        DDLogError(@"Could not update notification content: %@", error);
    else
    {
        DDLogDebug(@"Publishing communication notification with id %@", idval);
        [self publishNotificationContent:updatedContent withID:idval];
    }
}

-(void) showNotificationForMessage:(MLMessage*) message withSound:(BOOL) sound
{
    // always use legacy notifications if we should only show a generic "New Message" notifiation without name or content
    if(self.notificationPrivacySetting == NotificationPrivacySettingOptionDisplayOnlyPlaceholder)
        return [self showLegacyNotificationForMessage:message withSound:sound];
    
    return [self showModernNotificationForMessage:message withSound:sound];
}

-(void) showLegacyNotificationForMessage:(MLMessage*) message withSound:(BOOL) sound
{
    NSString* idval = [self identifierWithMessage:message];
    
    UNMutableNotificationContent* content = [UNMutableNotificationContent new];
    content.title = NSLocalizedString(@"New Message", @"");
    content.body = NSLocalizedString(@"Open app to see more", @"");
    
    if(sound && [[HelperTools defaultsDB] boolForKey:@"Sound"])
    {
        NSString* filename = [[HelperTools defaultsDB] objectForKey:@"AlertSoundFile"];
        if(filename)
        {
            content.sound = [UNNotificationSound soundNamed:[NSString stringWithFormat:@"AlertSounds/%@.aif", filename]];
            DDLogDebug(@"Using user configured alert sound: %@", content.sound);
        }
        else
        {
            content.sound = [UNNotificationSound defaultSound];
            DDLogDebug(@"Using default alert sound: %@", content.sound);
        }
    }
    else
        DDLogDebug(@"Using no alert sound");
    
    DDLogDebug(@"Publishing notification with id %@", idval);
    [self publishNotificationContent:[self updateBadgeForContent:content] withID:idval];
}

-(void) showModernNotificationForMessage:(MLMessage*) message withSound:(BOOL) sound
{
    UNMutableNotificationContent* content = [UNMutableNotificationContent new];
    NSString* idval = [self identifierWithMessage:message];
    
    INSendMessageAttachment* audioAttachment = nil;
    NSString* msgText = [self messageToText:message];
    
    //notification settings
    content.threadIdentifier = [self threadIdentifierWithMessage:message];
    content.categoryIdentifier = @"message";
    
    //user info for notification actions
    content.userInfo = @{
        @"contact": [HelperTools serializeObject:message.chatContact],
        @"message": [HelperTools serializeObject:message],
    };
    
    //only show real message text if we are allowed to (use placeholder otherwise)
    if(self.notificationPrivacySetting == NotificationPrivacySettingOptionDisplayNameAndMessage)
    {
        if([message.messageType isEqualToString:kMessageTypeFiletransfer])
        {
            MLFiletransferInfo* fileInfo = message.fileInfo;
            if(fileInfo.downloadState == DownloadStateComplete && (fileInfo.isImage || fileInfo.isVideo || fileInfo.isAudio))
            {
                if(fileInfo.isAudio)
                {
                    audioAttachment = [INSendMessageAttachment attachmentWithAudioMessageFile:[INFile fileWithFileURL:[NSURL fileURLWithPath:fileInfo.cacheFilePath] filename:fileInfo.filename typeIdentifier:fileInfo.utType.identifier]];
                    DDLogVerbose(@"Added audio attachment(%@ = %@): %@", fileInfo.mimeType, fileInfo.utType, audioAttachment);
                }
                UNNotificationAttachment* attachment = [self createNotificationAttachmentForFileInfo:fileInfo];
                if(attachment)
                    content.attachments = @[attachment];
            }
        }
    }
    content.body = msgText;     //save message text to notification content
    
    if(sound && [[HelperTools defaultsDB] boolForKey:@"Sound"])
    {
        NSString* filename = [[HelperTools defaultsDB] objectForKey:@"AlertSoundFile"];
        if(filename)
        {
            content.sound = [UNNotificationSound soundNamed:[NSString stringWithFormat:@"AlertSounds/%@.aif", filename]];
            DDLogDebug(@"Using user configured alert sound: %@", content.sound);
        }
        else
        {
            content.sound = [UNNotificationSound defaultSound];
            DDLogDebug(@"Using default alert sound: %@", content.sound);
        }
    }
    else
        DDLogDebug(@"Using no alert sound");
        
    // update badge value prior to donating the interaction to sirikit
    [self updateBadgeForContent:content];
    
    INSendMessageIntent* intent = [self makeIntentForMessage:message havingReaction:nil usingText:msgText andAudioAttachment:audioAttachment direction:INInteractionDirectionIncoming];
    
    INInteraction* interaction = [[INInteraction alloc] initWithIntent:intent response:nil];
    interaction.direction = INInteractionDirectionIncoming;
    interaction.identifier = [NSString stringWithFormat:@"%@|%@", message.accountID, message.buddyName];
    
    NSError* error = nil;
    UNNotificationContent* updatedContent = [content contentByUpdatingWithProvider:intent error:&error];
    if(error)
        DDLogError(@"Could not update notification content: %@", error);
    else
    {
        DDLogDebug(@"Publishing communication notification with id %@", idval);
        [self publishNotificationContent:updatedContent withID:idval];
    }
    
    //we can donate interactions after posting their notification (see signal source code)
    [interaction donateInteractionWithCompletion:^(NSError *error) {
        if(error)
            DDLogError(@"Could not donate interaction: %@", error);
    }];
}

-(void) donateInteractionForOutgoingDBId:(NSNumber*) messageDBId
{
    MLMessage* message = [MLMessage createMessageFromHistoryID:messageDBId];
    INSendMessageIntent* intent = [self makeIntentForMessage:message havingReaction:nil usingText:@"dummyText" andAudioAttachment:nil direction:INInteractionDirectionOutgoing];
    INInteraction* interaction = [[INInteraction alloc] initWithIntent:intent response:nil];
    interaction.direction = INInteractionDirectionOutgoing;
    interaction.identifier = [NSString stringWithFormat:@"%@|%@", message.accountID, message.buddyName];
    [interaction donateInteractionWithCompletion:^(NSError *error) {
        if(error)
            DDLogError(@"Could not donate outgoing interaction: %@", error);
    }];
}

-(INSendMessageIntent*) makeIntentForMessage:(MLMessage*) message havingReaction:(MLReactionsEntry* _Nullable) reaction usingText:(NSString*) msgText andAudioAttachment:(INSendMessageAttachment*) audioAttachment direction:(INInteractionDirection) direction
{
    // some docu:
    // - https://developer.apple.com/documentation/usernotifications/implementing_communication_notifications?language=objc
    // - https://gist.github.com/Dexwell/dedef7389eae26c5b9db927dc5588905
    // - https://stackoverflow.com/a/68705169/3528174
    xmpp* account = message.account;
    MLContact* contact = message.chatContact;
    INPerson* sender = nil;
    NSString* groupDisplayName = nil;
    NSMutableArray* recipients = [NSMutableArray new];
    if(message.isMuc)
    {
        groupDisplayName = contact.contactDisplayName;
        //we don't need different handling of incoming or outgoing messages for non-anon mucs because sender and receiver always contain the right contacts
        if([kMucTypeGroup isEqualToString:message.mucType] && message.participantJid)
        {
            id<MLContactProtocol> senderContactInGroup = reaction != nil ? reaction.contact : message.contact;
            //use MLMessage's capability to calculate the fallback name using actualFrom
            sender = [self makeINPersonWithContact:senderContactInGroup andDisplayName:(reaction != nil ? reaction.contact.contactDisplayName : message.contactDisplayName) andAccount:account];
            
            //add other group members (except the sender)
            for(NSDictionary* member in [[DataLayer sharedInstance] getMembersAndParticipantsOfMuc:message.buddyName forAccountID:message.accountID])
            {
                NSString* jid = emptyDefault(member[@"participant_jid"], @"", member[@"member_jid"]);
                if(jid == nil)
                {
                    DDLogError(@"Jid should not be nil for member of MUC '%@': %@", message.buddyName, member);
                    continue;
                }
                MLContact* contactInGroup = [MLContact createContactFromJid:jid andAccountID:message.accountID];
                if(![contactInGroup isEqualToContact:senderContactInGroup])
                    [recipients addObject:[self makeINPersonWithContact:contactInGroup andDisplayName:member[@"room_nick"] andAccount:account]];
            }
        }
        else
        {
            //reactions bring their own contact info
            //use MLMessage's or MLContact's/MLChannelContact's capability to calculate the fallback name using actualFrom
            INPerson* selfPerson = [self makeINPersonForOwnAccount:account];
            INPerson* otherPerson = nil ;
            if(reaction != nil)
                otherPerson = [self makeINPersonWithContact:contact andDisplayName:reaction.contact.contactDisplayName andAccount:account];
            else
                otherPerson = [self makeINPersonWithContact:contact andDisplayName:message.contactDisplayName andAccount:account];
            
            //choose sender depending on direction
            if(direction == INInteractionDirectionIncoming)
                sender = otherPerson;
            else
                sender = selfPerson;
            
            //the next 2 lines are needed to make iOS show the group name in notifications (we need recipients.count > 1)
            [recipients addObject:selfPerson];
            [recipients addObject:otherPerson];
        }
    }
    else
    {
        if(direction == INInteractionDirectionIncoming)
        {
            sender = [self makeINPersonWithContact:(reaction != nil ? reaction.contact : contact) andDisplayName:nil andAccount:account];
            [recipients addObject:[self makeINPersonForOwnAccount:account]];
        }
        else
        {
            sender = [self makeINPersonForOwnAccount:account];
            [recipients addObject:[self makeINPersonWithContact:contact andDisplayName:nil andAccount:account]];
        }
    }
    
    DDLogDebug(@"Creating INSendMessageIntent with recipients=%@, speakableGroupName=%@, sender=%@", recipients, groupDisplayName, sender);
    INSendMessageIntent* intent = [[INSendMessageIntent alloc] initWithRecipients:recipients
                                                              outgoingMessageType:(audioAttachment ? INOutgoingMessageTypeOutgoingMessageAudio : INOutgoingMessageTypeOutgoingMessageText)
                                                                          content:msgText
                                                               speakableGroupName:(groupDisplayName ? [[INSpeakableString alloc] initWithSpokenPhrase:groupDisplayName] : nil)
                                                           conversationIdentifier:[[NSString alloc] initWithData:[HelperTools serializeObject:contact] encoding:NSISOLatin1StringEncoding]
                                                                      serviceName:message.accountID.stringValue
                                                                           sender:sender
                                                                      attachments:(audioAttachment ? @[audioAttachment] : @[])];
    //DDLogDebug(@"Intent is now: %@", intent);
    if(message.isMuc)
    {
        if(contact.avatar != nil)
        {
            DDLogDebug(@"Using muc avatar image: %@", contact.avatar);
            [intent setImage:[INImage imageWithImageData:UIImagePNGRepresentation(contact.avatar)] forParameterNamed:@"speakableGroupName"];
            [intent setImage:[INImage imageWithImageData:UIImagePNGRepresentation(message.contact.avatar)] forParameterNamed:@"sender"];
        }
        else
            DDLogDebug(@"NOT using muc avatar image...");
    }
    
    return intent;
}

-(INPerson*) makeINPersonForOwnAccount:(xmpp*) account
{
    DDLogDebug(@"Building INPerson for self contact...");
    NSString* personHandleIdentifier = [NSString stringWithFormat:@"xmpp:%@", account.connectionProperties.identity.jid];
    INPersonHandle* personHandle = [[INPersonHandle alloc] initWithValue:personHandleIdentifier type:INPersonHandleTypeUnknown label:@"Monal IM"];
    NSPersonNameComponents* nameComponents = [NSPersonNameComponents new];
    nameComponents.nickname = [MLContact ownDisplayNameForAccount:account];
    MLContact* ownContact = account.contact;
    INImage* contactImage = nil;
    if(ownContact.avatar != nil)
    {
        DDLogDebug(@"Using own avatar image: %@", ownContact.avatar);
        NSData* avatarData = UIImagePNGRepresentation(ownContact.avatar);
        contactImage = [INImage imageWithImageData:avatarData];
    }
    else
        DDLogDebug(@"NOT using own avatar image...");
    INPerson* person = [[INPerson alloc] initWithPersonHandle:personHandle
                                               nameComponents:nameComponents
                                                  displayName:nameComponents.nickname
                                                        image:contactImage
                                            contactIdentifier:nil
                                             customIdentifier:nil
                                                         isMe:YES
                                               suggestionType:INPersonSuggestionTypeInstantMessageAddress];
    return person;
}

-(INPerson*) makeINPersonWithContact:(id<MLContactProtocol>) contact andDisplayName:(NSString* _Nullable) displayName andAccount:(xmpp*) account
{
    DDLogDebug(@"Building INPerson for contact: %@ using display name: %@", contact, displayName);
    if(displayName == nil)
        displayName = contact.contactDisplayName;
    
    //identifiers are exposed to users in the ios ui (--> we can't use occupantId)
    //also make sure muc nicks can't be used to spoof a bare jid
    NSString* personHandleIdentifier = @"<unknown>";
    if([contact isKindOfClass:[MLContact class]])
        personHandleIdentifier = [NSString stringWithFormat:@"xmpp:%@", ((MLContact*)contact).contactJid];
    else if([contact isKindOfClass:[MLChannelContact class]])
        personHandleIdentifier = [NSString stringWithFormat:@"xmpp:%@, channel-nick: %@", ((MLChannelContact*)contact).mucContact.contactJid, ((MLChannelContact*)contact).nick];
    INPersonHandle* personHandle = [[INPersonHandle alloc] initWithValue:personHandleIdentifier type:INPersonHandleTypeUnknown label:@"Monal IM"];
    
    NSPersonNameComponents* nameComponents = [NSPersonNameComponents new];
    nameComponents.nickname = displayName;
    INImage* contactImage = nil;
    if(contact.avatar != nil)
    {
        DDLogDebug(@"Using avatar image: %@", contact.avatar);
        NSData* avatarData = UIImagePNGRepresentation(contact.avatar);
        contactImage = [INImage imageWithImageData:avatarData];
    }
    else
        DDLogDebug(@"NOT using avatar image...");
    INPerson* person = [[INPerson alloc] initWithPersonHandle:personHandle
                                               nameComponents:nameComponents
                                                  displayName:nameComponents.nickname
                                                        image:contactImage
                                            contactIdentifier:nil
                                             customIdentifier:nil
                                                         isMe:contact.isSelf
                                               suggestionType:INPersonSuggestionTypeInstantMessageAddress];
    /*
    if(contact.isInRoster)	
        person.relationship = INPersonRelationshipFriend;
    */
    return person;
}

-(UNNotificationAttachment* _Nullable) createNotificationAttachmentForFileInfo:(MLFiletransferInfo*) info
{
    NSError* error;
    UTType* typeHint = info.utType;
    NSString* attachmentDir = [[HelperTools getContainerURLForPathComponents:@[@"documentCache"]] path];
    //use "tmp." prefix to make sure this file will be garbage collected should the ios notification attachment implementation leave it behind
    NSString* attachmentBasename = [NSString stringWithFormat:@"tmp.%@", info.cacheId];
    NSString* notificationAttachment = [attachmentDir stringByAppendingPathComponent:[attachmentBasename stringByAppendingPathExtensionForType:typeHint]];
    //using stringByAppendingPathExtensionForType: does not produce playable audio notifications for audios sent by conversations,
    //but seems to work for other types
    //--> use info[@"fileExtension"] for audio files and stringByAppendingPathExtensionForType: for all other types
    if([typeHint conformsToType:UTTypeAudio])
        notificationAttachment = [notificationAttachment stringByAppendingPathComponent:[attachmentBasename stringByAppendingPathExtension:info.fileExtension]];
    UIImage* image = nil;
    if([info.mimeType hasPrefix:@"image/svg"])
    {
        NSString* pngAttachment = [attachmentDir stringByAppendingPathComponent:[attachmentBasename stringByAppendingPathExtensionForType:UTTypePNG]];
        DDLogVerbose(@"Preparing for notification attachment(%@): converting downloaded file from svg at '%@' to png at '%@'...", typeHint, info.cacheFilePath, pngAttachment);
        //we want our code to run synchronously --> use PMKHang
        //this code should never run in the main queue to not provoke a deadlock
        if([NSThread isMainThread])
            @throw [NSException exceptionWithName:@"InvalidThread" reason:@"PMKHang on renderUIImageFromSVGURL must never be called on the main thread!" userInfo:nil]; 
        image = (UIImage*)nilExtractor(PMKHang([HelperTools renderUIImageFromSVGURL:[NSURL fileURLWithPath:info.cacheFilePath]]));
        if(image != nil)
        {
            [UIImagePNGRepresentation(image) writeToFile:pngAttachment atomically:YES];
            typeHint = UTTypePNG;
            notificationAttachment = pngAttachment;
        }
    }
    //fallback if svg extraction failed OR it wasn't an SVG image in the first place
    if(image == nil)
    {
        DDLogVerbose(@"Preparing for notification attachment(%@): hardlinking downloaded file from '%@' to '%@'...", typeHint, info.cacheFilePath, notificationAttachment);
        error = [HelperTools hardLinkOrCopyFile:info.cacheFilePath to:notificationAttachment];
        if(error)
        {
            DDLogError(@"Could not hardlink cache file to notification image temp file!");
            return nil;
        }
    }
    [HelperTools configureFileProtectionFor:notificationAttachment];
    UNNotificationAttachment* attachment = [UNNotificationAttachment attachmentWithIdentifier:info.cacheId URL:[NSURL fileURLWithPath:notificationAttachment] options:@{UNNotificationAttachmentOptionsTypeHintKey:typeHint} error:&error];
    if(error != nil)
        DDLogError(@"Could not create UNNotificationAttachment: %@", error);
    return attachment;
}

-(NSString*) messageToText:(MLMessage*) message
{
    NSString* msgText = NSLocalizedString(@"Open app to see more", @"");
    
    if(self.notificationPrivacySetting == NotificationPrivacySettingOptionDisplayNameAndMessage)
    {
        //XEP-0245: The slash me Command
        if([message.messageText hasPrefix:@"/me "])
            msgText = [[MLXEPSlashMeHandler sharedInstance] stringSlashMeWithMessage:message];
        else
            msgText = message.messageText;
        
        if([message.messageType isEqualToString:kMessageTypeFiletransfer])
        {
            MLFiletransferInfo* fileInfo = message.fileInfo;

            if(fileInfo.isImage)
                msgText = NSLocalizedString(@"📷 An Image", @"");
            else if(fileInfo.isAudio)
                msgText = NSLocalizedString(@"🎵 An Audiomessage", @"");
            else if(fileInfo.isVideo)
                msgText = NSLocalizedString(@"🎥 A Video", @"");
            else if(fileInfo.isPDF)
                msgText = NSLocalizedString(@"📄 A Document", @"");
            else
                msgText = NSLocalizedString(@"📁 A File", @"");
        }
        else if([message.messageType isEqualToString:kMessageTypeUrl] && [[HelperTools defaultsDB] boolForKey:@"ShowURLPreview"])
            msgText = NSLocalizedString(@"🔗 A Link", @"");
        else if([message.messageType isEqualToString:kMessageTypeGeo])
            msgText = NSLocalizedString(@"📍 A Location", @"");
    }
    
    return msgText;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
