//
//  MLContactCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

#import "MLContactCell.h"
#import "MLConstants.h"
#import "MLContact.h"
#import "MLMessage.h"
#import "DataLayer.h"
#import "MLXEPSlashMeHandler.h"
#import "HelperTools.h"
#import "MLXMPPManager.h"
#import "xmpp.h"
#import "MLImageManager.h"
#import <QuartzCore/QuartzCore.h>

@interface MLContactCell()

@end

@implementation MLContactCell

-(void) awakeFromNib
{
    [super awakeFromNib];
}

-(void) initCell:(MLContact*) contact withLastMessage:(MLMessage* _Nullable) lastMessage
{
    self.accountNo = contact.accountId.integerValue;
    self.username = contact.contactJid;

    [self showDisplayName:contact.contactDisplayName];
    [self setPinned:contact.isPinned];
    [self setCount:(long)contact.unreadCount];
    [self displayLastMessage:lastMessage forContact:contact];

    [[MLImageManager sharedInstance] getIconForContact:contact.contactJid andAccount:contact.accountId withCompletion:^(UIImage *image) {
        self.userImage.image = image;
    }];
    BOOL muted = [[DataLayer sharedInstance] isMutedJid:contact.contactJid onAccount:contact.accountId];
    self.muteBadge.hidden = !muted;
}

-(void) displayLastMessage:(MLMessage* _Nullable) lastMessage forContact:(MLContact*) contact
{
    if(lastMessage)
    {
        if([lastMessage.messageType isEqualToString:kMessageTypeUrl] && [[HelperTools defaultsDB] boolForKey:@"ShowURLPreview"])
            [self showStatusText:NSLocalizedString(@"🔗 A Link", @"")];
        else if([lastMessage.messageType isEqualToString:kMessageTypeFiletransfer])
        {
            if([lastMessage.filetransferMimeType hasPrefix:@"image/"])
                [self showStatusText:NSLocalizedString(@"📷 An Image", @"")];
            else if([lastMessage.filetransferMimeType hasPrefix:@"audio/"])
                [self showStatusText:NSLocalizedString(@"🎵 A Audiomessage", @"")];
            else if([lastMessage.filetransferMimeType hasPrefix:@"video/"])
                [self showStatusText:NSLocalizedString(@"🎥 A Video", @"")];
            else if([lastMessage.filetransferMimeType isEqualToString:@"application/pdf"])
                [self showStatusText:NSLocalizedString(@"📄 A Document", @"")];
            else
                [self showStatusText:NSLocalizedString(@"📁 A File", @"")];
        }
        else if ([lastMessage.messageType isEqualToString:kMessageTypeMessageDraft])
        {
            NSString* draftPreview = [NSString stringWithFormat:NSLocalizedString(@"Draft: %@", @""), lastMessage.messageText];
            [self showStatusTextItalic:draftPreview withItalicRange:NSMakeRange(0, 6)];
        }
        else if([lastMessage.messageType isEqualToString:kMessageTypeGeo])
            [self showStatusText:NSLocalizedString(@"📍 A Location", @"")];
        else
        {
            NSString* displayName;
            xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:contact.accountId];
            if(lastMessage.inbound == NO)
                displayName = [MLContact ownDisplayNameForAccount:account];
            else
                displayName = [contact contactDisplayName];
            if([lastMessage.messageText hasPrefix:@"/me "])
            {
                NSString* replacedMessageText = [[MLXEPSlashMeHandler sharedInstance] stringSlashMeWithAccountId:contact.accountId displayName:displayName actualFrom:lastMessage.actualFrom message:lastMessage.messageText isGroup:contact.isGroup];

                NSRange replacedMsgAttrRange = NSMakeRange(0, replacedMessageText.length);

                [self showStatusTextItalic:replacedMessageText withItalicRange:replacedMsgAttrRange];
            }
            else
            {
                [self showStatusText:lastMessage.messageText];
            }
        }
        if(lastMessage.timestamp)
        {
            self.time.text = [self formattedDateWithSource:lastMessage.timestamp];
            self.time.hidden = NO;
        }
        else
            self.time.hidden = YES;
    }
    else
    {
        [self showStatusText:nil];
        DDLogWarn(@"Active chat but no messages found in history for %@.", contact.contactJid);
    }
}

-(void) showStatusText:(NSString *) text
{
    if(![self.statusText.text isEqualToString:text])
    {
        self.statusText.text = text;
        [self setStatusTextLayout:text];
    }
}

-(void) showStatusTextItalic:(NSString *) text withItalicRange:(NSRange)italicRange
{
    UIFont* italicFont = [UIFont italicSystemFontOfSize:self.statusText.font.pointSize];
    NSMutableAttributedString* italicString = [[NSMutableAttributedString alloc] initWithString:text];
    [italicString addAttribute:NSFontAttributeName value:italicFont range:italicRange];

    if(![italicString isEqualToAttributedString:self.statusText.originalAttributedText])
    {
        self.statusText.attributedText = italicString;
        [self setStatusTextLayout:text];
    }
}

-(void) setStatusTextLayout:(NSString*) text
{
    if(text)
    {
        self.centeredDisplayName.hidden = YES;
        self.displayName.hidden = NO;
        self.statusText.hidden = NO;
    }
    else
    {
        self.centeredDisplayName.hidden = NO;
        self.displayName.hidden=YES;
        self.statusText.hidden=YES;
    }
}

-(void) showDisplayName:(NSString *) name
{
    if(![self.displayName.text isEqualToString:name])
    {
        self.centeredDisplayName.text = name;
        self.displayName.text = name;
    }
}

-(void) setCount:(long)count
{
    if(count > 0)
    {
        // show number of unread messages
        [self.badge setTitle:[NSString stringWithFormat:@"%ld", (long)count] forState:UIControlStateNormal];
        self.badge.hidden = NO;
    }
    else
    {
        // hide number of unread messages
        [self.badge setTitle:@"" forState:UIControlStateNormal];
        self.badge.hidden = YES;
    }
}

-(void) setPinned:(BOOL) pinned
{
    self.isPinned = pinned;
    
    if(pinned) {
        self.backgroundColor = [UIColor colorNamed:@"activeChatsPinnedColor"];
    } else {
        self.backgroundColor = UIColor.clearColor;
    }
}

#pragma mark - date
-(NSString*) formattedDateWithSource:(NSDate*) sourceDate
{
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    if([[NSCalendar currentCalendar] isDateInToday:sourceDate])
    {
        //today just show time
        [dateFormatter setDateStyle:NSDateFormatterNoStyle];
        [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    }
    else
    {
        // note: if it isnt the same day we want to show the full day
        [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
        //no more need for seconds
        [dateFormatter setTimeStyle:NSDateFormatterNoStyle];
    }
    NSString* dateString = [dateFormatter stringFromDate:sourceDate];
    return dateString ? dateString : @"";
}

@end
