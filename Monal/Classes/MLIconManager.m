//
//  MLIconManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/16/13.
//
//

#import "MLIconManager.h"

@implementation MLIconManager


+(void) setIconForContact:(NSString*) contact andAccount:(NSString*) accountNo WithData:(NSData*) data andFileName:(NSString*) fileName
{
    
/*vCardPhotoBinval=[NSString stringWithString:messageBuffer];
 messageBuffer =nil;
 
 NSString* extension=nil;
 // we have type and data..  save it
 if([vCardPhotoType isEqualToString:@"image/png"])
 {
 extension=@"png";
 }
 
 if([vCardPhotoType isEqualToString:@"image/jpeg"])
 {
 extension=@"jpg";
 }
 
 //	debug_NSLog(@"contents: %@",vCardPhotoBinval) ;
 
 
 debug_NSLog(@"saving file %@ ", vCardPhotoType);
 if((vCardUser!=nil)  && (extension!=nil))// prevent wrong user icon situation
 {
 NSString* filename=[NSString stringWithFormat:@"/buddyicons/%@.%@", vCardUser,extension];
 NSString* clean_filename=[NSString stringWithFormat:@"%@.%@", vCardUser,extension];
 
 
 
 NSFileManager* fileManager = [NSFileManager defaultManager];
 
 NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
 NSString *documentsDirectory = [paths objectAtIndex:0];
 NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:filename];
 //	debug_NSLog(@"see if file ther %@", filename);
 //if( ![fileManager fileExistsAtPath:writablePath])
 {
 // The buddy icon
 
 debug_NSLog(@"file: %@",writablePath) ;
 //[fileManager copyItemAtPath:defaultDBPath toPath:writableDBPath error:&error];
 if([[self dataWithBase64EncodedString:vCardPhotoBinval] writeToFile:writablePath
 atomically:NO
 ] )
 {
 debug_NSLog(@"wrote file");
 }
 else
 {
 debug_NSLog(@"failed to write");
 }
 
 
 //set db entry
 [db setIconName:vCardUser :accountNumber:clean_filename];
 
 }
 
*/

// check for exisitng file based on DB
//delete file
//make new file
//set in DB
    
    
    
}

+(UIImage*) getIconForContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    UIImage* toreturn=nil; 
    //get filname from DB
    
    //uiimage image named is cached if avaialable
    
    if(toreturn==nil)
    {
        toreturn=[UIImage imageNamed:@"noicon"];
    }
    
    return toreturn;
    
}

@end
