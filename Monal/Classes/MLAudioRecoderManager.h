//
//  MLAudioRecoderManager.h
//  Monal
//
//  Created by jimtsai (poormusic2001@gmail.com) on 2021/2/26.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <monalxmpp/HelperTools.h>

NS_ASSUME_NONNULL_BEGIN

@protocol AudioRecoderManagerDelegate

-(void) notifyResult:(BOOL) isSuccess error:(NSString* _Nullable) errorMsg;
-(void) notifyStart;
-(void) notifyStop:(NSURL* _Nullable) fileURL;
-(void) updateCurrentTime:(NSTimeInterval) audioDuration;
@end

@interface MLAudioRecoderManager : NSObject <AVAudioRecorderDelegate>

@property (strong, nonatomic) AVAudioRecorder* audioRecorder;
@property (weak, nonatomic) id<AudioRecoderManagerDelegate> recoderManagerDelegate;

+ (MLAudioRecoderManager* _Nonnull)sharedInstance;

-(void) start;
-(void) stop:(BOOL) shouldSend;

@property (nonatomic) NSString* currentPlayFilePath;

@end

NS_ASSUME_NONNULL_END
