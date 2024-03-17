//
//  MLSoundManager.m
//  Monal
//
//  Created by 阿栋 on 3/16/24.
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
    }
    return self;
}

-(NSString*) fileNameforContact:(MLContact*) contact
{
    return [NSString stringWithFormat:@"chat_%@_%@.m4a", contact.accountId.stringValue, [contact.contactJid lowercaseString]];
}

-(NSString*) loadSoundURLForContact:(MLContact *_Nullable) contact
{
    NSString* userSoundKey;
    if(contact == nil)
    {
        userSoundKey = [NSString stringWithFormat:@"chat_global_AlertSoundFile"];
    }
    else
    {
        userSoundKey = [NSString stringWithFormat:@"chat_%@_AlertSoundFile", [contact.contactJid lowercaseString]];
    }
    NSString* filename = [[HelperTools defaultsDB] objectForKey:userSoundKey];
    if([filename hasSuffix:@"Custom"])
    {
        NSString* soundFilePath = [self.documentsDirectory stringByAppendingPathComponent:filename];
        NSFileManager* fileManager = [NSFileManager defaultManager];
        if([fileManager fileExistsAtPath:soundFilePath])
        {
            DDLogVerbose(@"The audio file was loaded successfully");
            return [self extractMiddleComponentFromString:soundFilePath];
        } 
        else
        {
            DDLogVerbose(@"The audio file does not exist");
        }
    }
    return nil;
}

-(void) saveSoundData:(NSData*) soundData AndWithSoundFileName:(NSString*) filename WithPrefix:(NSString*) prefix 
{
    if(soundData == nil)
    {
        DDLogVerbose(@"No audio data is provided.");
        return;
    }
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSError* error = nil;
    NSArray* contents = [fileManager contentsOfDirectoryAtPath:self.documentsDirectory error:&error];
    if(error)
    {
        DDLogDebug(@"Could not list directory contents: %@", error.localizedDescription);
        return;
    }
    for(NSString* file in contents)
    {
        if([file hasPrefix:prefix]) 
        {
            NSString* filePath = [self.documentsDirectory stringByAppendingPathComponent:file];
            BOOL success = [fileManager removeItemAtPath:filePath error:&error];
            if(!success)
            {
                DDLogDebug(@"Could not delete file: %@, error: %@", file, error.localizedDescription);
            }
            else
            {
                DDLogVerbose(@"Deleted file: %@", file);
            }
        }
    }
    NSString* targetPath = [self.documentsDirectory stringByAppendingPathComponent:filename];
    if([fileManager fileExistsAtPath:targetPath])
    {
        BOOL removed = [fileManager removeItemAtPath:targetPath error:&error];
        if(!removed && error)
        {
            DDLogVerbose(@"Failed to remove existing sound file: %@", error);
            return;
        }
    }
    BOOL success = [soundData writeToFile:targetPath options:NSDataWritingAtomic error:&error];
    if(success)
    {
        DDLogVerbose(@"Audio data written successfully to: %@", targetPath);
        [HelperTools configureFileProtectionFor:targetPath];
    } 
    else
    {
        DDLogVerbose(@"Failed to write audio data to file: %@", error);
    }
}



-(void) deleteSoundData:(MLContact *_Nullable) contact 
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSError* error = nil;
    NSString* prefix = [contact.contactJid lowercaseString];
    NSArray* contents = [fileManager contentsOfDirectoryAtPath:self.documentsDirectory error:&error];
    if(error)
    {
        DDLogDebug(@"Could not list directory contents: %@", error.localizedDescription);
        return;
    }
    for(NSString* file in contents)
    {
        if([file hasPrefix:prefix])
        {
            NSString* filePath = [self.documentsDirectory stringByAppendingPathComponent:file];
            BOOL success = [fileManager removeItemAtPath:filePath error:&error];
            if(!success)
            {
                DDLogDebug(@"Could not delete file: %@, error: %@", file, error.localizedDescription);
            }
            else
            {
                DDLogVerbose(@"Deleted file: %@", file);
            }
        }
    }
    NSString* globalSoundKey = [NSString stringWithFormat:@"chat_global_AlertSoundFile"];
    NSString* globalFilename = [[HelperTools defaultsDB] objectForKey:globalSoundKey];
    NSString* userSoundKey = [NSString stringWithFormat:@"chat_%@_AlertSoundFile",[contact.contactJid lowercaseString]];
    [[HelperTools defaultsDB] setObject:globalFilename forKey:userSoundKey];
    [[HelperTools defaultsDB] synchronize];
}

-(NSArray<NSString*>*) loadSoundFromResource 
{
    NSString* resourcePath = [[NSBundle mainBundle] resourcePath];
    NSString* alertSoundsPath = [resourcePath stringByAppendingPathComponent:@"AlertSounds"];
    NSError* error;
    NSArray<NSString*>* soundFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:alertSoundsPath error:&error];
    if(error)
    {
        DDLogDebug(@"Error listing files in directory: %@", error.localizedDescription);
    }
    NSMutableArray<NSString*>* sounds = [[NSMutableArray alloc] init];
    for(NSString* file in soundFiles)
    {
        NSString* fileNameWithoutExtension = [file stringByDeletingPathExtension];
        [sounds addObject:fileNameWithoutExtension];
    }
    return [sounds copy];
}

-(NSString*) loadSoundNameForContact:(MLContact* _Nullable) contact
{
    NSString* userSoundKey = [NSString stringWithFormat:@"chat_%@_AlertSoundFile", [contact.contactJid lowercaseString]];
    NSString* filename = [[HelperTools defaultsDB] objectForKey:userSoundKey];
    NSString* soundFilePath = [self.documentsDirectory stringByAppendingPathComponent:filename];
    NSFileManager* fileManager = [NSFileManager defaultManager];
    if(filename == nil || [filename isEqualToString:@""] || ![fileManager fileExistsAtPath:soundFilePath])
    {
        userSoundKey = @"chat_global_AlertSoundFile";
        filename = [[HelperTools defaultsDB] objectForKey:userSoundKey];
        return filename;
    }
    return filename;
}


-(NSString*) extractMiddleComponentFromString:(NSString*) string
{
    NSArray<NSString*>* components = [string componentsSeparatedByString:@"_"];
    if(components.count <= 2)
    {
        DDLogDebug(@"Format not recognized or missing sections.");
        return nil;
    }
    NSRange middleRange = NSMakeRange(1, components.count - 2);
    NSArray<NSString*>* middleComponents = [components subarrayWithRange:middleRange];
    NSString* extractedString = [middleComponents componentsJoinedByString:@"_"];
    return extractedString;
}

@end

