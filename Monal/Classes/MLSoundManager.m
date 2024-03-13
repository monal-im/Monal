//
//  MLSoundManager.m
//  Monal
//
//  Created by 阿栋 on 3/6/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

#import "MLSoundManager.h"
#import "HelperTools.h"
#import "MLContact.h"

@interface MLSoundManager()
@property (nonatomic, strong) NSString* documentsDirectory;
@property (nonatomic, strong) NSCache* soundCache;
@end

@implementation MLSoundManager

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
    if (self) {
        NSFileManager* fileManager = [NSFileManager defaultManager];
        NSURL *soundsDirectoryURL = [HelperTools getContainerURLForPathComponents:@[@"Library", @"Sounds"]];
        self.documentsDirectory = [soundsDirectoryURL path];
        [fileManager createDirectoryAtURL:soundsDirectoryURL withIntermediateDirectories:YES attributes:nil error:nil];
        [HelperTools configureFileProtectionFor:[soundsDirectoryURL path]];
    }
    return self;
}

-(NSString*) fileNameforContact:(MLContact*) contact
{
    return [NSString stringWithFormat:@"chat_%@_%@.m4a", contact.accountId.stringValue, [contact.contactJid lowercaseString]];
}

- (NSString *)loadSoundURLForContact:(MLContact *_Nullable)contact {
    NSString *soundName;
    if (contact == nil) {
        soundName = @"Sound.m4a";
    } else {
        soundName = [self fileNameforContact:contact];
    }
    NSString *soundFilePath = [self.documentsDirectory stringByAppendingPathComponent:soundName];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if ([fileManager fileExistsAtPath:soundFilePath]) {
        DDLogVerbose(@"The audio file was loaded successfully");
        return soundFilePath;
    } else {
        DDLogVerbose(@"The audio file does not exist");
        return nil;
    }
}

- (void)saveSoundDataForContact:(MLContact* _Nullable) contact withSoundData:(NSData *)soundData {
    // 检查音频数据是否为空
    if (soundData == nil) {
        DDLogVerbose(@"No audio data is provided.");
        return;
    }
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* targetPath;
    NSError *error = nil;

    if (contact == nil) {
        targetPath = [self.documentsDirectory stringByAppendingPathComponent:@"Sound.m4a"];
    } else {
        NSString* filename = [self fileNameforContact:contact];
        targetPath = [self.documentsDirectory stringByAppendingPathComponent:filename];
        if ([fileManager fileExistsAtPath:targetPath]) {
            BOOL removed = [fileManager removeItemAtPath:targetPath error:&error];
            if (!removed && error) {
                DDLogVerbose(@"Failed to remove existing sound file: %@", error);
                return;
            }
        }
    }

    BOOL success = [soundData writeToFile:targetPath options:NSDataWritingAtomic error:&error];
    if (success) {
        DDLogVerbose(@"Audio data written successfully to: %@", targetPath);
        [HelperTools configureFileProtectionFor:targetPath];
    } else {
        DDLogVerbose(@"Failed to write audio data to file: %@", error);
    }
}


- (void)deleteSoundData:(MLContact *_Nullable) contact {
    NSString *soundName;
    if (contact == nil) {
        soundName = @"Sound.m4a";
    } else {
        soundName = [self fileNameforContact:contact];
    }
    NSString *soundFilePath = [self.documentsDirectory stringByAppendingPathComponent:soundName];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError* error = nil;
    if ([fileManager removeItemAtPath:soundFilePath error:&error]) {
        DDLogVerbose(@"The audio file was deleted successfully: %@", soundFilePath);
    } else if (error) {
        DDLogVerbose(@"Failed to delete audio file: %@", error.localizedDescription);
    } else {
        DDLogVerbose(@"The audio file does not exist: %@", soundFilePath);
    }
}

@end
