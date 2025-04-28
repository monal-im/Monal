//
//  ChatViewHelpers.m
//  Monal
//
//  Created by lissine on 28/4/2025.
//  Copyright © 2025 monal-im.org. All rights reserved.
//

#import "ChatViewHelpers.h"
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/xmpp.h>
#import <monalxmpp/MLNotificationQueue.h>
#import "MLNotificationManager.h"

@implementation ChatViewHelpers

+(void) refreshCounterForContact:(MLContact*) contact
{
    if(![contact isEqualToContact:[MLNotificationManager sharedInstance].currentContact])
        return;

    if(![HelperTools isNotInFocus])
    {
        //don't block the main thread while writing to the db (another thread could hold a write transaction already, slowing down the main thread)
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            //get list of unread messages
            NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:contact.contactJid andAccount:contact.accountID tillStanzaId:nil wasOutgoing:NO];

            //publish MDS display marker and optionally send displayed marker for last unread message (XEP-0333)
            DDLogDebug(@"Sending MDS (and possibly XEP-0333 displayed marker) for messages: %@", unread);
            [contact.account sendDisplayMarkerForMessages:unread];

            //now switch back to the main thread, we are reading only (and contact should only be accessed from the main thread)
            dispatch_async(dispatch_get_main_queue(), ^{
                //remove notifications of all read messages (this will cause the MLNotificationManager to update the app badge, too)
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalDisplayedMessagesNotice object:contact.account userInfo:@{@"messagesArray":unread}];

                // update unread counter
                [contact updateUnreadCount];

                //refresh contact in active contacts view
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:contact.account userInfo:@{@"contact": contact}];
            });
        });

    }
    else
        DDLogDebug(@"Not marking messages as read because we are still in background: %@ notInFokus: %@", bool2str([HelperTools isInBackground]), bool2str([HelperTools isNotInFocus]));
}

@end
