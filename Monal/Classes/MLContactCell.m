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
    
    [[MLImageManager sharedInstance] getIconForContact:contact withCompletion:^(UIImage *image) {
        self.userImage.image = image;
    }];
    
    if(contact.isGroup && contact.isMentionOnly)
    {
        self.muteBadge.hidden = YES;
        self.mentionBadge.hidden = NO;
    }
    else
    {
        self.muteBadge.hidden = !contact.isMuted;
        self.mentionBadge.hidden = YES;
    }
}

-(void) displayLastMessage:(MLMessage* _Nullable) lastMessage forContact:(MLContact*) contact
{
    NSString* senderOfLastGroupMsg; // set to nick of sender in a group chat
    if(contact.isGroup == YES)
        senderOfLastGroupMsg = lastMessage.actualFrom;

    if(lastMessage)
    {
        if([lastMessage.messageType isEqualToString:kMessageTypeUrl] && [[HelperTools defaultsDB] boolForKey:@"ShowURLPreview"])
            [self showStatusText:NSLocalizedString(@"🔗 A Link", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
        else if([lastMessage.messageType isEqualToString:kMessageTypeFiletransfer])
        {
            if([lastMessage.filetransferMimeType hasPrefix:@"image/"])
                [self showStatusText:NSLocalizedString(@"📷 An Image", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            else if([lastMessage.filetransferMimeType hasPrefix:@"audio/"])
                [self showStatusText:NSLocalizedString(@"🎵 A Audiomessage", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            else if([lastMessage.filetransferMimeType hasPrefix:@"video/"])
                [self showStatusText:NSLocalizedString(@"🎥 A Video", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            else if([lastMessage.filetransferMimeType isEqualToString:@"application/pdf"])
                [self showStatusText:NSLocalizedString(@"📄 A Document", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            else
                [self showStatusText:NSLocalizedString(@"📁 A File", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
        }
        else if ([lastMessage.messageType isEqualToString:kMessageTypeMessageDraft])
        {
            NSString* draftPreviewPrefix = NSLocalizedString(@"Draft:", @"");
            NSString* draftPreview = [NSString stringWithFormat:@"%@ %@", draftPreviewPrefix, lastMessage.messageText];
            [self showStatusTextItalic:draftPreview withItalicRange:NSMakeRange(0, draftPreviewPrefix.length)];
        }
        else if([lastMessage.messageType isEqualToString:kMessageTypeGeo])
            [self showStatusText:NSLocalizedString(@"📍 A Location", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
        else
        {
            if([lastMessage.messageText hasPrefix:@"/me "])
            {
                NSString* replacedMessageText = [[MLXEPSlashMeHandler sharedInstance] stringSlashMeWithMessage:lastMessage];
                NSRange replacedMsgAttrRange = NSMakeRange(0, replacedMessageText.length);
                [self showStatusTextItalic:replacedMessageText withItalicRange:replacedMsgAttrRange];
            }
            else
            {
                [self showStatusText:lastMessage.messageText inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
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
        [self showStatusText:nil inboundDir:lastMessage.inbound fromUser:nil];
        DDLogWarn(@"Active chat but no messages found in history for %@.", contact.contactJid);
    }
}

-(void) showStatusText:(NSString *) text inboundDir:(BOOL) inboundDir fromUser:(NSString* _Nullable) fromUser
{
    NSString* statusMessage = @"";
    if(inboundDir == NO)
        statusMessage = [NSString stringWithFormat:@"%@ ", NSLocalizedString(@"Me", @"")];
    else if(inboundDir == YES && fromUser != nil && fromUser.length > 0)
        statusMessage = [NSString stringWithFormat:@"%@: ", fromUser];

    // set range of "Me" prefix that should be gray
    NSRange meAttrRange = NSMakeRange(0, statusMessage.length);

    if(text != nil)
    {
        statusMessage = [statusMessage stringByAppendingString:text];
        // set attribute settings
        NSMutableAttributedString* attrStatusText = [[NSMutableAttributedString alloc] initWithString:statusMessage];
        [attrStatusText addAttribute:NSForegroundColorAttributeName value:[UIColor lightGrayColor] range:meAttrRange];

        if(![attrStatusText isEqualToAttributedString:self.statusText.originalAttributedText])
        {
            // only update UI if needed
            self.statusText.attributedText = attrStatusText;
            [self setStatusTextLayout:text];
        }
    }
    else
    {
        self.statusText.text = nil;
    }
}

-(void) showStatusTextItalic:(NSString*) text withItalicRange:(NSRange) italicRange
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
    if(self.displayName && ![self.displayName.text isEqualToString:name])
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
        self.backgroundColor = nil;
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
