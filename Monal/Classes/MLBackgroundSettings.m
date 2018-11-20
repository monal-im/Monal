//
//  MLBackgroundSettings.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/19/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLBackgroundSettings.h"
#import "MLSettingCell.h"

@interface MLBackgroundSettings ()

@end

@implementation MLBackgroundSettings

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"Backgrounds";
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

-(NSString *) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"Select services to opt out of";
}

-(NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return @"Default chat backgrounds are from the Ubuntu project." ;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCell* toreturn;
    switch (indexPath.row) {
        case 0: {
            MLSettingCell* cell=[[MLSettingCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AccountCell"];
            cell.parent= self;
            cell.switchEnabled=YES;
            cell.defaultKey=@"ChatBackgrounds";
            cell.textLabel.text=@"Chat Backgrounds";
            toreturn=cell;
            break;
        }
            
        case 1: {
           UITableViewCell* cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SelectCell"];
            cell.textLabel.text=@"Select Background";
            toreturn=cell;
            break;
        }
            
        case 2: {
            UITableViewCell* cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SelectCell"];
            cell.textLabel.text=@"Select Photo";
            toreturn=cell;
            break;
        }
            
        default:
            break;
    }
   
    return toreturn;
}



@end
