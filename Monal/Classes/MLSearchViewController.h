//
//  MLSearchViewController.h
//  Monal
//
//  Created by jimtsai (poormusic2001@gmail.com) on 2020/9/23.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MLContact.h"
#import "DataLayer.h"

@protocol SearchResultDeleagte

- (void) doGoSearchResultAction:(NSNumber*_Nullable) nextDBId;
- (void) doReloadActionForPathIndex:(NSIndexPath*_Nonnull) pathIdx;
- (void) doReloadActionForAllTableView;
- (void) doReloadHistoryForSearch;
- (void) doGetMsgData;
@end

NS_ASSUME_NONNULL_BEGIN

@interface MLSearchViewController : UISearchController <UISearchBarDelegate>
@property (nonatomic, strong) MLContact *contact;
@property (nonatomic, weak) NSString *jid;
@property (nonatomic, weak) id <SearchResultDeleagte> searchResultDelegate;
@property (nonatomic) BOOL isLoadingHistory;
@property (nonatomic) BOOL isGoingUp;


- (void) getSearchData:(NSString*) queryText;
- (NSMutableAttributedString*) doSearchKeyword:(NSString*) keyword onText:(NSString*) allText andInbound:(BOOL) inDirection;
- (BOOL) isDBIdExited:(NSNumber*) dbId;
- (void) setResultToolBar;
- (void) setMessageIndexPath:(NSNumber*)idxPath withDBId:(NSNumber*)dbId;
- (NSNumber*) getMessageIndexPathForDBId:(NSNumber*)dbId;
- (void) doNextAction;
- (void) doPreviousAction;
@end

NS_ASSUME_NONNULL_END
