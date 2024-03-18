//
//  MLSoundManager.h
//  Monal
//
//  Created by 阿栋 on 3/16/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MLContact;

@interface MLSoundManager : NSObject


@property (nonatomic, strong) NSString* _Nullable selectedSound;


+(MLSoundManager*) sharedInstance;
- (void)deleteSoundData:(MLContact *_Nullable) contact;
- (NSArray<NSString *> *)loadSoundFromResource;
- (NSString* )loadSoundNameForContact:(MLContact* _Nullable)contact;
- (NSString *)loadSoundURLForContact:(MLContact *_Nullable)contact;
- (void)saveSoundData:(NSData *)soundData AndWithSoundFileName:(NSString *)filename WithPrefix:(NSString *)prefix;

@end

NS_ASSUME_NONNULL_END
