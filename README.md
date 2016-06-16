# TTPlayer 

## 在线/本地音乐播放器

基于 AVPlayer 封装的在线/本地音乐播放器，一行代码调用播放器，非常方便。

## 集成

下载本项目，将 TTPlayer 文件夹拖进工程， 导入 TTPlayer.h 头文件。

## 使用方法

一句话调用播放器：

```objective-c 

// 地址可以是 url ，也可是本地沙盒路径
NSString *musicUrl = @"http://mr7.doubanio.com/22e3b0bce564794dba6868523d909a69/1/fm/song/p1638900_128k.mp4";

[[TTPlayer sharedPlayer] asyncPlayerWithUrlString:musicUrl completion:^(TTPlayer * _Nonnull player, BOOL successful, NSError * _Nullable error) {
	// 播放完成回调
   NSLog(@"playerDidFinishPlaying : successful -> %d",successful);
}];
    
// 初始化播放器回调
[[TTPlayer sharedPlayer] playerWillPlayingWithCompletion:^(TTPlayer * _Nonnull player) {
   NSLog(@"playerWillPlayingWithCompletion");
}];

// 初始化完成，准备播放回调, 回调音频时长，可以用来更新 UI
[[TTPlayer sharedPlayer] playerReadToPlayWithCompletion:^(TTPlayer * _Nonnull player, CGFloat duration) {
         NSLog(@"playerReadToPlayWithCompletion : duration -> %f",duration);
    }];
    
// 添加当前播放进度监听
/*
	添加播放进度监听，更新进度条和当前播放时间
*/
[[TTPlayer sharedPlayer] playerAddPeriodicTimerObserverUsingBlock:^(CGFloat currentTime, CGFloat duration) {
    NSLog(@"playerAddPeriodicTimerObserverUsingBlock : currentTime -> %f, duration -> %f",currentTime, duration);
}];

// 暂停播放回调
[[TTPlayer sharedPlayer] playerPausePlayingWithCompletion:^(TTPlayer * _Nonnull player) {
   NSLog(@"playerPausePlayingWithCompletion");
}];

```

#### 如果觉得这么写麻烦，也可以使用下面的写法，参考了 Masonry 

```objective-c
[[[[[[TTPlayer sharedPlayer] asyncPlayerWithUrlString:musicUrl completion:^(TTPlayer * _Nonnull player, BOOL successful, NSError * _Nullable error) {
        
        NSLog(@"playerDidFinishPlaying : successful -> %d",successful);
        
    }] playerWillPlayingWithCompletion:^(TTPlayer * _Nonnull player) {

        NSLog(@"playerWillPlayingWithCompletion");
        
    }] playerReadToPlayWithCompletion:^(TTPlayer * _Nonnull player, CGFloat duration) {

        NSLog(@"playerReadToPlayWithCompletion : duration -> %f",duration);
        
    }] playerAddPeriodicTimerObserverUsingBlock:^(CGFloat currentTime, CGFloat duration) {
        NSLog(@"playerAddPeriodicTimerObserverUsingBlock : currentTime -> %f, duration -> %f",currentTime, duration);
        
    }] playerPausePlayingWithCompletion:^(TTPlayer * _Nonnull player) {
        NSLog(@"playerPausePlayingWithCompletion");
    }];

```

## 开源许可

工作中的一点积累，可以随意使用。