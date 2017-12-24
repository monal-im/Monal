//
//  MLBaseCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/24/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MLBaseCell : UITableViewCell

@property (nonatomic, strong) IBOutlet NSString* time;
@property (nonatomic, assign) BOOL outBound;
@property (nonatomic, assign) BOOL MUC;

@property (nonatomic, assign) BOOL showName;
@property (nonatomic, strong) IBOutlet UILabel* name;
@property (nonatomic, strong) IBOutlet UILabel* date;
@property (nonatomic, strong) NSString* link;

@property (nonatomic, assign) BOOL deliveryFailed;
@property (nonatomic, strong) IBOutlet UIButton* retry;
@property (nonatomic, strong) NSNumber* messageHistoryId;
@property (nonatomic, weak) UIViewController *parent;

@end
