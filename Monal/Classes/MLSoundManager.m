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
    NSFileManager* fileManager = [NSFileManager defaultManager];
    self.documentsDirectory = [[HelperTools getContainerURLForPathComponents:@[]] path];
    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"Library/Sounds/"];
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:nil];
    [HelperTools configureFileProtectionFor:writablePath];
    
    return self;
}

- (void)saveSoundData:(NSData* _Nullable)data{
    if (data == nil) {
        DDLogVerbose(@"No audio data is provided.");
        return;
    }

    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* libraryPath = [self.documentsDirectory stringByAppendingPathComponent:@"Library/Sounds/"];
    NSString* writablePath = [libraryPath stringByAppendingPathComponent:@"Sound.m4a"];
    
    if (![fileManager fileExistsAtPath:libraryPath]) {
        [fileManager createDirectoryAtPath:libraryPath withIntermediateDirectories:YES attributes:nil error:nil];
    }

    if ([fileManager fileExistsAtPath:writablePath]) {
        [fileManager removeItemAtPath:writablePath error:nil];
    }
    
    DDLogVerbose(@"Writing sound data %@ for %@ '...", data, writablePath);
    if ([data writeToFile:writablePath atomically:YES]) {
        DDLogVerbose(@"Writing sound data Successfully: %@", writablePath);
        [HelperTools configureFileProtectionFor:writablePath];
    } else {
        DDLogVerbose(@"Writing sound data failure: %@", writablePath);
    }
}

- (NSString *)loadSoundURL {
    NSString *libraryPath = [self.documentsDirectory stringByAppendingPathComponent:@"Library/Sounds/"];
    NSString *soundFilePath = [libraryPath stringByAppendingPathComponent:@"Sound.m4a"];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if ([fileManager fileExistsAtPath:soundFilePath]) {
        DDLogVerbose(@"The audio file was loaded successfully");
        return soundFilePath;
    } else {
        DDLogVerbose(@"The audio file does not exist");
        return nil;
    }
}

- (void)deleteSoundData {
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* libraryPath = [self.documentsDirectory stringByAppendingPathComponent:@"Library/Sounds"]; // 获取Library目录
    NSString* soundFilePath = [libraryPath stringByAppendingPathComponent:@"Sound.m4a"];

    if ([fileManager fileExistsAtPath:soundFilePath]) {
        NSError* error = nil;

        if ([fileManager removeItemAtPath:soundFilePath error:&error]) {
            DDLogVerbose(@"The audio file was deleted successfully: %@", soundFilePath);
        } else {
            DDLogVerbose(@"Failed to delete audio file: %@", error.localizedDescription);
        }
    } else {
        DDLogVerbose(@"The audio file does not exist: %@", soundFilePath);
    }
}




@end
