//
//  XMPPPresence.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/5/13.
//
//

#import "XMLNode.h"

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


#define kpresenceUnavailable @"unavailable"
#define kpresencesSubscribe @"subscribe"
#define kpresenceSubscribed @"subscribed"
#define kpresenceUnsubscribe @"unsubscribe"
#define kpresenceUnsubscribed @"unsubscribed"
#define kpresenceProbe @"probe"
#define kpresenceError @"error"

@interface XMPPPresence : XMLNode
{
    
}

@property (nonatomic,strong) NSString* versionHash;
@property (nonatomic,assign) NSInteger priority;

/**
 initialte with a version hash string
 */
-(id) initWithHash:(NSString*) version;

/**
 sets a show child with away
 */
-(void) setAway;

/**
 creates and sets the priority child
 */
-(void) setPriority:(NSInteger)priority;

/**
 creates and sets the show child
 */
-(void) setShow:(NSString*) showVal;

/**
 unsubscribes from presence notfiction
 */
-(void) unsubscribeContact:(NSString*) jid;

/**
 subscribes from presence notfiction
 */
-(void) subscribeContact:(NSString*) jid;

/**
allow subscription. Called in response to a remote request. 
 */
-(void) subscribedContact:(NSString*) jid;

/**
 do not allow subscription.Called in response to a remote request. 
 */
-(void) unsubscribedContact:(NSString*) jid;

@end
