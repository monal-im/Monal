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

@property  (nonatomic, strong) NSCache *iconCache;
@property  (nonatomic, strong) NSCache *imageCache;

@property  (nonatomic, strong) NSOperationQueue *fileQueue;
@property  (nonatomic, strong) UIImage *noIcon;

@end

@implementation MLImageManager

#pragma mark initilization
+ (MLImageManager* )sharedInstance
{
    static dispatch_once_t once;
    static MLImageManager* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[MLImageManager alloc] init] ;
        NSFileManager* fileManager = [NSFileManager defaultManager];
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:@"imagecache"];
        NSError *error;
        [fileManager createDirectoryAtPath:writablePath withIntermediateDirectories:YES attributes:nil error:&error];
        
        //for notifications
        NSString *writablePath2 = [documentsDirectory stringByAppendingPathComponent:@"tempImage"];
        NSError *error2;
        [fileManager createDirectoryAtPath:writablePath2 withIntermediateDirectories:YES attributes:nil error:&error2];
        
    });
    return sharedInstance;
}


-(id) init
{
    self=[super init];
    self.fileQueue = [[NSOperationQueue alloc] init];
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

-(NSCache*) imageCache
{
    if(!_imageCache) _imageCache=[[NSCache alloc] init];
    return _iconCache;
}

-(void) purgeCache
{
    _iconCache=nil;
    _noIcon=nil;
    _imageCache=nil;
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

    if(data)
    {
        if([data writeToFile:writablePath atomically:NO])
            DDLogVerbose(@"wrote image to file");
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

-(void) filePathForURL:(NSString *)url wuthCompletion:(void (^)(NSString * _Nullable path)) completionHandler {
    NSString* path = [[DataLayer sharedInstance] imageCacheForUrl:url];
    if(completionHandler) completionHandler(path);
}

-(NSString *) savefilePathforURL:(NSString *)url {
    NSString *filename = [NSUUID UUID].UUIDString;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *writePath = [documentsDirectory stringByAppendingPathComponent:@"imagecache"];
    writePath = [writePath stringByAppendingPathComponent:filename];
    
    [[DataLayer sharedInstance] createImageCache:filename forUrl:url];
    
    return writePath;
}

-(NSString *) saveTempfilePathforURL:(NSString *)url {
    NSString *filename = [NSUUID UUID].UUIDString;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *writePath = [documentsDirectory stringByAppendingPathComponent:@"tempImage"];
    writePath = [writePath stringByAppendingPathComponent:filename];
    
    return writePath;
}

-(void) imageForAttachmentLink:(NSString *) url withCompletion:(void (^)(NSData * _Nullable data)) completionHandler
{
    NSData *cachedData = [self.imageCache objectForKey:url];
    if(cachedData) {
        if(completionHandler) completionHandler(cachedData);
    }
    
    [self filePathForURL:url wuthCompletion:^(NSString * _Nullable path) {
       
            if(path) {
                [self.fileQueue addOperationWithBlock:^{
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                NSString *documentsDirectory = [paths objectAtIndex:0];
                NSString *readPath = [documentsDirectory stringByAppendingPathComponent:@"imagecache"];
                readPath = [readPath stringByAppendingPathComponent:path];
                NSData *data =[NSData dataWithContentsOfFile:readPath];
                if(data) [self.imageCache setObject:data forKey:url];
                if(completionHandler) completionHandler(data);
                }];
            } else  {
                if ([url hasPrefix:@"aesgcm://"])
                {
                    [self attachmentDataFromEncryptedLink:url withCompletion:completionHandler];
                } else  {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSURLSession *session = [NSURLSession sharedSession];
                        NSURLSessionDownloadTask *task=[session downloadTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                            NSData *downloaded= [NSData dataWithContentsOfURL:location];
                            //cache data
                             [self.fileQueue addOperationWithBlock:^{
                            NSString *path =  [self savefilePathforURL:url];
                            [downloaded writeToFile:path atomically:YES];
                            if(downloaded)  [self.imageCache setObject:downloaded forKey:url];
                            if(completionHandler) completionHandler(downloaded);
                             }];
                        }];
                        
                        [task resume];
                    });
                }
            }
      
    }];

      //  return task.progress;
}

/**
 Writes once to the regular location and again to the temp location.
Provides temp url
 */
-(void) imageURLForAttachmentLink:(NSString *) url withCompletion:(void (^_Nullable)(NSURL * _Nullable path)) completionHandler
{
    [self filePathForURL:url wuthCompletion:^(NSString * _Nullable path) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if(path) {
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                NSString *documentsDirectory = [paths objectAtIndex:0];
                NSString *readPath = [documentsDirectory stringByAppendingPathComponent:@"imagecache"];
                readPath = [readPath stringByAppendingPathComponent:path];
                NSData *data =[NSData dataWithContentsOfFile:readPath];
                if(data) [self.imageCache setObject:data forKey:url];
                NSString *tempPath =  [self saveTempfilePathforURL:url];
                 [data writeToFile:tempPath atomically:YES];
                
                if(completionHandler) completionHandler([NSURL fileURLWithPath:tempPath]);
            } else  {
                if ([url hasPrefix:@"aesgcm://"])
                {
                    [self attachmentDataFromEncryptedLink:url withCompletion:^(NSData * _Nullable data) {
                        NSString *tempPath =  [self saveTempfilePathforURL:url];
                        [data writeToFile:tempPath atomically:YES];
                        if(completionHandler) completionHandler([NSURL fileURLWithPath:tempPath]);
                    }];
                } else  {
                    NSURLSession *session = [NSURLSession sharedSession];
                    [[session downloadTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                        NSData *downloaded= [NSData dataWithContentsOfURL:location];
                        //cache data
                        NSString *path =  [self savefilePathforURL:url];
                        [downloaded writeToFile:path atomically:YES];
                        
                        NSString *tempPath =  [self saveTempfilePathforURL:url];
                        [downloaded writeToFile:tempPath atomically:YES];
                        if(downloaded) [self.imageCache setObject:downloaded forKey:url];
                            if(completionHandler) completionHandler([NSURL fileURLWithPath:tempPath]);
                    }] resume];
                }
            }
        });
    }];
}

-(void) saveImageData:(NSData* _Nonnull) data forLink:(NSString* _Nonnull) link
{
    [self.fileQueue addOperationWithBlock:^{
        NSString *path =  [self savefilePathforURL:link];
        [data writeToFile:path atomically:YES];
        [self.imageCache setObject:data forKey:link];
    }];
}

- (void) attachmentDataFromEncryptedLink:(NSString *) link withCompletion:(void (^)(NSData * _Nullable data)) completionHandler {
    if ([link hasPrefix:@"aesgcm://"])
    {
        NSString *cleanLink= [link stringByReplacingOccurrencesOfString:@"aesgcm://" withString:@"https://"];
        NSArray *parts = [cleanLink componentsSeparatedByString:@"#"];
        if(parts.count>1) {
            NSString *url = parts[0];
            NSString *crypto = parts[1];
            if(crypto.length>=88) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    int ivLength=24;

                    NSString *ivHex =[crypto substringToIndex:ivLength];
                    //format is
                   //iv+32byte key
                    NSString *keyHex =[crypto substringWithRange:NSMakeRange(ivLength, 64)];
                    NSURLSession *session = [NSURLSession sharedSession];
                    [[session downloadTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                        
                        //decrypt
                        NSData *key = [HelperTools dataWithHexString:keyHex];
                        NSData *iv = [HelperTools dataWithHexString:ivHex];
                        
                        NSData *decrypted;
                        NSData *downloaded= [NSData dataWithContentsOfURL:location];
                        if(downloaded && downloaded.length>0 && key && iv) {
                            decrypted=[AESGcm decrypt:downloaded withKey:key andIv:iv withAuth:nil];
                            [self.fileQueue addOperationWithBlock:^{
                                                   NSString *path =  [self savefilePathforURL:link];
                                                   [decrypted writeToFile:path atomically:YES];
                                                   if(decrypted) [self.imageCache setObject:decrypted forKey:link];
                                                   if(completionHandler) completionHandler(decrypted);
                                                    }];
                        } else {
                            DDLogError(@"no data from aesgcm link, error %@", error);
                        }
                        
                    }] resume];
                });
                
            } else {
                DDLogError(@"aesgcm key and iv too short %@", link);
            }
        } else  {
            DDLogError(@"aesgcm url missing parts %@", link);
        }
    }
}


- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite{
    
}

@end
