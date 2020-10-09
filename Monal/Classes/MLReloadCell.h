//
//  MLReloadCell.h
//  Monal
//
//  Created by Friedrich Altheide on 09.10.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLBaseCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLReloadCell : MLBaseCell
@property (weak, nonatomic) IBOutlet UILabel* reloadLabel;

@end

NS_ASSUME_NONNULL_END
