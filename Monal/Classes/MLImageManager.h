//
//  MLImageManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import <Foundation/Foundation.h>

@import UIKit;
@class MLContact;
@class MLMessage;

@interface MLImageManager : NSObject

/**
 chatview inbound background image
 */
@property (nonatomic, strong) UIImage* _Nullable inboundImage;
/**
 chatview outbound background image
 */
@property (nonatomic, strong) UIImage* _Nullable outboundImage;


+(MLImageManager* _Nonnull) sharedInstance;
-(void) cleanupHashes;
-(void) removeAllContactIcons;

/**
 Takes the string from the xmpp icon vcard info and stores it in an appropropriate place. 
 */
-(void) setIconForContact:(MLContact* _Nonnull) contact WithData:(NSData* _Nullable) data;
-(void) setAvatarForOccupant:(NSString* _Nonnull) occupantId inRoom:(NSString* _Nonnull) room forAccount:(NSNumber* _Nonnull) accountID WithData:(NSData* _Nullable) data;

/**
 retrieves a uiimage for the icon. returns noicon.png if nothing is found. never returns nil.
 */
-(BOOL) hasIconForContact:(MLContact* _Nonnull) contact;
-(UIImage* _Nullable) getIconForContact:(MLContact* _Nonnull) contact withCompletion:(void (^_Nullable)(UIImage *_Nullable))completion;
-(UIImage* _Nullable) getIconForContact:(MLContact* _Nonnull) contact;
-(UIImage* _Nonnull) getAvatarForOccupant:(NSString* _Nullable) occupantId inRoom:(NSString* _Nonnull) room havingNick:(NSString* _Nonnull) nick forAccount:(NSNumber* _Nonnull) accountID;
+(UIImage* _Nonnull) circularImage:(UIImage* _Nonnull) image;

-(NSURL* _Nullable) getThumbnailURLOfMessage:(MLMessage* _Nonnull) message;
-(NSURL* _Nullable) setThumbnailOfMessage:(MLMessage* _Nonnull) message withData:(NSData* _Nullable) data;

-(void) saveBackgroundImageData:(NSData* _Nullable) data forContact:(MLContact* _Nullable) contact;
-(UIImage* _Nullable) getBackgroundFor:(MLContact* _Nullable) contact;

/**
 Purge cache in the event of  a memory warning
 */
-(void) purgeCache;
-(void) purgeCacheForContact:(NSString* _Nonnull) contact andAccount:(NSNumber* _Nonnull) accountID;

@end
