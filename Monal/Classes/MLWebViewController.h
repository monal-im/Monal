//
//  MLWebViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 1/1/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
@import WebKit;

@interface MLWebViewController : UIViewController

-(void) initEmptyPage;
-(void) initViewWithUrl:(NSURL*) url;

@end
