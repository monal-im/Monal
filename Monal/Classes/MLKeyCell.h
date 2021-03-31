//
//  MLKeyCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/30/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLKeyCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UILabel* deviceid;
@property (nonatomic, weak) IBOutlet UILabel* key;
@property (nonatomic, weak) IBOutlet UISwitch* toggle;
@property (weak, nonatomic) IBOutlet UILabel* removedFromServerLabel;

-(void)initWithFingerprint:(NSData*) fingerprint andDeviceId:(long) deviceId andTrustLevel:(UInt16) trustLevel ownKey:(BOOL) ownKey andIndexPath:(NSIndexPath*)indexPath;

@end

NS_ASSUME_NONNULL_END
