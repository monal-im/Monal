//
//  MLImageManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import "MLImageManager.h"
#import "HelperTools.h"
#import "DataLayer.h"
#import "AESGcm.h"
#import "UIColor+Extension.h"


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
        sharedInstance = [[MLImageManager alloc] init];
    });
    return sharedInstance;
}

//this mehod should *only* be used in the mainapp due to memory requirements for large images
+(UIImage*) circularImage:(UIImage*) image
{
    UIImage* composedImage;
    UIGraphicsBeginImageContextWithOptions(image.size, NO, 0);
    
    UIBezierPath* clipPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    [clipPath addClip];
    
    // Flip coordinates before drawing image as UIKit and CoreGraphics have inverted coordinate system
    CGContextTranslateCTM(UIGraphicsGetCurrentContext(), 0, image.size.height);
    CGContextScaleCTM(UIGraphicsGetCurrentContext(), 1, -1);
    
    CGContextDrawImage(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, image.size.width, image.size.height), image.CGImage);
    composedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return composedImage;
}

+(UIImage*) image:(UIImage*) image withMucOverlay:(UIImage*) overlay
{
    UIGraphicsImageRendererFormat* format = [[UIGraphicsImageRendererFormat alloc] init];
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
    self.iconCache = [[NSCache alloc] init];
    self.backgroundCache = [[NSCache alloc] init];
    
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

-(void) purgeCacheForContact:(NSString*) contact andAccount:(NSNumber*) accountNo
{
    [self.iconCache removeObjectForKey:[NSString stringWithFormat:@"%@_%@", accountNo, contact]];
    [self resetCachedBackgroundImageForContact:[MLContact createContactFromJid:contact andAccountNo:accountNo]];
}

-(void) cleanupHashes
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSArray<MLContact*>* contactList = [[DataLayer sharedInstance] contactList];
    
    for(MLContact* contact in contactList)
    {
        NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
        writablePath = [writablePath stringByAppendingPathComponent:contact.accountId.stringValue];
        writablePath = [writablePath stringByAppendingPathComponent:[self fileNameforContact:contact]];
        NSString* hash = [[DataLayer sharedInstance] getAvatarHashForContact:contact.contactJid andAccount:contact.accountId];
        BOOL hasHash = ![@"" isEqualToString:hash];
        
        if(hasHash && ![fileManager isReadableFileAtPath:writablePath])
        {
            DDLogDebug(@"Deleting orphan hash '%@' of contact: %@", hash, contact);
            //delete avatar hash from db if the file containing our image data vanished
            [[DataLayer sharedInstance] setAvatarHash:@"" forContact:contact.contactJid andAccount:contact.accountId];
        }
        
        if(!hasHash && [fileManager isReadableFileAtPath:writablePath])
        {
            DDLogDebug(@"Deleting orphan avatar file '%@' of contact: %@", writablePath, contact);
            NSError* error;
            [fileManager removeItemAtPath:writablePath error:&error];
            if(error)
                DDLogError(@"Error deleting orphan avatar file: %@", error);
        }
    }
}

-(void) removeAllIcons
{
    NSError* error;
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    [fileManager removeItemAtPath:writablePath error:&error];
    if(error)
        DDLogError(@"Got error while trying to delete all avatar files: %@", error);
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

-(UIImage*) generateDummyIconForContact:(MLContact*) contact
{
    NSString* contactLetter = [[[contact contactDisplayName] substringToIndex:1] uppercaseString];
    UIColor* background = [HelperTools generateColorFromJid:contact.contactJid];
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
        CGSize textSize = [contactLetter sizeWithAttributes:attributes];
        CGRect textRect = CGRectMake(floorf((float)(renderer.format.bounds.size.width - textSize.width) / 2),
                                    floorf((float)(renderer.format.bounds.size.height - textSize.height) / 2),
                                    textSize.width,
                                    textSize.height);
        [contactLetter drawInRect:textRect withAttributes:attributes];
    }];
}

-(NSString*) fileNameforContact:(MLContact*) contact
{
    return [NSString stringWithFormat:@"%@_%@.png", contact.accountId.stringValue, [contact.contactJid lowercaseString]];;
}

-(void) setIconForContact:(MLContact*) contact WithData:(NSData* _Nullable) data
{
    //documents directory/buddyicons/account no/contact
    
    NSString* filename = [self fileNameforContact:contact];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    NSString *writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    writablePath = [writablePath stringByAppendingPathComponent:contact.accountId.stringValue];
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
    [self.iconCache removeObjectForKey:[NSString stringWithFormat:@"%@_%@", contact.accountId, contact]];
    
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
    NSString* cacheKey = [NSString stringWithFormat:@"%@_%@", contact.accountId, contact.contactJid];
    
    //check cache
    toreturn = [self.iconCache objectForKey:cacheKey];
    if(!toreturn)
    {
        NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
        writablePath = [writablePath stringByAppendingPathComponent:contact.accountId.stringValue];
        writablePath = [writablePath stringByAppendingPathComponent:filename];
        
        DDLogVerbose(@"Loading avatar image at: %@", writablePath);
        UIImage* savedImage = [UIImage imageWithContentsOfFile:writablePath];
        if(savedImage)
            toreturn = savedImage;
        DDLogVerbose(@"Loaded image: %@", toreturn);
        
        if(toreturn == nil)             //return default avatar
        {
            DDLogVerbose(@"Using/generating dummy icon for contact: %@", contact);
            if(contact.isGroup)
            {
                if([@"channel" isEqualToString:contact.mucType])
                    toreturn = [MLImageManager circularImage:[UIImage imageNamed:@"noicon_channel" inBundle:nil compatibleWithTraitCollection:nil]];
                else
                    toreturn = [MLImageManager circularImage:[UIImage imageNamed:@"noicon_muc" inBundle:nil compatibleWithTraitCollection:nil]];
            }
            else
                toreturn = [self generateDummyIconForContact:contact];
        }
        else if(contact.isGroup)        //add group indicator overlay for non-default muc avatar
        {
            UIImage* overlay = nil;
            if([@"channel" isEqualToString:contact.mucType])
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
