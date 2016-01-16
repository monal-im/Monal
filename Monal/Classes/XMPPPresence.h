//
//  XMPPPresence.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/5/13.
//
//

#import "MLXMLNode.h"

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

@interface XMPPPresence : MLXMLNode
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
 brings a user back from being away
 */
-(void) setAvailable;

/**
 creates and sets the priority child
 */
-(void) setPriority:(NSInteger)priority;

/**
 creates and sets the show child
 */
-(void) setShow:(NSString*) showVal;


/**
 creates and sets the status child
 */
-(void) setStatus:(NSString*) status;

/**
 unsubscribes from presence notfiction
 */
-(void) unsubscribeContact:(NSString*) jid;

/**
 sets type unavilable.  there is no corresponding visibility call since any presence without unavailable will be visible. 
 */
-(void) setInvisible;

#pragma mark subscription
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

#pragma mark MUC
/**
 join specified room on server
 */
-(void) joinRoom:(NSString*) room withPassword:(NSString*) password onServer:(NSString*) server withName:(NSString*)name;

/**
 leave specified room
 */
-(void) leaveRoom:(NSString*) room onServer:(NSString*) server withName:(NSString*)name;

@end
