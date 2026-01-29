//
//  MLContactCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

#import "MLContactCell.h"
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/MLContact.h>
#import <monalxmpp/MLMessage.h>
#import <monalxmpp/DataLayer.h>
#import "MLXEPSlashMeHandler.h"
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/MLXMPPManager.h>
#import <monalxmpp/xmpp.h>
#import <monalxmpp/MLImageManager.h>
#import <monalxmpp/MLFiletransferInfo.h>
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
    [self showDisplayName:contact.contactDisplayName];
    [self setPinned:contact.isPinned];
    [self setCount:(long)contact.unreadCount];
    [self displayLastMessage:lastMessage forContact:contact];
    
    [[MLImageManager sharedInstance] getIconForContact:contact withCompletion:^(UIImage *image) {
        self.userImage.image = image;
    }];
    
    if(contact.isMuc && contact.isMentionOnly)
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
    if(lastMessage)
    {
        if(lastMessage.timestamp)
        {
            self.time.text = [self formattedDateWithSource:lastMessage.timestamp];
            self.time.hidden = NO;
        }
        else
            self.time.hidden = YES;
        
        if(lastMessage.retracted)
        {
            NSString* retractedStatus = NSLocalizedString(@"This message got retracted", @"");
            [self showStatusTextItalic:retractedStatus withItalicRange:NSMakeRange(0, retractedStatus.length)];
            return;
        }
        else if ([lastMessage.messageType isEqualToString:kMessageTypeMessageDraft])
        {
            NSString* draftPreviewPrefix = NSLocalizedString(@"Draft:", @"");
            NSString* draftPreview = [NSString stringWithFormat:@"%@ %@", draftPreviewPrefix, lastMessage.messageText];
            [self showStatusTextItalic:draftPreview withItalicRange:NSMakeRange(0, draftPreviewPrefix.length)];
            return;
        }
        
        NSString* senderOfLastGroupMsg;     // set to nick of sender in a group chat, if this is a group chat (1:1 MUST be nil)
        if(lastMessage.isMuc)
            senderOfLastGroupMsg = lastMessage.contactDisplayName;
        
        if([lastMessage.messageType isEqualToString:kMessageTypeUrl] && [[HelperTools defaultsDB] boolForKey:@"ShowURLPreview"])
            [self showStatusText:NSLocalizedString(@"🔗 A Link", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
        else if([lastMessage.messageType isEqualToString:kMessageTypeGeo])
            [self showStatusText:NSLocalizedString(@"📍 A Location", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
        else if([lastMessage.messageType isEqualToString:kMessageTypeFiletransfer])
        {
            if(lastMessage.fileInfo.isImage)
                [self showStatusText:NSLocalizedString(@"📷 An Image", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            else if(lastMessage.fileInfo.isAudio)
                [self showStatusText:NSLocalizedString(@"🎵 An Audiomessage", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            else if(lastMessage.fileInfo.isVideo)
                [self showStatusText:NSLocalizedString(@"🎥 A Video", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            else if(lastMessage.fileInfo.isPDF)
                [self showStatusText:NSLocalizedString(@"📄 A Document", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            else
                [self showStatusText:NSLocalizedString(@"📁 A File", @"") inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
        }
        else
        {
            if([lastMessage.messageText hasPrefix:@"/me "])
            {
                NSString* replacedMessageText = [[MLXEPSlashMeHandler sharedInstance] stringSlashMeWithMessage:lastMessage];
                [self showStatusTextItalic:replacedMessageText withItalicRange:NSMakeRange(0, replacedMessageText.length)];
            }
            else
            {
                [self showStatusText:lastMessage.messageText inboundDir:lastMessage.inbound fromUser:senderOfLastGroupMsg];
            }
        }
    }
    else
    {
        [self showStatusText:nil inboundDir:NO fromUser:nil];
        self.time.hidden = YES;
    }
}

-(void) showStatusText:(NSString *) text inboundDir:(BOOL) inboundDir fromUser:(NSString* _Nullable) fromUser
{
    NSString* statusMessage = @"";
    if(inboundDir == NO)
        statusMessage = [NSString stringWithFormat:@"%@ ", NSLocalizedString(@"Me:", @"Prefix for own messages in chat overview")];
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
        self.pinBadge.hidden = NO;
    } else {
        self.pinBadge.hidden = YES;
    }
}

#pragma mark - date
-(NSString*) formattedDateWithSource:(NSDate*) sourceDate
{
    NSDateFormatter* dateFormatter = [NSDateFormatter new];
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
