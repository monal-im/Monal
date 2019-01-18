//
//  MLResourcesViewController.h
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 1/10/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLResourcesViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSDictionary *contact;
@property (nonatomic, weak) IBOutlet NSTableView *table;
@property (nonatomic, weak) IBOutlet NSTextField *jid;
@property (nonatomic, weak) IBOutlet NSTextField *topText;
@end

NS_ASSUME_NONNULL_END
