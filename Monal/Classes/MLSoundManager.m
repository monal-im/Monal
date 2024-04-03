//
//  MLSoundManager.m
//  Monal
//
//  Created by 阿栋 on 3/29/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

#import "MLSoundManager.h"
#import "MLXMPPManager.h"
#import "HelperTools.h"
#import "DataLayer.h"

@interface MLSoundManager()
@property (nonatomic, strong) NSString* documentsDirectory;
@end

@implementation MLSoundManager

#pragma mark initilization

+(MLSoundManager*) sharedInstance
{
    static dispatch_once_t once;
    static MLSoundManager* sharedInstance;
    dispatch_once(&once, ^{
        DDLogVerbose(@"Creating shared sound manager instance...");
        sharedInstance = [MLSoundManager new];
    });
    return sharedInstance;
}

-(id) init
{
    self = [super init];
    if(self)
    {
        NSFileManager* fileManager = [NSFileManager defaultManager];
        NSURL* soundsDirectoryURL = [HelperTools getContainerURLForPathComponents:@[@"Library", @"Sounds"]];
        self.documentsDirectory = [soundsDirectoryURL path];
        [fileManager createDirectoryAtURL:soundsDirectoryURL withIntermediateDirectories:YES attributes:nil error:nil];
        [HelperTools configureFileProtectionFor:[soundsDirectoryURL path]];
        [self checkAndCreateAlertSoundsTable];
    }
    return self;
}

-(NSArray<NSString*>*) listBundledSounds
{
    NSString* resourcePath = [[NSBundle mainBundle] resourcePath];
    NSString* alertSoundsPath = [resourcePath stringByAppendingPathComponent:@"AlertSounds"];
    NSError* error;
    NSArray<NSString*>* soundFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:alertSoundsPath error:&error];
    if(error)
    {
        DDLogError(@"Error listing files in directory: %@", error.localizedDescription);
    }
    NSMutableArray<NSString*>* sounds = [[NSMutableArray alloc] init];
    for(NSString* file in soundFiles)
    {
        NSString* fileNameWithoutExtension = [file stringByDeletingPathExtension];
        [sounds addObject:fileNameWithoutExtension];
    }
    return [sounds copy];
}

- (NSString*) getSoundNameForSenderJID:(NSString*) senderJID andReceiverJID:(NSString*) receiverJID
{
    NSString *soundName = [[DataLayer sharedInstance] getSoundNameForAccountId:receiverJID buddyId:senderJID];
    if(soundName.length == 0)
    {
        soundName = [[DataLayer sharedInstance] getSoundNameForAccountId:@"Default" buddyId:senderJID];
        if(soundName.length == 0)
        {
            soundName = [[DataLayer sharedInstance] getSoundNameForAccountId:@"Default" buddyId:@"global"];
            if(soundName.length == 0)
            {
                return @"";
            }
        }
    }
    return soundName;
}


-(NSData*) getSoundDataForSenderJID:(NSString*) senderJID andReceiverJID:(NSString*) receiverJID
{
    return [[DataLayer sharedInstance] getSoundDataForAccountId:receiverJID buddyId:senderJID];
}

-(void) saveSoundData:(NSData*) soundData forSenderJID:(NSString*) senderJID andReceiverJID:(NSString*) receiverJID WithSoundFileName:(NSString*) filename isCustomSound:(NSNumber*)isCustom
{
    [[DataLayer sharedInstance] setAlertSoundWithAccountId:receiverJID buddyId:senderJID soundName:filename soundData:soundData isCustom:isCustom];
}

- (void) checkAndCreateAlertSoundsTable
{
    [[DataLayer sharedInstance] checkAndCreateAlertSoundsTable];
}

-(NSNumber*) getIsCustomSoundForAccountId:(NSString*) accountId buddyId:(NSString*) buddyId
{
    return [[DataLayer sharedInstance] getIsCustomSoundForAccountId:accountId buddyId:buddyId];
}

-(void) deleteContactForAccountId:(NSString*) accountId
{
    [[DataLayer sharedInstance] deleteSoundsForBuddyId:accountId];
}




@end

