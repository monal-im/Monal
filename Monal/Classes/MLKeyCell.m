//
//  MLKeyCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/30/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLKeyCell.h"
#import "HelperTools.h"
#import "MLSignalStore.h"

@implementation MLKeyCell

-(void)awakeFromNib
{
    [super awakeFromNib];
    // Initialization code
}

-(void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

-(void)initWithFingerprint:(NSData*) fingerprint andDeviceId:(long) deviceId andTrustLevel:(UInt16) trustLevel ownKey:(BOOL) ownKey andIndexPath:(NSIndexPath*)indexPath
{
    self.key.text = [HelperTools signalHexKeyWithSpacesWithData:fingerprint];
    self.toggle.on = trustLevel > MLOmemoNotTrusted;
    self.toggle.tag = 100 + indexPath.row;

    // set toggle color
    if(trustLevel == MLOmemoToFU)
        self.toggle.onTintColor = [UIColor yellowColor];
    else
        self.toggle.onTintColor = [UIColor greenColor];

    // show "removed from server" label if needed
    self.removedFromServerLabel.hidden = (trustLevel != MLOmemoTrustedButRemoved);

    // set cell background color if we have not seen messages in a long time from this device
    if (trustLevel == MLOmemoTrustedButNoMsgSeenInTime)
        self.backgroundColor = [UIColor redColor];
    else
        self.backgroundColor = nil;

    if(ownKey)
    {
        self.deviceid.text = [NSString stringWithFormat:NSLocalizedString(@"%ld (This device)", @""), deviceId];
    }
    else
    {
        self.deviceid.text = [NSString stringWithFormat:@"%ld", deviceId];
    }
}
@end
