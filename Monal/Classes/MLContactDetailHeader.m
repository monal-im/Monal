//
//  MLContactDetailHeader.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/29/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLContactDetailHeader.h"
#import "MLContact.h"
#import "DataLayer.h"
#import "MLImageManager.h"

@interface MLContactDetailHeader()
@property (nonatomic, weak) IBOutlet UIImageView* buddyIconView;
@property (nonatomic, weak) IBOutlet UIImageView* background;
@property (nonatomic, weak) IBOutlet UILabel* jid;
@property (weak, nonatomic) IBOutlet UILabel* groupSubjectLabel;
@property (nonatomic, weak) IBOutlet UILabel* lastInteraction;
@property (nonatomic, weak) IBOutlet UILabel* isContact;

@property (nonatomic, weak) IBOutlet UIButton* muteButton;
@property (nonatomic, weak) IBOutlet UIButton* lockButton;
@property (nonatomic, weak) IBOutlet UIButton* phoneButton;
@end

@implementation MLContactDetailHeader

- (void)awakeFromNib {
    [super awakeFromNib];
   
    self.buddyIconView.layer.cornerRadius =  self.buddyIconView.frame.size.height / 2;
    self.buddyIconView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.buddyIconView.layer.borderWidth = 2.0f;
    self.buddyIconView.clipsToBounds = YES;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

-(void) loadContentForContact:(MLContact*) contact
{
    self.jid.text = contact.contactJid;

    // Set human readable lastInteraction field
    NSDate* lastInteractionDate = [[DataLayer sharedInstance] lastInteractionOfJid:contact.contactJid forAccountNo:contact.accountId];
    NSString* lastInteractionStr;
    if(lastInteractionDate.timeIntervalSince1970 > 0)
        lastInteractionStr = [NSDateFormatter localizedStringFromDate:lastInteractionDate dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
    else
        lastInteractionStr = NSLocalizedString(@"now", @"");
    self.lastInteraction.text = [NSString stringWithFormat:NSLocalizedString(@"Last seen: %@", @""), lastInteractionStr];

    [[MLImageManager sharedInstance] getIconForContact:contact.contactJid andAccount:contact.accountId withCompletion:^(UIImage* image) {
        self.buddyIconView.image = image;
    }];

    self.background.image = [UIImage imageNamed:@"Tie_My_Boat_by_Ray_Garcia"];

    if(contact.isMuted)
        [self.muteButton setImage:[UIImage systemImageNamed:@"moon.fill"] forState:UIControlStateNormal];
    else
        [self.muteButton setImage:[UIImage systemImageNamed:@"moon"] forState:UIControlStateNormal];

    if(contact.isEncrypted)
        [self.lockButton setImage:[UIImage imageNamed:@"744-locked-selected"] forState:UIControlStateNormal];
    else
        [self.lockButton setImage:[UIImage imageNamed:@"745-unlocked"] forState:UIControlStateNormal];

    [self updateSubscriptionLabel:contact];

    // hide phone button
    if(contact.isGroup == YES) {
        self.phoneButton.hidden = YES;
        self.isContact.hidden = YES;
        self.lockButton.hidden = YES;
    }
}

-(void) updateSubscriptionLabel:(MLContact*) contact {
    if(!contact.subscription || ![contact.subscription isEqualToString:kSubBoth]) {
        self.isContact.hidden = NO;

        NSString* subMessage;
        if([contact.subscription isEqualToString:kSubNone]){
            subMessage = NSLocalizedString(@"Neither can see keys.", @"");
        }
        else if([contact.subscription isEqualToString:kSubTo])
        {
             subMessage = NSLocalizedString(@"You can see their keys. They can't see yours", @"");
        }
        else if([contact.subscription isEqualToString:kSubFrom])
        {
             subMessage = NSLocalizedString(@"They can see your keys. You can't see theirs", @"");
        } else {
              subMessage = NSLocalizedString(@"Unknown Subcription", @"");
        }

        if([contact.ask isEqualToString:kAskSubscribe])
        {
            subMessage = [NSString  stringWithFormat:NSLocalizedString(@"%@ (Pending Approval)", @""), subMessage];
        }
        self.isContact.text = subMessage;
    } else  {
        self.isContact.hidden = YES;
    }
}

@end
