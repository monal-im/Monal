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


@interface XMPPPresence : XMLNode
{
    
}

@property (nonatomic,strong) NSString* versionHash;
@property (nonatomic,assign) NSInteger priority;

/**
 initialte with a version hash string
 */
-(id) initWithHash:(NSString*) version;

-(void) setAway;
-(void) setClientPriority;

@end
