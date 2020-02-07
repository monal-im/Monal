//
//  MLImageManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
@import UIKit;
#endif


@interface MLImageManager : NSObject  <NSURLSessionDownloadDelegate>



#if TARGET_OS_IPHONE
/**
 chatview inbound background image
 */
@property (nonatomic, strong) UIImage* _Nullable inboundImage;
/**
 chatview outbound background image
 */
@property (nonatomic, strong) UIImage* _Nullable outboundImage;

@property (nonatomic, strong) UIImage* _Nullable chatBackground;

#else

#endif


+ (MLImageManager* _Nonnull )sharedInstance;


/**
 Takes the string from the xmpp icon vcard info and stores it in an appropropriate place. 
 */
-(void) setIconForContact:(NSString*_Nonnull) contact andAccount:(NSString*_Nonnull) accountNo WithData:(NSString*_Nonnull) data ;

-(BOOL) saveBackgroundImageData:(NSData *_Nonnull) data;

#if TARGET_OS_IPHONE
/**
 retrieves a uiimage for the icon. returns noicon.png if nothing is found. never returns nil.
 */
-(void) getIconForContact:(NSString*_Nonnull) contact andAccount:(NSString *_Nonnull) accountNo withCompletion:(void (^_Nullable)(UIImage *_Nullable))completion;

-(UIImage *_Nullable) getBackground;

#else
/**
 retrieves a nsimage for the icon. returns noicon.png if nothing is found. never returns nil.
 */
-(void) getIconForContact:(NSString*) contact andAccount:(NSString *) accountNo withCompletion:(void (^)(NSImage *))completion;

#endif

-(void) imageForAttachmentLink:(NSString *_Nonnull) url withCompletion:(void (^_Nullable)(NSData * _Nullable data)) completionHandler;
-(void) imageURLForAttachmentLink:(NSString *_Nonnull) url withCompletion:(void (^_Nullable)(NSURL * _Nullable url)) completionHandler;

/**
 Purge cache in the event of  a memory warning
 */
-(void) purgeCache;

-(void) saveImageData:(NSData *) data forLink:(NSString *) link;
@end
