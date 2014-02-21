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

static const int ddLogLevel = LOG_LEVEL_ERROR;

@interface MLImageManager()
@property  (nonatomic, strong) NSMutableArray* iconArray;
@property  (nonatomic, strong) UIImage* noIcon;

@end

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

#pragma mark cache

-(UIImage*) noIcon{
    if(!_noIcon) _noIcon=[UIImage imageNamed:@"noicon"];
    return _noIcon;
}

-(NSMutableArray*) iconArray
{
    if(!_iconArray) _iconArray=[[NSMutableArray alloc] init];
    return _iconArray;
}

-(void) purgeCache
{
    _iconArray=nil;
    _noIcon=nil;
}

-(void) cacheImage:(UIImage*) image withName:(NSString*) contact
{
    if([self.iconArray count]==20)
    {
        [self.iconArray removeObjectAtIndex:0]; //first in first out
    }
    
    NSDictionary* row = @{@"contact":contact,@"image":image };
    [self.iconArray addObject:row];
}


-(UIImage*) checkCacheForFile:(NSString*) contact
{
    for(NSDictionary* row in self.iconArray)
    {
        if([[row objectForKey:@"contact"] isEqualToString:contact]) {
            return [row objectForKey:@"image"];
        }
    }
    
    return nil;
}


-(void) unCacheFile:(NSString*) contact
{
    int counter=0;
    for(NSDictionary* row in self.iconArray)
    {
        if([[row objectForKey:@"contact"] isEqualToString:contact]) {
            [self.iconArray removeObjectAtIndex:counter];
            break;
        }
        counter++;
    }

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
        DDLogError(@"failed to write");
    }
    
    //remove from cache if its there
    [self unCacheFile:contact];
    
    //set db entry
    [[DataLayer sharedInstance] setIconName:filename forBuddy:contact inAccount:accountNo];
}

-(UIImage*) getIconForContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    UIImage* toreturn=nil; 
    //get filname from DB
    NSString* filename =  [[DataLayer sharedInstance] iconName:contact forAccount:accountNo];
    
    //check cache
    toreturn= [self checkCacheForFile:contact];
    if(!toreturn) {
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:@"buddyicons"];
        writablePath = [documentsDirectory stringByAppendingPathComponent:accountNo];
        writablePath = [documentsDirectory stringByAppendingPathComponent:filename];
        
        
        UIImage* savedImage =[UIImage imageWithContentsOfFile:writablePath];
        if(savedImage)
            toreturn=savedImage;
        
        if(toreturn==nil)
        {
            toreturn=self.noIcon;
        }
      
        //uiimage image named is cached if avaialable
        [self cacheImage:toreturn withName:contact];
        
    }
    
    return toreturn;
    
}

@end
