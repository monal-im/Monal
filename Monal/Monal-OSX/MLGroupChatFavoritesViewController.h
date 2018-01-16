//
//  MLGroupChatFavoritesViewController.h
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 1/11/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MLGroupChatFavoritesViewController : NSViewController  <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) IBOutlet NSTableView *favoritesTable;

-(IBAction)join:(id)sender;
-(IBAction)remove:(id)sender;
-(IBAction)doubleClick:(id)sender;


@end
