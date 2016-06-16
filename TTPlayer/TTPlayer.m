//
//  TTPlayer.m
//  TTDemo
//
//  Created by tofu on 6/8/16.
//  Copyright © 2016 iOS Tofu. All rights reserved.
//

#import "TTPlayer.h"
#import "AppDelegate.h"

#define tt_player_dispatch_main_sync_safe(block)\
        if ([NSThread isMainThread]) {\
            block();\
        } else {\
            dispatch_sync(dispatch_get_main_queue(), block);\
        }

#define tt_player_dispatch_main_async_safe(block)\
        if ([NSThread isMainThread]) {\
            block();\
        } else {\
            dispatch_async(dispatch_get_main_queue(), block);\
        }

#pragma mark - Root Player
@interface TTPlayer ()

@property (nonatomic, strong) id playerTimeObserver;
@property (nonatomic, strong) NSURL *currentURL;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *playerItem;


@property (nonatomic, copy) TTPlayerDidFinishPlayingCompletion playerDidFinishPlayingCompletion;
@property (nonatomic, copy) TTPlayerWillPlayingCompletion playerWillPlayingCompletion;
@property (nonatomic, copy) TTPlayerPausePlayingCompletion playerPausePlayingCompletion;
@property (nonatomic, copy) TTPlayerReadToPlayCompletion playerReadToPlayCompletion;
@property (nonatomic, copy) TTPlayerPeriodicTimerObserverUsingBlock playerPeriodTimerObserverBlock;

/* 手动暂停 */
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign, getter=isStop) BOOL stop;
@property (nonatomic, assign) BOOL seekToZeroBeforePlay;
@property (nonatomic, assign) BOOL restoreAfterPlayingState;

@end

#pragma mark - Player
@interface TTPlayer (Private)

- (void)play;
- (CMTime)playerItemDuration;
- (void)removePlayerTimeObserver;
- (void)removePlayerItemObserver;
- (void)removePlayerObserver;
- (void)playerItemDidEndTime:(NSNotification *)notification;

/**
 *  网络不好时，延迟几秒播放，否则时间在走，但没有声音
 */
- (void)mediaBufferToLazyPlay;

@end

static void *TTPlayerPlaybackRateObservationContext = &TTPlayerPlaybackRateObservationContext;
static void *TTPlayerPlaybackStatusObservationContext = &TTPlayerPlaybackStatusObservationContext;
static void *TTPlayerPlaybackBufferEmptyContext = & TTPlayerPlaybackBufferEmptyContext;
static void *TTPlayerPlaybackCurrentItemObservationContext = &TTPlayerPlaybackCurrentItemObservationContext;


#pragma mark - Player Completion
@implementation TTPlayer (TTPlayerCompletion)

- (void)removeCompletion {
    self.playerWillPlayingCompletion = nil;
    self.playerPausePlayingCompletion = nil;
    self.playerPeriodTimerObserverBlock = nil;
    self.playerReadToPlayCompletion = nil;
}


- (TTPlayer * _Nonnull)playerWillPlayingWithCompletion:(TTPlayerWillPlayingCompletion)completion {
    self.playerWillPlayingCompletion = completion;
    return self;
}

- (TTPlayer * _Nonnull)playerReadToPlayWithCompletion:(TTPlayerReadToPlayCompletion)completion {
    self.playerReadToPlayCompletion = completion;
    return self;
}

- (TTPlayer * _Nonnull)playerAddPeriodicTimerObserverUsingBlock:(TTPlayerPeriodicTimerObserverUsingBlock)block {
    self.playerPeriodTimerObserverBlock = block;
    return self;
}

- (TTPlayer * _Nonnull)playerPausePlayingWithCompletion:(TTPlayerPausePlayingCompletion)completion {
    self.playerPausePlayingCompletion = completion;
    return self;
}

@end

@implementation TTPlayer

static TTPlayer *sharedPlayer = nil;

#pragma mark - Initialization
+ (instancetype)sharedPlayer {
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedPlayer = [[TTPlayer alloc] init];
    });
    return sharedPlayer;
}

- (instancetype)init {
    if (self = [super init]) {
        
        _paused = NO;
        _stop = NO;
        _seekToZeroBeforePlay = NO;
        _restoreAfterPlayingState = NO;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerApplicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    
    [self removePlayerTimeObserver];
    [self removePlayerObserver];
    [self removeCompletion];
}


/* Requests invocation of a given block during media playback to update the slider. */
- (void)initPeriodicTimeObserver {

    CMTime playerDuration = [self playerItemDuration];
    if (CMTIME_IS_INVALID(playerDuration)) return;
    
    @synchronized(self) {
        __weak TTPlayer *weakSelf = self;
        self.playerTimeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1)
                                                                            queue:NULL /* If you pass NULL, the main queue is used. */
                                                                       usingBlock:^(CMTime time)
                                   {
                                       if (weakSelf.isPaused) {
                                           return;
                                       }
                                       
                                       if (weakSelf.playerPeriodTimerObserverBlock) {
                                           
                                           tt_player_dispatch_main_async_safe(^{
                                               CGFloat currentTime = CMTimeGetSeconds(time);
                                               
                                               CGFloat totalDuration = CMTimeGetSeconds(playerDuration);
                                               weakSelf.playerPeriodTimerObserverBlock(currentTime, totalDuration);
                                           })
                                           
                                       }
                                   }];
        [self play];
    }
}

#pragma mark - Player
- (TTPlayer *)asyncPlayerWithUrlString:(NSString *)urlString completion:(TTPlayerDidFinishPlayingCompletion)completion {
    
    
    if (self.isPaused && !self.isPlaying) {
        [self play];
        return self;
    }
    
    if (self.isPlaying) {
        [self.player seekToTime:kCMTimeZero];
        [self.player pause];
        [self.player replaceCurrentItemWithPlayerItem:nil];
    }
    _paused = NO;
    _stop = NO;
    

    self.playerDidFinishPlayingCompletion = completion;
    
    NSString *urlStringEncoding = [urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    NSURL *metaUrl = nil;
    if ([urlString hasPrefix:@"http"]) {
        metaUrl = [NSURL URLWithString:urlStringEncoding];
    } else if ([urlString hasPrefix:@"/"]) {
        metaUrl = [NSURL fileURLWithPath:urlStringEncoding];
    } else if ([urlString hasPrefix:@"file://"]) {
        metaUrl = [NSURL URLWithString:urlStringEncoding];
    } else {
        NSError *error = [NSError errorWithDomain:@"TTPlayerURLStringError" code:0 userInfo:@{NSURLErrorFailingURLStringErrorKey:@"请检查音频地址是否正确"}];
        [self assetFailedToPrepareForPlayback:error];
        return self;
    }
    
    if (![self validateLocalFileisExist:metaUrl]) {
        NSError *error = [NSError errorWithDomain:@"TTPlayerURLStringError" code:0 userInfo:@{NSURLErrorFailingURLStringErrorKey:@"文件不存在"}];
        [self assetFailedToPrepareForPlayback:error];
        return self;
    }
    
    
    if (self.currentURL != metaUrl) {
        self.currentURL = [metaUrl copy];
    }
    
    /*
     Create an asset for inspection of a resource referenced by a given URL.
     Load the values for the asset key "playable".
     */
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:self.currentURL options:nil];
    
    NSArray *requestedKeys = @[@"playable"];
    
    /* Tells the asset to load the values of any of the specified keys that are not already loaded. */
    [asset loadValuesAsynchronouslyForKeys:requestedKeys completionHandler:
     ^{
         dispatch_async( dispatch_get_main_queue(),
                        ^{
                            /* IMPORTANT: Must dispatch to main queue in order to operate on the AVPlayer and AVPlayerItem. */
                            [self prepareToPlayAsset:asset withKeys:requestedKeys];
                        });
     }];

    
    return self;
}

#pragma mark - 验证本地音频是否存在
- (BOOL)validateLocalFileisExist:(NSURL *)localURL {
    
    if ([localURL.absoluteString hasPrefix:@"http"] || [localURL.absoluteString hasPrefix:@"https"]) {
        return YES;
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:localURL.absoluteString]) {
        return YES;
    } else {
        NSString *fileName = [localURL.absoluteString lastPathComponent];
        NSString *sourceFile =[[NSBundle mainBundle] pathForResource:fileName ofType:nil];
        if ([sourceFile length] > 0) {
            return YES;
        } else {
            return NO;
        }
    }

}

#pragma mark -
#pragma mark Loading the Asset Keys Asynchronously

#pragma mark -
#pragma mark Error Handling - Preparing Assets for Playback Failed

/* --------------------------------------------------------------
 **  Called when an asset fails to prepare for playback for any of
 **  the following reasons:
 **
 **  1) values of asset keys did not load successfully,
 **  2) the asset keys did load successfully, but the asset is not
 **     playable
 **  3) the item did not become ready to play.
 ** ----------------------------------------------------------- */

- (void)assetFailedToPrepareForPlayback:(NSError *)error {
    if (self.playerDidFinishPlayingCompletion) {
        tt_player_dispatch_main_async_safe(^{
            self.playerDidFinishPlayingCompletion(self, NO, error);
        })
    }
    _stop = YES;
}


#pragma mark Prepare to play asset, URL

/*
 Invoked at the completion of the loading of the values for all keys on the asset that we require.
 Checks whether loading was successfull and whether the asset is playable.
 If so, sets up an AVPlayerItem and an AVPlayer to play the asset.
 */
- (void)prepareToPlayAsset:(AVURLAsset *)asset withKeys:(NSArray *)requestedKeys {

    /* 保证 AVURLAsset 每一个你需要的 key 都加载成功 */
    for (NSString *key in requestedKeys) {
        NSError *error = nil;
        AVKeyValueStatus keyStatus = [asset statusOfValueForKey:key error:&error];
        if (keyStatus == AVKeyValueStatusFailed) {
            [self assetFailedToPrepareForPlayback:error];
            return;
        }
    }
    
    /* 进一步确认是否能播放 */
    if (!asset.playable) {
        NSError *assetCannotBePlayedError = [NSError errorWithDomain:@"TTStitchedStreamPlayer" code:0 userInfo:@{NSLocalizedFailureReasonErrorKey:@"The assets tracks were loaded, but could not be made playable."}];
        [self assetFailedToPrepareForPlayback:assetCannotBePlayedError];
        return;
    }
    
    /* 开始播放之前 停止前一个音频的监听 */
    if (self.playerItem) {
        [self.playerItem removeObserver:self forKeyPath:@"status"];
        [self.playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemDidPlayToEndTimeNotification
                                                      object:self.playerItem];
    }
    
    self.playerItem = [AVPlayerItem playerItemWithAsset:asset];
    
    /* 监听播放器状态 */
    [self.playerItem addObserver:self
                      forKeyPath:@"status"
                         options:NSKeyValueObservingOptionNew |NSKeyValueObservingOptionOld
                         context:TTPlayerPlaybackStatusObservationContext];
    [self.playerItem addObserver:self
                      forKeyPath:@"playbackBufferEmpty"
                         options:NSKeyValueObservingOptionNew |NSKeyValueObservingOptionOld
                         context:TTPlayerPlaybackBufferEmptyContext];
    /* 播放完成通知 */
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidEndTime:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:self.playerItem];
    if (!self.player) {
        
        self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
        [self.player setActionAtItemEnd:AVPlayerActionAtItemEndPause];
        [self.player addObserver:self
                      forKeyPath:@"currentItem"
                         options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                         context:TTPlayerPlaybackCurrentItemObservationContext];
        
        [self.player addObserver:self
                      forKeyPath:@"rate"
                         options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                         context:TTPlayerPlaybackRateObservationContext];
    }
    
    if (self.player.currentItem != self.playerItem) {
        
        [self.player replaceCurrentItemWithPlayerItem:self.playerItem];
    }
    
    // 通知将要播放
    if (self.playerWillPlayingCompletion) {
        tt_player_dispatch_main_async_safe(^{
            self.playerWillPlayingCompletion(self);
        })
    }
}

#pragma mark -
#pragma mark Asset Key Value Observing
#pragma mark

#pragma mark Key Value Observer for player rate, currentItem, player item status
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    /* AVPlayerItem context */
    if (context == TTPlayerPlaybackStatusObservationContext) {
        
        AVPlayerStatus status = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];
        
        switch (status) {
            case AVPlayerStatusUnknown: {
                [self removePlayerTimeObserver];
                break;
            }
            case AVPlayerStatusReadyToPlay: {
                [self removePlayerTimeObserver];
                [self initPeriodicTimeObserver];
                if (self.playerReadToPlayCompletion) {
                    tt_player_dispatch_main_async_safe(^{
                        CMTime playerDuration = [self playerItemDuration];
                        self.playerReadToPlayCompletion(self ,CMTimeGetSeconds(playerDuration));
                    })
                }
                self.seekToZeroBeforePlay = NO;
                break;
            }
            case AVPlayerStatusFailed: {
                AVPlayerItem *playerItem = (AVPlayerItem *)object;
                [self assetFailedToPrepareForPlayback:playerItem.error];
                break;
            }
        }
    } else if (context == TTPlayerPlaybackCurrentItemObservationContext) {
        /* AVPlayer AVPlayer "currentItem" property observer. */
    } else if (context == TTPlayerPlaybackRateObservationContext) {
        /* AVPlayer "rate" property observer. */
        
        /* 
         有些音频最后1秒不能播放，不会触发 `AVPlayerItemDidPlayToEndTimeNotification` 通知，
         手动调用播放结束。
        */
        CGFloat rate = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];
        if (!rate) {
            CGFloat currentTime = CMTimeGetSeconds([self.player currentTime]);
            CGFloat duration = CMTimeGetSeconds([self playerItemDuration]);
            if (duration - currentTime < 2.0 && !self.seekToZeroBeforePlay) {
                [self stop];
            }
        }
        NSLog(@"TTPlayerPlaybackRateObservationContext : %f",rate);
    } else if (context == TTPlayerPlaybackBufferEmptyContext) {
        /* AVPlayer "bufferEmpty" property observer */
        AVPlayerItem *playerItem = object;
        if (playerItem.isPlaybackBufferEmpty) {
            [self mediaBufferToLazyPlay];
        }
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


#pragma mark - Notification

- (void)playerApplicationDidEnterBackground:(NSNotification *)notification {
    if (self.isPlaying) {
        [self stop];
    }
}

@end



#pragma mark - Player Control

@implementation TTPlayer (TTPlayerControl)

/**
 *  拖动播放
 *
 *  @param completion
 */
- (void)seekToTime:(CGFloat)seconds {
    [self seekToTime:seconds completion:nil];
}
/**
 *  拖动播放
 *
 *  @param completion
 */
- (void)seekToTime:(CGFloat)seconds completion:(void (^)(BOOL))completion {
    
    if (self.isStop) {
        return;
    }
    
    CMTime playerDuration = [self playerItemDuration];
    if (CMTIME_IS_INVALID(playerDuration)) return;
    CGFloat duration = CMTimeGetSeconds(playerDuration);
    seconds = MAX(0, seconds);
    seconds = MIN(seconds, duration);
    
    if (self.isPaused) {
        [self.player seekToTime:CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC)];
        return;
    }
    
    __weak TTPlayer *weakSelf = self;
    [self.player pause];
    [self.player seekToTime:CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC) completionHandler:^(BOOL finished) {
        if (finished) {
            [weakSelf.player play];
//            if (weakSelf.playerReadToPlayCompletion) {
//                tt_player_dispatch_main_async_safe(^{
//                    weakSelf.playerReadToPlayCompletion(weakSelf, CMTimeGetSeconds([weakSelf playerItemDuration]));
//                })
//            }
            
            if (completion) {
                tt_player_dispatch_main_async_safe(^{
                    completion(finished);
                })
            }
        }
    }];
    
}

/**
 *  暂停播放
 */
- (void)pause {
    if (self.isPlaying) {
        [self.player pause];
        _paused = YES;
        
        if (self.playerPausePlayingCompletion) {
            tt_player_dispatch_main_async_safe(^{
                self.playerPausePlayingCompletion(self);
            })
        }
    }
}

/**
 *  恢复播放
 */
- (void)resume {
    if (self.isPaused) {
        [self play];
    }
}

/**
 *  停止播放
 */
- (void)stop {
    if (self.isPlaying) {
        [self.player seekToTime:kCMTimeZero];
        [self.player pause];
        [self.player replaceCurrentItemWithPlayerItem:nil];
    }

    if (self.isPaused) {
        [self.player seekToTime:kCMTimeZero];
        [self.player replaceCurrentItemWithPlayerItem:nil];
    }
    
    [self removePlayerTimeObserver];
    [self removePlayerItemObserver];
    [self removeCompletion];
    if (self.playerDidFinishPlayingCompletion) {
        tt_player_dispatch_main_sync_safe(^{
            self.playerDidFinishPlayingCompletion(self, YES, nil);
            self.playerDidFinishPlayingCompletion = nil;
        })
    }
    _paused = NO;
    _stop = YES;
    
}

/**
 *  是否正在播放
 *
 *  @return
 */
- (BOOL)isPlaying {
    return self.player.rate;
}

@end

#pragma mark - Player Private
@implementation TTPlayer (Private)

- (void)playerItemDidEndTime:(NSNotification *)notification {
    
    self.seekToZeroBeforePlay = YES;
    
    [self stop];
}

- (CMTime)playerItemDuration {
    AVPlayerItem *playerItem = [self.player currentItem];
    if (playerItem.status == AVPlayerItemStatusReadyToPlay)
    {
        return([playerItem duration]);
    }
    
    return(kCMTimeInvalid);
}

/* Cancels the previously registered time observer. */
- (void)removePlayerTimeObserver {
    if (self.playerTimeObserver) {
        [self.player removeTimeObserver:self.playerTimeObserver];
        self.playerTimeObserver = nil;
    }
}

- (void)removePlayerObserver {
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.player removeObserver:self forKeyPath:@"rate"];
    [self.player removeObserver:self forKeyPath:@"currentItem"];

}

- (void)removePlayerItemObserver {
    if (self.playerItem) {        
        [self.playerItem removeObserver:self forKeyPath:@"status"];
        [self.playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
        self.playerItem = nil;
    }
}

/**
 *  播放
 */
- (void)play {
    if (YES == self.seekToZeroBeforePlay) {
        self.seekToZeroBeforePlay = NO;
        [self.player seekToTime:kCMTimeZero];
    }
    [self.player play];
    _paused = NO;
}

/**
 *  网络不好时，延迟几秒播放，否则时间在走，但没有声音
 */
- (void)mediaBufferToLazyPlay {
    
    static BOOL isBuffering = NO;
    if (isBuffering) {
        return;
    }
    isBuffering = YES;
    
    [self.player pause];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        if (self.isPaused) {
            isBuffering = NO;
            return;
        }
        
        [self play];
        isBuffering = NO;
        //如果还是没播放，继续等待缓存
        if (!self.playerItem.isPlaybackLikelyToKeepUp) {
            [self mediaBufferToLazyPlay];
        }
    });
}

@end


