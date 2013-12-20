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

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

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

#pragma mark chat bubbles
-(UIImage *) inboundImage
{
 if (_inboundImage)
 {
     return _inboundImage;
 }
 
    _inboundImage=[[UIImage imageNamed:@"incoming"]
                   resizableImageWithCapInsets:UIEdgeInsetsMake(20, 30, 20, 30)];
    
    return _inboundImage;
    
}


-(UIImage*) outboundImage
{
    if (_outboundImage)
    {
        return _outboundImage;
    }
    
    _outboundImage=[[UIImage imageNamed:@"outgoing"]
                   resizableImageWithCapInsets:UIEdgeInsetsMake(20, 30, 20, 30)];
    
    return _outboundImage;
}
#pragma mark user icons

-(void) setIconForContact:(NSString*) contact andAccount:(NSString*) accountNo WithData:(NSString*) data
{
    if(!data) return; 
//documents directory/buddyicons/account no/contact
    
    NSString* filename=[NSString stringWithFormat:@"%@.png", [contact lowercaseString]];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    writablePath = [documentsDirectory stringByAppendingPathComponent:accountNo];
    writablePath = [documentsDirectory stringByAppendingPathComponent:filename];
    
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
        DDLogVerbose(@"failed to write");
    }
    
    //set db entry
    [[DataLayer sharedInstance] setIconName:filename forBuddy:contact inAccount:accountNo];
}

-(UIImage*) getIconForContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    UIImage* toreturn=nil; 
    //get filname from DB
    NSString* filename =  [[DataLayer sharedInstance] iconName:contact forAccount:accountNo];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
    writablePath = [documentsDirectory stringByAppendingPathComponent:accountNo];
    writablePath = [documentsDirectory stringByAppendingPathComponent:filename];
    
    
    UIImage* savedImage =[UIImage imageWithContentsOfFile:writablePath];
 if(savedImage)
     toreturn=savedImage;
    
    
    //uiimage image named is cached if avaialable
    
    if(toreturn==nil)
    {
        toreturn=[UIImage imageNamed:@"noicon"];
    }
    
 
    
    return toreturn;
    
}

@end
