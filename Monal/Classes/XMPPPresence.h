//
//  XMPPPresence.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/5/13.
//
//

#import <monalxmpp/XMPPStanza.h>
#import <monalxmpp/MLContact.h>

NS_ASSUME_NONNULL_BEGIN

/*
 pmuc-v1 = private muc
 voice-v1: indicates the user is capable of sending and receiving voice media.
 video-v1: indicates the user is capable of receiving video media.
 camera-v1: indicates the user is capable of sending video media.
 */

#define kextpmuc @"pmuc-v1"
#define kextvoice @"voice-v1"
#define kextvideo @"video-v1"
#define kextcamera @"camera-v1"

@interface XMPPPresence : XMPPStanza
{
    
}

-(void) setLastInteraction:(NSDate*) date;

/**
 initialte with a version hash string
 */
-(id) initWithHash:(NSString*) version;

/**
 sets a show child with away
 */
-(void) setAway;

/**
 brings a user back from being away
 */
-(void) setAvailable;

/**
 creates and sets the show child
 */
-(void) setShow:(NSString*) showVal;


/**
 creates and sets the status child
 */
-(void) setStatus:(NSString*) status;

#pragma mark subscription

/**
 unsubscribes from presence notfiction
 */
-(void) unsubscribeContact:(MLContact*) contact;

/**
 subscribes from presence notfiction
 */
-(void) subscribeContact:(MLContact*) contact;
-(void) subscribeContact:(MLContact*) contact withPreauthToken:(NSString* _Nullable) token;

/**
allow subscription. Called in response to a remote request. 
 */
-(void) subscribedContact:(MLContact*) contact;

/**
 do not allow subscription.Called in response to a remote request. 
 */
-(void) unsubscribedContact:(MLContact*) contact;

#pragma mark MUC

-(void) createRoom:(NSString*) room withNick:(NSString*) nick;

/**
 join specified room on server
 */
-(void) joinRoom:(NSString*) room withNick:(NSString*) nick;

/**
 leave specified room
 */
-(void) leaveRoom:(NSString*) room withNick:(NSString*) nick;

@end

NS_ASSUME_NONNULL_END
