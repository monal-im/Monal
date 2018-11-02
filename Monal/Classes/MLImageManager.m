//
//  MLImageManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import "MLImageManager.h"
#import "EncodingTools.h"
#import "DataLayer.h"

#if TARGET_OS_IPHONE
#else
#import <Cocoa/Cocoa.h>
#endif

static const int ddLogLevel = LOG_LEVEL_ERROR;

@interface MLImageManager()

@property  (nonatomic, strong) NSCache* iconCache;
#if TARGET_OS_IPHONE
@property  (nonatomic, strong) UIImage* noIcon;
#else
@property  (nonatomic, strong) NSImage* noIcon;
#endif


@end

@implementation MLImageManager

#pragma mark initilization
+ (MLImageManager* )sharedInstance
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
    self=[super init];
   return self;
}

#pragma mark cache

#if TARGET_OS_IPHONE
-(UIImage*) noIcon{
    if(!_noIcon) _noIcon=[UIImage imageNamed:@"noicon"];
    return _noIcon;
}

#else
-(NSImage*) noIcon{
    if(!_noIcon){
        
    _noIcon=[NSImage imageNamed:@"noicon"];
    }
    return _noIcon;
}

#endif

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

#if TARGET_OS_IPHONE
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
#endif

#pragma mark user icons

-(NSString *) fileNameforContact:(NSString *) contact {
    return [NSString stringWithFormat:@"%@.png", [contact lowercaseString]];;
}

-(void) setIconForContact:(NSString*) contact andAccount:(NSString*) accountNo WithData:(NSString*) data
{
    if(!data) return; 
//documents directory/buddyicons/account no/contact
    
    NSString* filename= [self fileNameforContact:contact];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    writablePath = [writablePath stringByAppendingPathComponent:accountNo];
    NSError* error;
    [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:&error];
    writablePath = [writablePath stringByAppendingPathComponent:filename];
    
    if([fileManager fileExistsAtPath:writablePath])
    {
        [fileManager removeItemAtPath:writablePath error:nil];
    }
    
    if([[EncodingTools dataWithBase64EncodedString:data] writeToFile:writablePath atomically:NO] )
    {
        DDLogVerbose(@"wrote file");
    }
    else
    {
        DDLogError(@"failed to write");
    }
    
    //remove from cache if its there
    [self.iconCache removeObjectForKey:[NSString stringWithFormat:@"%@_%@",accountNo,contact]];
    
}


#if TARGET_OS_IPHONE

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
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsDirectory = [paths objectAtIndex:0];
            NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
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
#else

+ (NSImage*)circularImage:(NSImage *)image
{
    NSImage *composedImage = [[NSImage alloc] initWithSize:image.size] ;
    
    [composedImage lockFocus];
    NSBezierPath *clipPath = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, image.size.width, image.size.height)];
    [clipPath addClip];
    [image drawAtPoint:NSZeroPoint fromRect:NSMakeRect(0, 0, image.size.width, image.size.height) operation:NSCompositeSourceOver fraction:1];
    [composedImage unlockFocus];
    
    return composedImage;
}

-(void) getIconForContact:(NSString*) contact andAccount:(NSString *) accountNo withCompletion:(void (^)(NSImage *))completion
{
    NSString* filename=[self fileNameforContact:contact];
    NSString* cacheKey=[NSString stringWithFormat:@"%@_%@",accountNo,contact];
    //check cache
    __block NSImage* toreturn= [self.iconCache objectForKey:cacheKey];
    if(!toreturn) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsDirectory = [paths objectAtIndex:0];
            NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
            writablePath = [writablePath stringByAppendingPathComponent:accountNo];
            writablePath = [writablePath stringByAppendingPathComponent:filename];
            
            
            NSImage* savedImage =[[NSImage alloc] initWithContentsOfFile:writablePath];
            if(savedImage)
                toreturn=savedImage;
            
            if(!toreturn)
            {
                toreturn=self.noIcon;
            }
            
            toreturn=[MLImageManager circularImage:toreturn];
            
            
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
#endif


@end
