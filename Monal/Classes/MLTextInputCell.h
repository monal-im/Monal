//
//  MLTextInputCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 4/10/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MLTextInputCell : UITableViewCell

-(void) initTextCell:(NSString*) text andPlaceholder:(NSString*) placeholder andDelegate:(id) delegate;
-(void) initMailCell:(NSString*) text andPlaceholder:(NSString*) placeholder andDelegate:(id) delegate;
-(void) initPasswordCell:(NSString*) text andPlaceholder:(NSString*) placeholder andDelegate:(id) delegate;

-(void) disableEditMode;

-(NSString*) getText;

@end
