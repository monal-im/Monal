//
//  MLEditGroupViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 4/1/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
typedef void (^controllerCompletion)(void);

@interface MLEditGroupViewController : UITableViewController <UITextFieldDelegate, UIPickerViewDelegate, UIPickerViewDataSource>

@property (nonatomic, strong) NSDictionary *groupData;
@property (nonatomic, strong) controllerCompletion completion;

@end
