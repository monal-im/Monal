//
//  MLSoundManager.h
//  Monal
//
//  Created by 阿栋 on 3/6/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MLContact;

@interface MLSoundManager : NSObject


@property (nonatomic, strong) NSString* _Nullable selectedSound;


+(MLSoundManager* _Nonnull) sharedInstance;
- (void)saveSoundDataForContact:(MLContact* _Nullable) contact withSoundData:(NSData *)soundData;
- (void)deleteSoundData:(MLContact *_Nullable) contact;
- (NSString *)loadSoundURLForContact:(MLContact *_Nullable)contact;

@end

NS_ASSUME_NONNULL_END
