//
//  MLAudioRecoderManager.m
//  Monal
//
//  Created by jimtsai (poormusic2001@gmail.com) on 2021/2/26.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLAudioRecoderManager.h"

NSTimer *updateTimer = nil;
NSURL *audioFileURL = nil;

@implementation MLAudioRecoderManager

+(MLAudioRecoderManager*)sharedInstance
{
    static dispatch_once_t once;
    static MLAudioRecoderManager* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[MLAudioRecoderManager alloc] init] ;
    });
    return sharedInstance;
}

-(void) start
{
    id<AudioRecoderManagerDelegate> recoderManagerDelegate = self.recoderManagerDelegate;
    NSError *audioSessionCategoryError = nil;
    NSError *audioRecodSetActiveError = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryRecord error:&audioSessionCategoryError];
    [audioSession setActive:YES error:&audioRecodSetActiveError];
    if (audioSessionCategoryError) {
        DDLogError(@"Audio Recoder set category error: %@", audioSessionCategoryError);
        [recoderManagerDelegate notifyResult:NO error:NSLocalizedString(@"Audio Recoder set category error: %@", audioSessionCategoryError)];
        return;
    }
    
    if (audioRecodSetActiveError) {
        DDLogError(@"Audio Recoder set active error: %@", audioRecodSetActiveError);
        [recoderManagerDelegate notifyResult:NO error:NSLocalizedString(@"Audio Recoder set active error: %@", audioRecodSetActiveError)];
        return;
    }
    
    NSError* recoderError = nil;
    NSDictionary* recodSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                   [NSNumber numberWithInt:kAudioFormatMPEG4AAC] , AVFormatIDKey,
                                   [NSNumber numberWithInt:AVAudioQualityMin],AVEncoderAudioQualityKey,
                                   [NSNumber numberWithInt: 1], AVNumberOfChannelsKey,
                                   [NSNumber numberWithFloat:32000.0], AVSampleRateKey, nil];
    
    audioFileURL = [NSURL fileURLWithPath:[self getAudioPath]];
    
    self.audioRecorder = [[AVAudioRecorder alloc] initWithURL:audioFileURL settings:recodSettings error:&recoderError];
    
    if(recoderError)
    {
        [recoderManagerDelegate notifyResult:NO error:NSLocalizedString(@"Audio recoder init fail.", @"")];
        return;
    }
    self.audioRecorder.delegate = self;
    BOOL isPrepare = [self.audioRecorder prepareToRecord];
    
    if(!isPrepare)
    {
        [self.recoderManagerDelegate notifyResult:NO error:NSLocalizedString(@"Audio recoder prepareToRecord fail.", @"")];
        return;
    }
    BOOL isRecord = [self.audioRecorder record];
    
    if(!isRecord)
    {
        [self.recoderManagerDelegate notifyResult:NO error:NSLocalizedString(@"Audio recoder record fail.", @"")];
        return;
    }
    [recoderManagerDelegate notifyStart];
    updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateTimeInfo) userInfo:nil repeats:YES];
}

-(void)stop{
    [self.audioRecorder stop];
    
    [updateTimer invalidate];
    updateTimer = nil;
    [self.recoderManagerDelegate notifyStop:audioFileURL];
}

-(void)updateTimeInfo{
    [self.recoderManagerDelegate updateCurrentTime:self.audioRecorder.currentTime];
}

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag{
    if (flag) {
        [self.recoderManagerDelegate notifyResult:YES error:nil];
    } else {
        [self.recoderManagerDelegate notifyResult:NO error:NSLocalizedString(@"Audio Recoder recode fail", @"")];
        DDLogError(@"Audio Recoder recode fail");
    }
}

-(void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error{
    DDLogError(@"Audio Recoder EncodeError: %@", [error description]);
    [self.recoderManagerDelegate notifyResult:NO error:[error description]];
}

-(NSString *)getAudioPath{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString *documentsDirectory = [[fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup] path];

    NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:@"AudioRecordCache"];
    NSError *error = nil;
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:&error];
    [HelperTools configureFileProtectionFor:writablePath];
    if (error) {
        DDLogError(@"Audio Recoder create directory fail: %@", [error description]);
    }

    NSString *audioFilePath = [writablePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.aac",[[NSUUID UUID] UUIDString]]];
    return  audioFilePath;
}


@end
