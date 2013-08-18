//
//  MLIconManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import "MLIconManager.h"
#import "EncodingTools.h"
#import "DataLayer.h"

@implementation MLIconManager


+(void) setIconForContact:(NSString*) contact andAccount:(NSString*) accountNo WithData:(NSString*) data
{
    
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
        debug_NSLog(@"wrote file");
    }
    else
    {
        debug_NSLog(@"failed to write");
    }
    
    //set db entry
    [[DataLayer sharedInstance] setIconName:filename forBuddy:contact inAccount:accountNo];
}

+(UIImage*) getIconForContact:(NSString*) contact andAccount:(NSString*) accountNo
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
