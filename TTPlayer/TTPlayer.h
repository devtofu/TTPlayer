//
//  TTPlayer.h
//  TTDemo
//
//  Created by tofu on 6/8/16.
//  Copyright © 2016 iOS Tofu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TTPlayer;

/* 将要播放回调 */
typedef void(^TTPlayerWillPlayingCompletion)(TTPlayer * _Nonnull player);
/* 暂停播放回调 */
typedef void(^TTPlayerPausePlayingCompletion)(TTPlayer * _Nonnull player);
/* 播放器已经准备好播放 
 
  @param duration 当前播放总时长
 */
typedef void(^TTPlayerReadToPlayCompletion)(TTPlayer * _Nonnull player, CGFloat duration);

/* 
 添加播放时长回调
 
 @param currentTime 当前播放时间
 @param duration 总时长
 */
typedef void(^TTPlayerPeriodicTimerObserverUsingBlock)(CGFloat currentTime, CGFloat duration);

/* 播放完成回调 */
typedef void(^TTPlayerDidFinishPlayingCompletion)(TTPlayer * _Nonnull player, BOOL successful, NSError * _Nullable error);

/*!
 *  播放器类, 支持播放在线/本地音乐
 */
@interface TTPlayer : NSObject

/**
 *  是否播放
 */
@property (readonly, nonatomic, assign, getter=isPlaying) BOOL playing;
/**
 *  是否暂停
 */
@property (readonly, nonatomic, assign, getter=isPaused) BOOL paused;

/**
 *  单例播放器
 *
 *  @return TTPlayer 实例
 */
+ (instancetype)sharedPlayer;

- (instancetype)init /* 重要：不要使用 alloc init 方法初始化播放器 */;

/**
 *  异步播放音频，自动识别播放离线音频还是在线音频
 *
 *  @param urlString  音频地址
 *  @param completion 播放完成回调
 *
 *  @return TTPlayer 实例
 */
- (nonnull TTPlayer *)asyncPlayerWithUrlString:(NSString *)urlString
                                    completion:(nullable TTPlayerDidFinishPlayingCompletion)completion;


@end

@interface TTPlayer (TTPlayerControl)

/**
 *  拖动播放
 */
- (void)seekToTime:(CGFloat)seconds;

/**
 *  拖动播放
 *
 *  @param completion
 */
- (void)seekToTime:(CGFloat)seconds
        completion:(nullable void (^)(BOOL finished))completion;
/**
 *  暂停播放
 */
- (void)pause;

/**
 *  恢复播放
 */
- (void)resume;

/**
 *  停止播放
 *
 *  @warning *重要* 该方法会清空 TTPlayer 中所有 block
 */
- (void)stop;

@end

@interface TTPlayer (TTPlayerCompletion)

/*!
 * ---------------------------------------------------------------------------
 * @warning *重要* 播放结束，TTPlayer 内部会自动清空这些回调
                  .所以每次播放时都要自行调用这些回调方法
 * ---------------------------------------------------------------------------
 */

/**
 *  添加当前播放时长回调
 *
 *  该方法每秒会调用一次，回调在主线程，可用此刷新 UI 时间 。
 *  @param block 当前播放时间
 */
- (TTPlayer * _Nonnull)playerAddPeriodicTimerObserverUsingBlock:(TTPlayerPeriodicTimerObserverUsingBlock)block;

/**
 *  将要播放音频时回调
 *
 *  @param completion
 */
- (TTPlayer * _Nonnull)playerWillPlayingWithCompletion:(TTPlayerWillPlayingCompletion)completion;

/**
 *  准备完毕开始播放回调
 *
 *  @param completion
 */
- (TTPlayer * _Nonnull)playerReadToPlayWithCompletion:(TTPlayerReadToPlayCompletion)completion;

/**
 *  暂停播放回调
 *
 *  @param completion 
 */
- (TTPlayer * _Nonnull)playerPausePlayingWithCompletion:(TTPlayerPausePlayingCompletion)completion;

@end;

NS_ASSUME_NONNULL_END