//
//  MLContactsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLContactsViewController.h"
#import "MLContactsCell.h"
#import "MLConstants.h"
#import "DataLayer.h"
#import "MLXMPPManager.h"
#import "DDLog.h"
#import "MLChatViewController.h"

#define kinfoSection 0
#define konlineSection 1
#define kofflineSection 2

@interface MLContactsViewController ()

@property (nonatomic, strong) NSMutableArray* infoCells;
@property (nonatomic, strong) NSMutableArray* contacts;
@property (nonatomic, strong) NSMutableArray* offlineContacts;

@property (nonatomic, weak) MLChatViewController *chatViewController;

@end

@implementation MLContactsViewController

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //for some reason i can't set this in the UI editor.
    self.contactsTable.backgroundColor= [NSColor clearColor];
    
  //  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    
    self.contacts=[[NSMutableArray alloc] init] ;
    self.offlineContacts=[[NSMutableArray alloc] init] ;
    self.infoCells=[[NSMutableArray alloc] init] ;
    
    [MLXMPPManager sharedInstance].contactVC=self;
    [self.contactsTable reloadData];
    
}

-(void) viewDidAppear
{
    [super viewDidAppear];
    
    if([self.parentViewController isKindOfClass:[NSSplitViewController class]])
    {
        NSArray *splitViewItems = ((NSSplitViewController *) self.parentViewController ).splitViewItems;
        if([splitViewItems count]>1)
        {
            NSSplitViewItem *otherItem = [splitViewItems objectAtIndex:1];
            self.chatViewController = (MLChatViewController *)otherItem.viewController;
        }
    }
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}



#pragma mark --   updating user display

-(BOOL) positionOfOnlineContact:(NSDictionary *) user
{
    NSInteger pos=0;
    for(NSDictionary* row in self.contacts)
    {
        if([[row objectForKey:kContactName] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
           [[row objectForKey:kAccountID]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
        {
            return pos;
        }
        pos++;
    }
    
    return -1;
    
}

-(BOOL) positionOfOfflineContact:(NSDictionary *) user
{
    NSInteger pos=0;
    for(NSDictionary* row in self.offlineContacts)
    {
        if([[row objectForKey:kContactName] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
           [[row objectForKey:kAccountID]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
        {
            
            return pos;
        }
        pos++;
    }
    
    return  -1;
    
}

-(void) addOnlineUser:(NSDictionary*) user
{
    //mutex to prevent others from modifying contacts at the same time
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       //check if already there
                       int pos=-1;
                       int offlinepos=-1;
                       int counter=0;
                       for(NSDictionary* row in _contacts)
                       {
                           if([[row objectForKey:kContactName] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
                              [[row objectForKey:kAccountID]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
                           {
                               pos=counter;
                               break;
                           }
                           counter++;
                       }
                       
                       
                       if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                       {
                           counter=0;
                           for(NSDictionary* row in _offlineContacts)
                           {
                               if([[row objectForKey:kContactName] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
                                  [[row objectForKey:kAccountID]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
                               {
                                   offlinepos=counter;
                                   break;
                               }
                               counter++;
                           }
                       }
                       
                       //not there
                       if(pos<0)
                       {
                           //insert into tableview
                           // for now just online
                           [[DataLayer sharedInstance] contactForUsername:[user objectForKey:kusernameKey] forAccount:[user objectForKey:kaccountNoKey] withCompletion:^(NSArray * contactRow) {
                               
                               dispatch_async(dispatch_get_main_queue(),
                                              ^{
                                                  if(!(contactRow.count>=1))
                                                  {
                                                      DDLogError(@"ERROR:could not find contact row");
                                                      return;
                                                  }
                                                  
                                                  NSInteger onlinepos= [self positionOfOnlineContact:user];
                                                  if(onlinepos>=0)
                                                  {
                                                      
                                                      DDLogVerbose(@"user %@ already in list",[user objectForKey:kusernameKey]);
                                             
                                                      return;
                                                  }
                                                  //insert into datasource
                                                  [_contacts insertObject:[contactRow objectAtIndex:0] atIndex:0];
                                                  
                                                  if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                                                  {
                                                      if(offlinepos>=0 && offlinepos<[_offlineContacts count])
                                                      {
                                                          [_offlineContacts removeObjectAtIndex:offlinepos];
                                                      }
                                                  }
                                                  
                                                  //sort
                                                  NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:kContactName  ascending:YES];
                                                  NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
                                                  [_contacts sortUsingDescriptors:sortArray];
                                                  
                                                  //find where it is
                                                  int pos=0;
                                                  int counter=0;
                                                  for(NSDictionary* row in _contacts)
                                                  {
                                                      if([[row objectForKey:kContactName] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
                                                         [[row objectForKey:kAccountID]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
                                                      {
                                                          pos=counter;
                                                          break;
                                                      }
                                                      counter++;
                                                  }
                                                  DDLogVerbose(@"sorted contacts %@", _contacts);
                                                  
                                                  DDLogVerbose(@"inserting %@ at pos %d", [_contacts objectAtIndex:pos], pos);
                                                  [_contactsTable beginUpdates];
                                                  NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:pos] ;
                                                  [self.contactsTable insertRowsAtIndexes:indexSet withAnimation:NSTableViewAnimationEffectFade];
                                                  
//                                                  if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
//                                                  {
//                                                      if(offlinepos>=0 && offlinepos<[_offlineContacts count])
//                                                      {
//                                                          NSIndexPath *path2 = [NSIndexPath indexPathForRow:offlinepos inSection:kofflineSection];
//                                                          [self.contactsTable deleteRowsAtIndexPaths:@[path2]
//                                                                                withRowAnimation:UITableViewRowAnimationFade];
//                                                      }
//                                                  }
                                                  [self.contactsTable endUpdates];
                                              });
                           }];
                           
                           
                       }else
                       {
                           DDLogVerbose(@"user %@ already in list",[user objectForKey:kusernameKey]);
                           if([user objectForKey:kstateKey])
                               [[_contacts objectAtIndex:pos] setObject:[user objectForKey:kstateKey] forKey:kstateKey];
                           if([user objectForKey:kstatusKey])
                               [[_contacts objectAtIndex:pos] setObject:[user objectForKey:kstatusKey] forKey:kstatusKey];
                           
                           if([user objectForKey:kfullNameKey])
                               [[_contacts objectAtIndex:pos] setObject:[user objectForKey:kfullNameKey] forKey:@"full_name"];
                           [self.contactsTable reloadData];
                           
//                               [self.contactsTable beginUpdates];
//                               
//                               NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:pos] ;
//                               [self.contactsTable reloadDataForRowIndexes:indexSet columnIndexes:0];
//                               [self.contactsTable endUpdates];
                       }
                       
                   });
}

-(void) removeOnlineUser:(NSDictionary*) user
{
    //mutex to prevent others from modifying contacts at the same time
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       //check if  there
                       int __block pos=-1;
                       int __block counter=0;
                       int __block offlinepos=-1;
                       for(NSDictionary* row in _contacts)
                       {
                           if([[row objectForKey:kContactName] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
                              [[row objectForKey:kAccountID]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
                           {
                               pos=counter;
                               break;
                           }
                           counter++;
                       }
                       
                       
                       [[DataLayer sharedInstance] contactForUsername:[user objectForKey:kusernameKey] forAccount:[user objectForKey:kaccountNoKey] withCompletion:^(NSArray* contactRow) {
                           
                           dispatch_async(dispatch_get_main_queue(),
                                          ^{
                                              
                                              if((contactRow.count<1))
                                              {
                                                  DDLogError(@"ERROR:could not find contact row");
                                                  return;
                                              }
                                              
                                              if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                                              {
                                                  
                                                  counter=0;
                                                  for(NSDictionary* row in _offlineContacts)
                                                  {
                                                      if([[row objectForKey:kContactName] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
                                                         [[row objectForKey:kAccountID]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
                                                      {
                                                          offlinepos=counter;
                                                          break;
                                                      }
                                                      counter++;
                                                  }
                                                  
                                                  //in contacts but not in offline.. (not in roster this shouldnt happen)
                                                  if((offlinepos==-1) &&(pos>=0))
                                                  {
                                                      NSMutableDictionary* row= [contactRow objectAtIndex:0] ;
                                                      [_offlineContacts insertObject:row atIndex:0];
                                                      
                                                      //sort
                                                      NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:kContactName  ascending:YES];
                                                      NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
                                                      [_offlineContacts sortUsingDescriptors:sortArray];
                                                      
                                                      //find where it is
                                                      
                                                      counter=0;
                                                      for(NSDictionary* row in _offlineContacts)
                                                      {
                                                          if([[row objectForKey:kContactName] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
                                                             [[row objectForKey:kAccountID]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
                                                          {
                                                              offlinepos=counter;
                                                              break;
                                                          }
                                                          counter++;
                                                      }
                                                      DDLogVerbose(@"sorted contacts %@", _offlineContacts);
                                                  }
                                              }
                                              
                                              //not there
                                              if(pos>=0)
                                              {
//                                                  [_contacts removeObjectAtIndex:pos];
//                                                  DDLogVerbose(@"removing %@ at pos %d", [user objectForKey:kusernameKey], pos);
//                                                  [_contactsTable beginUpdates];
//                                                  NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:konlineSection];
//                                                  [_contactsTable deleteRowsAtIndexPaths:@[path1]
//                                                                        withRowAnimation:UITableViewRowAnimationAutomatic];
//                                                  
//                                                  if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"] && offlinepos>-1)
//                                                  {
//                                                      NSIndexPath *path2 = [NSIndexPath indexPathForRow:offlinepos inSection:kofflineSection];
//                                                      DDLogVerbose(@"inserting offline at %d", offlinepos);
//                                                      [_contactsTable insertRowsAtIndexPaths:@[path2]
//                                                                            withRowAnimation:UITableViewRowAnimationFade];
//                                                  }
                                                  
                                                  [_contactsTable endUpdates];
                                              }
                                              
                                          });
                       }];
                   });
}

-(void) showConnecting:(NSDictionary*) info{
    
}
-(void) updateConnecting:(NSDictionary*) info
{
    
}
-(void) hideConnecting:(NSDictionary*) info{
    
}

-(void) clearContactsForAccount: (NSString*) accountNo
{
    
}



#pragma mark -table view datasource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [self.contacts count];
}

#pragma mark - table view delegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn  row:(NSInteger)row
{
    
    NSDictionary *contactRow = [self.contacts objectAtIndex:row];
    
    MLContactsCell *cell = [tableView makeViewWithIdentifier:@"OnlineUser" owner:self];
    cell.name.backgroundColor =[NSColor clearColor];
    cell.status.backgroundColor= [NSColor clearColor];
    
    cell.name.stringValue = [contactRow objectForKey:kContactName];
   
    NSString *statusText = [contactRow objectForKey:@"status"];
    if( [statusText isEqualToString:@"(null)"])  {
        statusText = @"";
    }
    cell.status.stringValue =statusText;
    
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    return 60.0f;
}


- (void)tableViewSelectionDidChange:(NSNotification *)notification;
{
    if(self.contactsTable.selectedRow<self.contacts.count) {
        NSDictionary *contactRow = [self.contacts objectAtIndex:self.contactsTable.selectedRow];
        [self.chatViewController showConversationForContact:contactRow];
    } else  {
        
    }
}

@end
