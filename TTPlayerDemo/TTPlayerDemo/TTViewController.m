//
//  TTViewController.m
//  TTPlayerDemo
//
//  Created by tofu on 6/16/16.
//  Copyright © 2016 iOS Tofu. All rights reserved.
//

#import "TTViewController.h"
#import "TTPlayer.h"

@interface TTViewController ()

@property (weak, nonatomic) IBOutlet UILabel *currentTimeLabel;
@property (weak, nonatomic) IBOutlet UILabel *durationLabel;
@property (weak, nonatomic) IBOutlet UISlider *playerProgress;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (nonatomic, assign, getter=isDraging) BOOL draging;

@end

@implementation TTViewController

#pragma mark - LifeCycle

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [self defaultPlayerProgress];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Actions
- (IBAction)progressValueChanged:(id)sender {
    NSLog(@"progressValueChanged");
    _draging = YES;
}

- (IBAction)progressDragDidEnd:(UISlider *)sender {
    NSLog(@"progressDragDidEnd");
    
    
   [[TTPlayer sharedPlayer] seekToTime:sender.value completion:^(BOOL finished) {
       _draging = NO;
   }];
}

#pragma mark - Play or Pause
- (IBAction)playActoin:(id)sender {
    
    if ([[TTPlayer sharedPlayer] isPlaying]) {
        [[TTPlayer sharedPlayer] pause];
    } else {
        if ([[TTPlayer sharedPlayer] isPaused]) {
            [[TTPlayer sharedPlayer] resume];
        } else {
            [self start];
        }
    }
}

#pragma mark - Stop play
- (IBAction)stopAction:(id)sender {
    [[TTPlayer sharedPlayer] stop];
    [self defaultPlayerProgress];
}

#pragma mark - Private
- (void)changeButtonTitle:(BOOL)isPlaying {
    if (isPlaying) {
        [self.playButton setTitle:@"暂停" forState:UIControlStateNormal];
    } else {
        [self.playButton setTitle:@"播放" forState:UIControlStateNormal];
    }
}

- (NSString *)perttyTimeFormat:(NSInteger)duration {
    NSInteger seconds = duration % 60;
    NSInteger minutes = (duration / 60) % 60;
    NSInteger hours = duration / 3600;
    
    minutes = minutes + hours * 60;
    
    NSString *minuteStr = @"";
    NSString *secondStr = @"";
    if (seconds < 10) {
        secondStr = [NSString stringWithFormat:@"0%ld", seconds];
    } else {
        secondStr = [NSString stringWithFormat:@"%ld", seconds];
    }
    
    if (minutes < 10) {
        minuteStr = [NSString stringWithFormat:@"0%ld", minutes];
    } else {
        minuteStr = [NSString stringWithFormat:@"%ld", minutes];
    }
    
    
    return [NSString stringWithFormat:@"%@:%@",minuteStr,secondStr];
}

- (void)defaultPlayerProgress {
    self.playerProgress.userInteractionEnabled = NO;
    self.playerProgress.value = 0;
    self.playerProgress.minimumValue = 0;
    self.playerProgress.maximumValue = 0;
    self.currentTimeLabel.text = [self perttyTimeFormat:0];
    self.durationLabel.text = [self perttyTimeFormat:0];
}

#pragma mark - Start Play
- (void)start {
    NSString *musicUrl = @"http://mr7.doubanio.com/22e3b0bce564794dba6868523d909a69/1/fm/song/p1638900_128k.mp4";
    
    [[[[[[TTPlayer sharedPlayer] asyncPlayerWithUrlString:musicUrl completion:^(TTPlayer * _Nonnull player, BOOL successful, NSError * _Nullable error) {
        
        // 延迟1秒播放下一曲，防止太快，回调被反复赋值
//        [self performSelector:@selector(playerDidFinishPlaying) withObject:nil afterDelay:0.5];
        NSLog(@"playerDidFinishPlaying : successful -> %d",successful);
        
    }] playerWillPlayingWithCompletion:^(TTPlayer * _Nonnull player) {
        
        [self defaultPlayerProgress];
        NSLog(@"playerWillPlayingWithCompletion");
        
    }] playerReadToPlayWithCompletion:^(TTPlayer * _Nonnull player, CGFloat duration) {
        self.playerProgress.userInteractionEnabled = YES;
        self.playerProgress.minimumValue = 0;
        self.playerProgress.maximumValue = duration;
        self.durationLabel.text = [self perttyTimeFormat:duration];
        NSLog(@"playerReadToPlayWithCompletion : duration -> %f",duration);
        
    }] playerAddPeriodicTimerObserverUsingBlock:^(CGFloat currentTime, CGFloat duration) {
        
        if (!self.isDraging) {
            self.playerProgress.value = currentTime;
            self.currentTimeLabel.text = [self perttyTimeFormat:currentTime];
        }
        NSLog(@"playerAddPeriodicTimerObserverUsingBlock : currentTime -> %f, duration -> %f",currentTime, duration);
        
    }] playerPausePlayingWithCompletion:^(TTPlayer * _Nonnull player) {
        
        NSLog(@"playerPausePlayingWithCompletion");
    }];

}
@end
