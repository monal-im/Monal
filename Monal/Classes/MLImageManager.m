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


@interface MLImageManager()
@property (nonatomic, strong) NSCache* iconCache;
@property (nonatomic, strong) UIImage* noIcon;
@property (nonatomic, strong) NSString* documentsDirectory;
@end

@implementation MLImageManager

#pragma mark initilization

+(MLImageManager*) sharedInstance
{
    static dispatch_once_t once;
    static MLImageManager* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[MLImageManager alloc] init] ;
    });
    return sharedInstance;
}


-(id) init
{
    self = [super init];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    self.documentsDirectory = [[fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup] path];
    
    NSString *writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"imagecache"];
    NSError *error;
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:&error];
    [HelperTools configureFileProtectionFor:writablePath];
    
    //for notifications
    NSString *writablePath2 = [self.documentsDirectory stringByAppendingPathComponent:@"tempImage"];
    NSError *error2;
    [fileManager createDirectoryAtPath:writablePath2 withIntermediateDirectories:YES attributes:nil error:&error2];
    [HelperTools configureFileProtectionFor:writablePath2];
    
    return self;
}

#pragma mark cache

-(UIImage*) noIcon{
    if(!_noIcon) _noIcon=[UIImage imageNamed:@"noicon"];
    return _noIcon;
}

-(NSCache*) iconCache
{
    if(!_iconCache) _iconCache=[[NSCache alloc] init];
    return _iconCache;
}

-(void) purgeCache
{
    _iconCache=nil;
    _noIcon=nil;
}


#pragma mark chat bubbles

-(UIImage *) inboundImage
{
 if (_inboundImage)
 {
     return _inboundImage;
 }
 
    _inboundImage=[[UIImage imageNamed:@"incoming"]
                   resizableImageWithCapInsets:UIEdgeInsetsMake(6, 6, 6, 6)];
    
    return _inboundImage;
    
}


-(UIImage*) outboundImage
{
    if (_outboundImage)
    {
        return _outboundImage;
    }
    
    _outboundImage=[[UIImage imageNamed:@"outgoing"]
                   resizableImageWithCapInsets:UIEdgeInsetsMake(6, 6, 6, 6)];
    
    return _outboundImage;
}

#pragma mark user icons

-(NSString *) fileNameforContact:(NSString *) contact {
    return [NSString stringWithFormat:@"%@.png", [contact lowercaseString]];;
}

-(void) setIconForContact:(NSString*) contact andAccount:(NSString*) accountNo WithData:(NSData* _Nullable) data
{
    //documents directory/buddyicons/account no/contact
    
    NSString* filename= [self fileNameforContact:contact];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    NSString *writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    writablePath = [writablePath stringByAppendingPathComponent:accountNo];
    NSError* error;
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:&error];
    [HelperTools configureFileProtectionFor:writablePath];
    writablePath = [writablePath stringByAppendingPathComponent:filename];
    
    if([fileManager fileExistsAtPath:writablePath])
    {
        [fileManager removeItemAtPath:writablePath error:nil];
    }

    if(data)
    {
        if([data writeToFile:writablePath atomically:NO])
        {
            [HelperTools configureFileProtectionFor:writablePath];
            DDLogVerbose(@"wrote image to file");
        }
        else
            DDLogError(@"failed to write image");
    }
    
    //remove from cache if its there
    [self.iconCache removeObjectForKey:[NSString stringWithFormat:@"%@_%@",accountNo,contact]];
    
}


+ (UIImage*)circularImage:(UIImage *)image
{
    UIImage *composedImage;
    UIGraphicsBeginImageContextWithOptions(image.size, NO, 0);
    UIBezierPath *clipPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    [clipPath addClip];
    // Flip coordinates before drawing image as UIKit and CoreGraphics have inverted coordinate system
    CGContextTranslateCTM(UIGraphicsGetCurrentContext(), 0, image.size.height);
    CGContextScaleCTM(UIGraphicsGetCurrentContext(), 1, -1);
    CGContextDrawImage(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, image.size.width, image.size.height), image.CGImage);
    composedImage= UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return composedImage;
}

-(void) getIconForContact:(NSString*) contact andAccount:(NSString*) accountNo withCompletion:(void (^)(UIImage *))completion
{
    NSString* filename=[self fileNameforContact:contact];
    
    __block UIImage* toreturn=nil;
    //get filname from DB
    NSString* cacheKey=[NSString stringWithFormat:@"%@_%@",accountNo,contact];
    
    //check cache
    toreturn= [self.iconCache objectForKey:cacheKey];
    if(!toreturn) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *writablePath = [self.documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
            writablePath = [writablePath stringByAppendingPathComponent:accountNo];
            writablePath = [writablePath stringByAppendingPathComponent:filename];
            
            
            UIImage* savedImage =[UIImage imageWithContentsOfFile:writablePath];
            if(savedImage)
                toreturn=savedImage;
            
            if(toreturn==nil)
            {
                toreturn=self.noIcon;
            }
            
            toreturn=[MLImageManager circularImage:toreturn];
            
            //uiimage image named is cached if avaialable
            if(toreturn) {
                [self.iconCache setObject:toreturn forKey:cacheKey];
            }
            
            if(completion)
            {
                completion(toreturn);
            }
            
        });
    }
    
    else if(completion)
    {
        completion(toreturn);
    }
    
}


-(BOOL) saveBackgroundImageData:(NSData *) data {
    NSFileManager* fileManager = [NSFileManager defaultManager];

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:@"background.jpg"];

    if([fileManager fileExistsAtPath:writablePath])
    {
        [fileManager removeItemAtPath:writablePath error:nil];
    }

    return [data writeToFile:writablePath atomically:YES];
}

-(UIImage *) getBackground
{
    if(self.chatBackground) return self.chatBackground;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:@"background.jpg"];
    
    self.chatBackground= [UIImage imageWithContentsOfFile:writablePath];
    
    return self.chatBackground;
}
/*
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite{
    
}
*/
@end
