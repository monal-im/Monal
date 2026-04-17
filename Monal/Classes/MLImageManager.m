//
//  MLImageManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import <monalxmpp/MLImageManager.h>
#import <monalxmpp/MLXMPPManager.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/DataLayer.h>
#import "AESGcm.h"
#import <monalxmpp/UIColor+Extension.h>


@interface MLImageManager()
@property (nonatomic, strong) NSCache* iconCache;
@property (nonatomic, strong) NSString* documentsDirectory;
@property (nonatomic, strong) NSCache* backgroundCache;
@end

@implementation MLImageManager

#pragma mark initilization

+(MLImageManager*) sharedInstance
{
    static dispatch_once_t once;
    static MLImageManager* sharedInstance;
    dispatch_once(&once, ^{
        DDLogVerbose(@"Creating shared image manager instance...");
        sharedInstance = [MLImageManager new];
    });
    return sharedInstance;
}

//this mehod should *only* be used in the mainapp due to memory requirements for large images
+(UIImage*) circularImage:(UIImage*) image
{
    return [[[UIGraphicsImageRenderer alloc] initWithSize:image.size] imageWithActions:^(UIGraphicsImageRendererContext* _Nonnull rendererContext) {
        UIBezierPath* clipPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
        [clipPath addClip];
        
        //Flip coordinates before drawing image as UIKit and CoreGraphics have inverted coordinate system
        CGContextTranslateCTM(rendererContext.CGContext, 0, image.size.height);
        CGContextScaleCTM(rendererContext.CGContext, 1, -1);
        
        CGContextDrawImage(rendererContext.CGContext, CGRectMake(0, 0, image.size.width, image.size.height), image.CGImage);
    }];
}

+(UIImage*) image:(UIImage*) image withMucOverlay:(UIImage*) overlay
{
    UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat new];
    format.opaque = NO;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    format.scale = 1.0;
    CGRect drawRect = CGRectMake(0, 0, image.size.width, image.size.height);
    CGFloat overlaySize = (float)(image.size.width / 3);
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:drawRect.size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext* _Nonnull context __unused) {
        [image drawInRect:drawRect];
        CGRect overlayRect = CGRectMake(0,                  //renderer.format.bounds.size.width - overlaySize
                                        0,                  //renderer.format.bounds.size.height - overlaySize
                                        overlaySize,
                                        overlaySize);
        [overlay drawInRect:overlayRect];
    }];
}

-(id) init
{
    self = [super init];
    self.iconCache = [NSCache new];
    self.backgroundCache = [NSCache new];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    self.documentsDirectory = [[HelperTools getContainerURLForPathComponents:@[]] path];
    
    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"imagecache"];
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:nil];
    [HelperTools configureFileProtectionFor:writablePath];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMemoryPressureNotification) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    
    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) handleMemoryPressureNotification
{
    DDLogVerbose(@"Removing all objects in avatar cache due to memory pressure...");
    [self purgeCache];
}

#pragma mark cache

-(void) purgeCache
{
    [self.iconCache removeAllObjects];
    [self.backgroundCache removeAllObjects];
}

-(void) purgeCacheForContact:(NSString*) contact andAccount:(NSNumber*) accountID
{
    [self.iconCache removeObjectForKey:[NSString stringWithFormat:@"%@_%@", accountID, contact]];
    [self resetCachedBackgroundImageForContact:[MLContact createContactFromJid:contact andAccountID:accountID]];
}

-(void) purgeCacheForOccupant:(NSString*) occupantId inRoom:(NSString*) room
{
    [self.iconCache removeObjectForKey:[NSString stringWithFormat:@"%@_%@", room, occupantId]];
}

-(void) cleanupHashes
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSArray<MLContact*>* contactList = [[DataLayer sharedInstance] contactList];
    
    for(MLContact* contact in contactList)
    {
        NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
        writablePath = [writablePath stringByAppendingPathComponent:contact.accountID.stringValue];
        writablePath = [writablePath stringByAppendingPathComponent:[self fileNameforContact:contact]];
        NSString* hash = [[DataLayer sharedInstance] getAvatarHashForContact:contact.contactJid andAccount:contact.accountID];
        BOOL hasHash = ![@"" isEqualToString:hash];
        
        if(hasHash && ![fileManager isReadableFileAtPath:writablePath])
        {
            DDLogDebug(@"Deleting orphan hash '%@' of contact: %@", hash, contact);
            //delete avatar hash from db if the file containing our image data vanished
            [[DataLayer sharedInstance] setAvatarHash:@"" forContact:contact.contactJid andAccount:contact.accountID];
        }
        
        if(!hasHash && [fileManager isReadableFileAtPath:writablePath])
        {
            DDLogDebug(@"Deleting orphan avatar file '%@' of contact: %@", writablePath, contact);
            NSError* error;
            [fileManager removeItemAtPath:writablePath error:&error];
            if(error)
                DDLogError(@"Error deleting orphan avatar file: %@", error);
        }

        //clean up orphan hashes and orphan avatar files of muc participants
        if(contact.isMuc)
        {
            NSArray* participants = [[DataLayer sharedInstance] getMembersAndParticipantsOfMuc:contact.contactJid forAccountID:contact.accountID];
            //documents directory/muc_participant_avatars/accountID/room/occupantId
            NSString* rootPath = [self.documentsDirectory stringByAppendingPathComponent:@"muc_participant_avatars"];
            rootPath = [rootPath stringByAppendingPathComponent:contact.accountID.stringValue];
            rootPath = [rootPath stringByAppendingPathComponent:contact.contactJid];
            for(NSDictionary* participant in participants)
            {
                NSString* occupantId = participant[@"occupant_id"];
                if(occupantId == nil || [occupantId isEqualToString:@""])
                    continue;

                writablePath = [rootPath stringByAppendingPathComponent:[self fileNameForOccupant:occupantId]];
                hasHash = participant[@"iconhash"] != nil && ![@"" isEqualToString:participant[@"iconhash"]];

                if(hasHash && ![fileManager isReadableFileAtPath:writablePath])
                {
                    DDLogDebug(@"Deleting orphan hash '%@' of muc participant: %@/%@", participant[@"iconhash"], participant[@"room"], participant[@"room_nick"]);
                    //delete avatar hash from db if the file containing our image data vanished
                    [[DataLayer sharedInstance] clearAvatarHashForOccupant:occupantId inRoom:participant[@"room"] forAccount:contact.accountID];
                }

                if(!hasHash && [fileManager isReadableFileAtPath:writablePath])
                {
                    DDLogDebug(@"Deleting orphan avatar file '%@' of muc participant: %@/%@", writablePath, participant[@"room"], participant[@"room_nick"]);
                    NSError* error;
                    [fileManager removeItemAtPath:writablePath error:&error];
                    if(error)
                        DDLogError(@"Error deleting orphan avatar file: %@", error);
                }
            }
        }
    }
}

-(void) removeAllContactIcons
{
    NSError* error;
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    [fileManager removeItemAtPath:writablePath error:&error];
    if(error)
        DDLogError(@"Got error while trying to delete all contact avatar files: %@", error);
}

#pragma mark chat bubbles

-(UIImage*) inboundImage
{
    if(_inboundImage)
        return _inboundImage;
    _inboundImage = [[UIImage imageNamed:@"incoming"] resizableImageWithCapInsets:UIEdgeInsetsMake(6, 6, 6, 6)];
    return _inboundImage;
    
}

-(UIImage*) outboundImage
{
    if (_outboundImage)
        return _outboundImage;
    _outboundImage = [[UIImage imageNamed:@"outgoing"] resizableImageWithCapInsets:UIEdgeInsetsMake(6, 6, 6, 6)];
    return _outboundImage;
}

#pragma mark user icons

-(UIImage*) generatePlaceholderAvatarForString:(NSString*) inputString withInitial:(NSString*) initialCharacter
{
    MLAssert(initialCharacter != nil && initialCharacter.length == 1, @"initialCharacter string does not represent a character");

    UIColor* background = [HelperTools generateColorFromString:inputString];
    UIColor* foreground = [UIColor blackColor];
    if(![background isLightColor])
        foreground = [UIColor whiteColor];
    
    CGRect drawRect = CGRectMake(0, 0, 200, 200);
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:drawRect.size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        //make sure our image is circular
        [[UIBezierPath bezierPathWithOvalInRect:drawRect] addClip];
        
        //fill the background of our image
        [background setFill];
        [context fillRect:renderer.format.bounds];
        
        //draw letter in the middleof our image
        NSMutableParagraphStyle* paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        paragraphStyle.alignment = NSTextAlignmentCenter;
        NSDictionary* attributes = @{
            NSFontAttributeName: [[UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle] fontWithSize:(unsigned int)(drawRect.size.height / 1.666)],
            NSForegroundColorAttributeName: foreground,
            NSParagraphStyleAttributeName: paragraphStyle
        };
        CGSize textSize = [initialCharacter sizeWithAttributes:attributes];
        CGRect textRect = CGRectMake(floorf((float)(renderer.format.bounds.size.width - textSize.width) / 2),
                                    floorf((float)(renderer.format.bounds.size.height - textSize.height) / 2),
                                    textSize.width,
                                    textSize.height);
        [initialCharacter drawInRect:textRect withAttributes:attributes];
    }];
}

-(UIImage*) generateDummyIconForContact:(MLContact*) contact
{
    NSString* initial = [[contact.contactDisplayNameWithoutSelfnotesPrefix substringToIndex:1] uppercaseString];
    return [self generatePlaceholderAvatarForString:contact.contactJid withInitial:initial];
}

-(UIImage*) generatePlaceholderAvatarForNick:(NSString*) nick
{
    NSString* initial = [[nick substringToIndex:1] uppercaseString];
    return [self generatePlaceholderAvatarForString:nick withInitial:initial];
}

-(UIImage*) generatePlaceholderAvatarForOccupantId:(NSString*) occupantId andNick:(NSString*) nick
{
    NSString* initial = [[nick substringToIndex:1] uppercaseString];
    return [self generatePlaceholderAvatarForString:occupantId withInitial:initial];
}

-(NSString*) fileNameforContact:(MLContact*) contact
{
    return [NSString stringWithFormat:@"%@_%@.png", contact.accountID.stringValue, [contact.contactJid lowercaseString]];;
}

-(NSString*) fileNameForOccupant:(NSString*) occupantId
{
    // Replace forward slashes with "__" because a forward slash is a path separator
    NSString* escapedOccupantId = [occupantId stringByReplacingOccurrencesOfString:@"/" withString:@"__"];
    return [NSString stringWithFormat:@"%@.png", escapedOccupantId];
}

-(NSString*) fileNameforThumbnailOfMessage:(MLMessage*) message
{
    return [NSString stringWithFormat:@"%@.png", message.messageDBId.stringValue];
}

-(NSURL*) setThumbnailOfMessage:(MLMessage*) message withData:(NSData* _Nullable) data
{
    //documents directory/thumbnails/accountID/contact

    NSString* filename = [self fileNameforThumbnailOfMessage:message];

    NSFileManager* fileManager = [NSFileManager defaultManager];

    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"thumbnails"];
    writablePath = [writablePath stringByAppendingPathComponent:message.accountID.stringValue];
    writablePath = [writablePath stringByAppendingPathComponent:message.buddyName];
    NSError* error;
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:&error];
    [HelperTools configureFileProtectionFor:writablePath];
    writablePath = [writablePath stringByAppendingPathComponent:filename];

    if([fileManager fileExistsAtPath:writablePath])
        [fileManager removeItemAtPath:writablePath error:nil];

    if(data)
    {
        if([data writeToFile:writablePath atomically:NO])
        {
            [HelperTools configureFileProtectionFor:writablePath];
            DDLogVerbose(@"wrote image to file: %@", writablePath);
            return [NSURL fileURLWithPath:writablePath];
        }
        else
            DDLogError(@"failed to write image to file: %@", writablePath);
    }
    return (NSURL*)nil;
}

-(void) setIconForContact:(MLContact*) contact WithData:(NSData* _Nullable) data
{
    //documents directory/buddyicons/account no/contact
    
    NSString* filename = [self fileNameforContact:contact];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    NSString *writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    writablePath = [writablePath stringByAppendingPathComponent:contact.accountID.stringValue];
    NSError* error;
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:&error];
    [HelperTools configureFileProtectionFor:writablePath];
    writablePath = [writablePath stringByAppendingPathComponent:filename];
    
    if([fileManager fileExistsAtPath:writablePath])
        [fileManager removeItemAtPath:writablePath error:nil];

    if(data)
    {
        if([data writeToFile:writablePath atomically:NO])
        {
            [HelperTools configureFileProtectionFor:writablePath];
            DDLogVerbose(@"wrote image to file: %@", writablePath);
        }
        else
            DDLogError(@"failed to write image to file: %@", writablePath);
    }
    
    //remove from cache if its there
    [self.iconCache removeObjectForKey:[NSString stringWithFormat:@"%@_%@", contact.accountID, contact]];
}

-(void) setAvatarForOccupant:(NSString*) occupantId inRoom:(NSString*) room forAccount:(NSNumber*) accountID WithData:(NSData* _Nullable) data
{
    MLAssert(occupantId != nil && ![occupantId isEqualToString:@""], @"The occupantId can't be empty when saving MUC participant avatars");

    //documents directory/muc_participant_avatars/accountID/room/occupantId
    NSString* filename = [self fileNameForOccupant:occupantId];
    NSFileManager* fileManager = [NSFileManager defaultManager];

    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"muc_participant_avatars"];
    writablePath = [writablePath stringByAppendingPathComponent:accountID.stringValue];
    writablePath = [writablePath stringByAppendingPathComponent:room];

    NSError* error;
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:&error];
    [HelperTools configureFileProtectionFor:writablePath];
    writablePath = [writablePath stringByAppendingPathComponent:filename];

    if([fileManager fileExistsAtPath:writablePath])
        [fileManager removeItemAtPath:writablePath error:nil];

    if(data)
    {
        if([data writeToFile:writablePath atomically:NO])
        {
            [HelperTools configureFileProtectionFor:writablePath];
            DDLogVerbose(@"wrote image to file: %@", writablePath);
        }
        else
            DDLogError(@"failed to write image to file: %@", writablePath);
    }

    //remove from cache if its there
    [self purgeCacheForOccupant:occupantId inRoom:room];
}

-(BOOL) hasIconForContact:(MLContact*) contact
{
    NSString* filename = [self fileNameforContact:contact];
    
    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    writablePath = [writablePath stringByAppendingPathComponent:contact.accountID.stringValue];
    writablePath = [writablePath stringByAppendingPathComponent:filename];
    
    DDLogVerbose(@"Checking avatar image at: %@", writablePath);
    return [UIImage imageWithContentsOfFile:writablePath] != nil;
}

-(NSURL*) getThumbnailURLOfMessage:(MLMessage*) message
{
    NSString* path = [self.documentsDirectory stringByAppendingPathComponent:@"thumbnails"];
    path = [path stringByAppendingPathComponent:message.accountID.stringValue];
    path = [path stringByAppendingPathComponent:message.buddyName];
    NSString* filename = [self fileNameforThumbnailOfMessage:message];
    path = [path stringByAppendingPathComponent:filename];
    if([[NSFileManager defaultManager] fileExistsAtPath:path])
        return [NSURL fileURLWithPath:path];
    else
        return nil;
}

-(UIImage*) getIconForContact:(MLContact*) contact
{
    return [self getIconForContact:contact withCompletion:nil];
}

-(UIImage*) getIconForContact:(MLContact*) contact withCompletion:(void (^)(UIImage *))completion
{
    NSString* filename = [self fileNameforContact:contact];
    
    __block UIImage* toreturn = nil;
    //get filname from DB
    NSString* cacheKey = [NSString stringWithFormat:@"%@_%@", contact.accountID, contact.contactJid];
    
    //check cache
    toreturn = [self.iconCache objectForKey:cacheKey];
    if(!toreturn)
    {
        NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
        writablePath = [writablePath stringByAppendingPathComponent:contact.accountID.stringValue];
        writablePath = [writablePath stringByAppendingPathComponent:filename];
        
        DDLogVerbose(@"Loading avatar image at: %@", writablePath);
        UIImage* savedImage = [UIImage imageWithContentsOfFile:writablePath];
        if(savedImage)
            toreturn = savedImage;
        DDLogVerbose(@"Loaded image: %@", toreturn);
        
        if(toreturn == nil)             //return default avatar
        {
            DDLogVerbose(@"Using/generating dummy icon for contact: %@", contact);
            if(contact.isMuc)
            {
                if([kMucTypeChannel isEqualToString:contact.mucType])
                    toreturn = [MLImageManager circularImage:[UIImage imageNamed:@"noicon_channel" inBundle:nil compatibleWithTraitCollection:nil]];
                else
                    toreturn = [MLImageManager circularImage:[UIImage imageNamed:@"noicon_muc" inBundle:nil compatibleWithTraitCollection:nil]];
            }
            else
                toreturn = [self generateDummyIconForContact:contact];
        }
        else if(contact.isMuc)        //add group indicator overlay for non-default muc avatar
        {
            UIImage* overlay = nil;
            if([kMucTypeChannel isEqualToString:contact.mucType])
                overlay = [MLImageManager circularImage:[UIImage imageNamed:@"noicon_channel" inBundle:nil compatibleWithTraitCollection:nil]];
            else
                overlay = [MLImageManager circularImage:[UIImage imageNamed:@"noicon_muc" inBundle:nil compatibleWithTraitCollection:nil]];
            if(overlay)
                toreturn = [MLImageManager image:toreturn withMucOverlay:overlay];
        }
        
        //uiimage is cached if avaialable, but only if not in appex due to memory limits therein
        if(toreturn && ![HelperTools isAppExtension])
            [self.iconCache setObject:toreturn forKey:cacheKey];
        
        if(completion)
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(toreturn);
            });
    }
    else if(completion)
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(toreturn);
        });
    return toreturn;
}

-(UIImage*) getAvatarForOccupant:(NSString* _Nullable) occupantId inRoom:(NSString*) room havingNick:(NSString*) nick forAccount:(NSNumber*) accountID
{
    if(occupantId == nil || [occupantId isEqualToString:@""])
    {
        return [self generatePlaceholderAvatarForNick:nick];
    }

    NSString* filename = [self fileNameForOccupant:occupantId];

    UIImage* toreturn = nil;

    NSString* cacheKey = [NSString stringWithFormat:@"%@_%@", room, occupantId];

    //check cache
    toreturn = [self.iconCache objectForKey:cacheKey];
    if(!toreturn)
    {
        NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"muc_participant_avatars"];
        writablePath = [writablePath stringByAppendingPathComponent:accountID.stringValue];
        writablePath = [writablePath stringByAppendingPathComponent:room];
        writablePath = [writablePath stringByAppendingPathComponent:filename];

        DDLogVerbose(@"Loading avatar image at: %@", writablePath);
        UIImage* savedImage = [UIImage imageWithContentsOfFile:writablePath];

        if(savedImage)
            toreturn = savedImage;
        else
            toreturn = [self generatePlaceholderAvatarForOccupantId:occupantId andNick:nick];

        //uiimage is cached if avaialable, but only if not in appex due to memory limits therein
        if(toreturn && ![HelperTools isAppExtension])
            [self.iconCache setObject:toreturn forKey:cacheKey];
    }
    MLAssert(toreturn != nil, @"Returned avatar image can't be nil!");
    return toreturn;
}

-(void) saveBackgroundImageData:(NSData* _Nullable) data forContact:(MLContact* _Nullable) contact
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* writablePath;
    if(contact != nil)
    {
        NSString* filename = [self fileNameforContact:contact];
        writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"backgrounds"];
        
        [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:nil];
        [HelperTools configureFileProtectionFor:writablePath];
        
        writablePath = [writablePath stringByAppendingPathComponent:filename];
        if([fileManager fileExistsAtPath:writablePath])
            [fileManager removeItemAtPath:writablePath error:nil];
    }
    else
    {
        writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"background.jpg"];
        if([fileManager fileExistsAtPath:writablePath])
            [fileManager removeItemAtPath:writablePath error:nil];
    }
    [self resetCachedBackgroundImageForContact:contact];
    
    //file was deleted above, just don't create it again
    if(data != nil)
    {
        DDLogVerbose(@"Writing background image data %@ for %@ to '%@'...", data, contact, writablePath);
        [data writeToFile:writablePath atomically:YES];
        [HelperTools configureFileProtectionFor:writablePath];
    }
    
    //don't queue this notification because it should be handled immediately
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalBackgroundChanged object:contact];
}

-(UIImage* _Nullable) getBackgroundFor:(MLContact* _Nullable) contact
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* filename = @"background.jpg";
    if(contact != nil)
        filename = [self fileNameforContact:contact];
    UIImage* img = [self.backgroundCache objectForKey:filename];
    if(img != nil)
        return img;
    
    NSString* writablePath;
    if(contact != nil)
    {
        writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"backgrounds"];
        writablePath = [writablePath stringByAppendingPathComponent:filename];
        if(![fileManager fileExistsAtPath:writablePath])
            return nil;
    }
    else
    {
        writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"background.jpg"];
        if(![fileManager fileExistsAtPath:writablePath])
            return nil;
    }
    DDLogVerbose(@"Loading background image for %@ from '%@'...", contact, writablePath);
    img = [UIImage imageWithContentsOfFile:writablePath];
    DDLogVerbose(@"Got image: %@", img);
    [self.backgroundCache setObject:img forKey:filename];
    return img;
}

-(void) resetCachedBackgroundImageForContact:(MLContact* _Nullable) contact
{
    NSString* filename = @"background.jpg";
    if(contact != nil)
        filename = [self fileNameforContact:contact];
    [self.backgroundCache removeObjectForKey:filename];
}

@end
