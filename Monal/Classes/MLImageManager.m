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

-(id) init
{
    self = [super init];
    self.iconCache = [[NSCache alloc] init];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    self.documentsDirectory = [[fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup] path];
    
    NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"imagecache"];
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:nil];
    [HelperTools configureFileProtectionFor:writablePath];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMemoryPressureNotification) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    
    return self;
}

-(void) deinit
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
}

-(void) purgeCacheForContact:(NSString*) contact andAccount:(NSNumber*) accountNo
{
    [self.iconCache removeObjectForKey:[NSString stringWithFormat:@"%@_%@",accountNo,contact]];
}

-(void) cleanupHashes
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSArray<MLContact*>* contactList = [[DataLayer sharedInstance] contactList];
    
    for(MLContact* contact in contactList)
    {
        NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
        writablePath = [writablePath stringByAppendingPathComponent:contact.accountId.stringValue];
        writablePath = [writablePath stringByAppendingPathComponent:[self fileNameforContact:contact.contactJid]];
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
        CGRect textRect = CGRectMake(floorf((renderer.format.bounds.size.width - textSize.width) / 2),
                                    floorf((renderer.format.bounds.size.height - textSize.height) / 2),
                                    textSize.width,
                                    textSize.height);
        [contactLetter drawInRect:textRect withAttributes:attributes];
    }];
}

-(NSString*) fileNameforContact:(NSString*) contact
{
    return [NSString stringWithFormat:@"%@.png", [contact lowercaseString]];;
}

-(void) setIconForContact:(NSString*) contact andAccount:(NSNumber*) accountNo WithData:(NSData* _Nullable) data
{
    //documents directory/buddyicons/account no/contact
    
    NSString* filename = [self fileNameforContact:contact];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    NSString *writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    writablePath = [writablePath stringByAppendingPathComponent:accountNo.stringValue];
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
    [self.iconCache removeObjectForKey:[NSString stringWithFormat:@"%@_%@", accountNo, contact]];
    
}

-(UIImage*) getIconForContact:(MLContact*) contact
{
    return [self getIconForContact:contact withCompletion:nil];
}

-(UIImage*) getIconForContact:(MLContact*) contact withCompletion:(void (^)(UIImage *))completion
{
    NSString* filename = [self fileNameforContact:contact.contactJid];
    
    __block UIImage* toreturn = nil;
    //get filname from DB
    NSString* cacheKey = [NSString stringWithFormat:@"%@_%@", contact.accountId, contact.contactJid];
    
    //check cache
    toreturn = [self.iconCache objectForKey:cacheKey];
    if(!toreturn)
    {
        if(contact.isGroup)
            toreturn = [MLImageManager circularImage:([@"channel" isEqualToString:contact.mucType] ? [UIImage imageNamed:@"noicon_channel"] : [UIImage imageNamed:@"noicon_muc"])];
        else
        {
            NSString* writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
            writablePath = [writablePath stringByAppendingPathComponent:contact.accountId.stringValue];
            writablePath = [writablePath stringByAppendingPathComponent:filename];

            DDLogVerbose(@"Loading avatar image at: %@", writablePath);
            UIImage* savedImage = [UIImage imageWithContentsOfFile:writablePath];
            if(savedImage)
                toreturn = savedImage;
            DDLogVerbose(@"Loaded image: %@", toreturn);

            if(toreturn == nil)
            {
                DDLogVerbose(@"Generating dummy icon for contact: %@", contact);
                toreturn = [self generateDummyIconForContact:contact];
            }
        }
        
        //uiimage image named is cached if avaialable, but onlyif not in appex due to memory limits therein
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


-(BOOL) saveBackgroundImageData:(NSData*) data
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* documentsDirectory = [paths objectAtIndex:0];
    NSString* writablePath = [documentsDirectory stringByAppendingPathComponent:@"background.jpg"];
    
    if([fileManager fileExistsAtPath:writablePath])
        [fileManager removeItemAtPath:writablePath error:nil];
    
    return [data writeToFile:writablePath atomically:YES];
}

-(UIImage*) getBackground:(BOOL) forceReload
{
    //use cached image if possible
    if(self.chatBackground && forceReload == NO)
        return self.chatBackground;
    
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* documentsDirectory = [paths objectAtIndex:0];
    NSString* writablePath = [documentsDirectory stringByAppendingPathComponent:@"background.jpg"];
    return self.chatBackground = [UIImage imageWithContentsOfFile:writablePath];
}

-(void) resetBackgroundImage
{
    self.chatBackground = nil;
}

@end
