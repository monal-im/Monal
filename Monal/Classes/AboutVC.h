//
//  AboutVC.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/28/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "tools.h"

@interface AboutVC : UIViewController {
	IBOutlet UILabel* versionText;
	IBOutlet UIScrollView* scroll;
}
-(IBAction) rateApp;


@end
