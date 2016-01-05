//
//  DLTAVPlayer.m
//  AVPlayerSample
//
//  Created by ttiamap on 04/01/2016.
//  Copyright © 2016 ttiamap. All rights reserved.
//

#import "DLTAVPlayer.h"
#import <MediaPlayer/MediaPlayer.h>

#define kDELAYTIME_PLAYAUDIO 0.5
#define kDELAYTIME_NOTIFICATIONFIRE 0.5
#define kDELAYTIME_AUDIOEFFECT 0.1
#define kDELAYTIME_BUFFERINGTOPLAY 8.0
#define kDELAYTIME_RECONNECT 8.0

// ERRORFIRE

@implementation DLTAVPlayer{
    NSUInteger timeEndPlaying; // It's the last time to stop audio
    
    CGFloat audioCurrentVolume;
    CGFloat audioVolumeSave;
    
    NSTimer *timerRetryConnection;
    NSTimer *timerDoWithVolumeFadeIn;
    
    UIImage *backgroundModeImage;
    NSString *backgroundModeSongName;
    NSString *backgroundModeSingerName;
    NSString *backgroundModeLinkImage;
}

//@synthesize playingStatus = _playingStatus;

static AVAudioSession *session;

// AVPlayer Property
static __strong AVPlayer *_avPlayer;
static __strong AVPlayerItem *_avPlayerItem;

// User Flag
static BOOL kIsUserPauseAudio = YES;

// Streaming flag
static int kReconnectTimes = 0;
static const int kReconnectRetries = 3;
static BOOL kStreamingSuccess = NO;
static BOOL kPlayerIsBuffering = NO;

// KVO Context
static void *playbackLikelyToKeepUpKVOToken = &playbackLikelyToKeepUpKVOToken;
static void *playbackBufferEmpty = &playbackBufferEmpty;
static void *playbackBufferFull = &playbackBufferFull;
static void *playbackStatus = &playbackStatus;
static void *playbackRate = &playbackRate;

#pragma mark - SingleTon
//=================================================================================================
// singleton
+ (DLTAVPlayer *)shareController{
    static dispatch_once_t once;
    static DLTAVPlayer *shareController;
    dispatch_once(&once, ^{
        shareController = [[self alloc]init];
        
        [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive: YES error: nil];
        
        // handle user Interruption notification
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(userEndInterruption:)
                                                     name:AVAudioSessionInterruptionNotification
                                                   object:session];
        
        // handle user unplug headphone
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(userUnplugedHeadPhone:)
                                                     name:AVAudioSessionRouteChangeNotification
                                                   object:session];
        
    });
    
    return shareController;
}

- (void)setPlayingStatus:(BOOL)playingStatus{
    _playingStatus = kIsUserPauseAudio;
}

+ (void)DLTAVPlayerRegisterAudioInBackgroundMode:(UIApplication *)application{
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    
    if([[UIApplication sharedApplication]  respondsToSelector:@selector(beginReceivingRemoteControlEvents)])
        [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    
    __block UIBackgroundTaskIdentifier task = 0;
    task=[application beginBackgroundTaskWithExpirationHandler:^{
        NSLog(@"Expiration handler called %f",[application backgroundTimeRemaining]);
        [application endBackgroundTask:task];
        task=UIBackgroundTaskInvalid;
    }];
    
    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive: YES error: nil];
    
    [[UIApplication sharedApplication] becomeFirstResponder];
}

#pragma mark - Add or Remove Obserer
//================================= Add or Remove Obserer ===================================

- (void)avplayerRemoveObserver{
    
    if (_avPlayer == nil) {
        NSLog(@"RemoveObsever AVPlayer = nil return");
        return;
    }
    @try {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // stop the audio when it is streaming
            [_avPlayer pause];
            
            if (_avPlayer && _avPlayer.currentItem) {
                
                [_avPlayer removeObserver:self forKeyPath:@"status" context:playbackStatus];
                [_avPlayer removeObserver:self forKeyPath:@"rate" context:playbackRate];
                
                [[NSNotificationCenter defaultCenter]removeObserver:self
                                                               name:AVPlayerItemDidPlayToEndTimeNotification
                                                             object:[_avPlayer currentItem]];
            }
            NSLog(@"RemoveObsever Set AVPlayerItem And AVPlayer = nil");
            _avPlayerItem = nil;
            _avPlayer = nil;
            
        });
    }
    @catch (NSException *exception) {
        NSLog(@"RemoveObsever Error : %@",[exception description]);
        //ERRORFIRE
    }
}

- (void)avplayerAddObsever{
    
    @try {
        if (_avPlayer && _avPlayer.currentItem) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [_avPlayer addObserver:self forKeyPath:@"status" options:0 context:playbackStatus];
                [_avPlayer addObserver:self forKeyPath:@"rate" options:NSKeyValueObservingOptionNew context:playbackRate];
                
                [[NSNotificationCenter defaultCenter] addObserver:self
                                                         selector:@selector(playerItemDidReachEnd:)
                                                             name:AVPlayerItemDidPlayToEndTimeNotification
                                                           object:[_avPlayer currentItem]];
                
                //            [_avPlayer.currentItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:playbackLikelyToKeepUpKVOToken];
                //            [_avPlayer.currentItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:playbackBufferEmpty];
                
            });
        }
    }
    @catch (NSException *exception) {
        NSLog(@"AddObsever Error : %@",[exception description]);
        //ERRORFIRE
    }
}

#pragma mark - StreamAudio

// playing local file audio
+ (void)DLTAVPlayer_PlayingLocalAudioFileWithLink:(NSString *)linkAudio imageArtWorkLink:(NSString *)linkArtWork orImageArtWork:(UIImage *)imageArtWork{
    NSURL *url = [NSURL fileURLWithPath:linkAudio];
    [[self shareController] AVPlayer_PlayingLocalFile:url];
}

-(void) AVPlayer_PlayingLocalFile: (NSURL*) url {
    //    [self avplayerRemoveObserver];
    
    //    AVAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    //    AVPlayerItem *anItem = [[AVPlayerItem alloc]initWithAsset:asset];
    //    _avPlayer = [[AVPlayer alloc]initWithURL:url];
    
    AVURLAsset *urlAsset = [AVURLAsset URLAssetWithURL:url options:nil];
    
    NSArray *keyArray = [[NSArray alloc] initWithObjects:@"tracks", nil];
    
    [urlAsset loadValuesAsynchronouslyForKeys:keyArray completionHandler:^{
        
        AVPlayerItem *playerItem = [[AVPlayerItem alloc] initWithAsset:urlAsset];
        
        _avPlayer = nil;
        _avPlayer = [[AVPlayer alloc] initWithPlayerItem:playerItem];
        
        while (true) {
            if (_avPlayer.status == AVPlayerStatusReadyToPlay && playerItem.status == AVPlayerItemStatusReadyToPlay)
                break;
        }
        
        [_avPlayer play];
        
    }];
    
}

// steaming link
+ (void)DLTAVPlayer_PlayAudioWithStreamingLink:(NSString *)linkAudio {
    [[self shareController] DLTAVPlayer_PlayAudioLink:linkAudio];
}

- (void)DLTAVPlayer_PlayAudioLink:(NSString *)linkAudio{
    
    kIsUserPauseAudio = NO;
    [self AVPlayerPlaySongWithStreamingLink:linkAudio];
}

- (void)AVPlayerPlaySongWithStreamingLink:(NSString *)streamingLink{
    
    kStreamingSuccess = NO;
    
    @try {
        if (!kStreamingSuccess && kReconnectTimes >= kReconnectRetries ) {
            // ERRORFIRE
            kReconnectTimes = 0;
            NSLog(@"Stream player over three time return");
            return;
        }
        
        //1
        // Remove all the obsever from AVPlayer for listen to new streaming link
        [self avplayerRemoveObserver];
        
        //2
        // after removeObsever Success
        // stream audio with link
        [self AVPlayerStreamingAudioLink:streamingLink];
    }
    @catch (NSException *exception) {
        // ERRORFIRE
        NSLog(@"streaming Error : %@",[exception description]);
    }
}

- (void)AVPlayerStreamingAudioLink:(NSString *)audioLink{
    
    NSURL *stringUrl = [NSURL URLWithString:audioLink];
    AVAsset *asset = [AVURLAsset URLAssetWithURL:stringUrl options:nil];
    NSString *tracksKey = @"tracks";
    
    [asset loadValuesAsynchronouslyForKeys:[NSArray arrayWithObject:tracksKey] completionHandler:^{
        
        dispatch_async(dispatch_get_main_queue(), ^{
            //
            NSError *error = nil;
            AVKeyValueStatus status = [asset statusOfValueForKey:tracksKey error:&error];
            
            if(status == AVKeyValueStatusLoaded){
                // set asset to player item when it loaded
                _avPlayerItem = [AVPlayerItem playerItemWithAsset:asset];
                
                //3
                // init PlayerItem to avplayer
                
                if (!_avPlayer) {
                    // if avplayer is frist init
                    [self AVPlayerInitWithNewItem];
                    
                }else if (_avPlayer.currentItem != _avPlayerItem || !_avPlayer){
                    // if avplayer is exists an item before
                    [self AVPlayerReplaceWithNewItem];
                }
                
                //4
                //add obsever to player item
                [self avplayerAddObsever];
                
                //5
                //set background view player
                [self backgroundViewPlayerControllerUpdateUIWithImageLink:backgroundModeLinkImage orImageArtWork:backgroundModeImage songName:backgroundModeSongName singerName:backgroundModeSingerName];
                
                // a flag to count three times when load audio problem with internet or something else
                // set back flag = 0
                kReconnectTimes = 0;
            }
            else{
                
                // a flag to count three times when load audio problem with internet or something else
                NSLog(@"The asset's tracks were not loaded with Reload count %d",kReconnectTimes);
                NSLog(@"The asset's loaded fail Error : %@",[error description]);
                
                // increase kRestreaming time
                kReconnectTimes++;
                
                // restreaming
                [self AVPlayerPlaySongWithStreamingLink:audioLink];
                
            }
        });
    }];
}

- (void)AVPlayerInitWithNewItem{
    
    @try {
        _avPlayer = [AVPlayer playerWithPlayerItem:_avPlayerItem];
        //
        NSLog(@"AVPlayer init item sucess and Asset load");
        NSLog(@"play with volume fade in after initPlayerItem sucess");
        
        [self performSelector:@selector(PlayWithVolumeFadeIn) withObject:nil afterDelay:kDELAYTIME_PLAYAUDIO];
    }
    @catch (NSException *exception) {
        //ERRORFIRE
        NSLog(@"AVPlayerInitWithNewItem Error : %@",[exception description]);
    }
    @finally {
        NSLog(@"Remove playerItem when init success or not");
        _avPlayerItem = nil;
    }
    
}

- (void)AVPlayerReplaceWithNewItem{
    @try {
        [_avPlayer replaceCurrentItemWithPlayerItem:_avPlayerItem];
        NSLog(@"AVPlayer Replace item sucess");
        
        //4
        // When it Replacing New item. It Not Auto play
        // and we will handle to play it
        
        [self performSelector:@selector(PlayWithVolumeFadeIn) withObject:nil afterDelay:kDELAYTIME_PLAYAUDIO];
        NSLog(@"play with volume fade in after replace sucess");
        
    }
    @catch (NSException *exception) {
        //ERRORFIRE
        NSLog(@"AVPlayerReplaceWithNewItem Error : %@",[exception description]);
    }
    @finally{
        NSLog(@"Remove playerItem when replace success or not");
        _avPlayerItem = nil;
    }
}

#pragma mark - AVPlayer handle Obsever And Keypath
//================================= AVPlayer handle Obsever And Keypath ===================================

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
    if (!_avPlayer){
        return;
    }
    
    //========================= handle Context
    if (context == playbackStatus && [keyPath isEqualToString:@"status"]) {
        [self observe_AVPlayerStatus];
    }
    
    if (context == playbackLikelyToKeepUpKVOToken && [keyPath isEqualToString:@"playbackLikelyToKeepUp"]){
        [self observe_AVPlayerPlayBackToKeepUp];
    }
    
    if (context == playbackBufferEmpty){
        if (_avPlayer.currentItem.playbackBufferEmpty){
            [self observe_AVPlayerBufferEmpty];
        }
    }
    
    if (context == playbackRate && [keyPath isEqualToString:@"rate"]) {
        [self observe_AVPlayerRate];
    }
}

- (void)observe_AVPlayerRate{
    
    static int i = 1;
    
    int rate = (int)_avPlayer.rate;
    
    if (rate > 0 && [self checkAVPlayerControllerIsPlaying]) {
        NSLog(@"Notification Fire in avPlayerRate");
        
        [self delegateAVPlayerStateFire:DLTAVPlayerStatePlaying withErrorMessage:nil];
        return;
    }
    
    if (!(rate > 0) && kPlayerIsBuffering && i<4){
        
        NSLog(@"Audio has pause because of slow buffer (Rate = 0)");
        
        kPlayerIsBuffering = YES;
        [self performSelector:@selector(PlayWithVolumeFadeIn) withObject:nil afterDelay:(kDELAYTIME_BUFFERINGTOPLAY*i)];
        ++i;
        // play with delay 8s * i
    }
}

- (void)observe_AVPlayerStatus{
    if (_avPlayer.status == AVPlayerStatusFailed) {
        
        AVPlayerItem *playerItem = (AVPlayerItem *)_avPlayer.currentItem;
        NSLog(@"AVPlayer Failed");
        NSLog(@"avPlayerStatus Error : %@",[playerItem.error localizedDescription]);
        
        // Song Fail Delegte call
        [self delegateAVPlayerStateFire:DLTAVPlayerStateError withErrorMessage:playerItem.error];
        return;
        
    } else if (_avPlayer.status == AVPlayerStatusReadyToPlay) {
        NSLog(@"AVPlayer Ready to Play");
        
        // Delay for audio buffering and play
        [self performSelector:@selector(PlayWithVolumeFadeIn) withObject:nil afterDelay:kDELAYTIME_PLAYAUDIO];
        
    } else if (_avPlayer.status == AVPlayerItemStatusUnknown) {
        NSLog(@"AVPlayer Unknown");
        [self timerReconnectCreate];
    }
}

- (void)observe_AVPlayerBufferEmpty{
    NSLog(@"recieve BUFFER EMPTY!!!"); // Buffer empty.... why when playbackShouldKeep up was just sent milliseconds ago.
    //    _retries = 0;
    if (_avPlayer.status == AVPlayerStatusReadyToPlay && CMTimeGetSeconds(_avPlayer.currentItem.duration)) {
        
        NSLog(@"do BUFFER EMPTY");
        
        // call to play audio with delay
        [self observe_AVPlayerRate];
        
        //                float percent = CMTimeGetSeconds(timerange.duration) / CMTimeGetSeconds(self.player.currentItem.duration);
        //                if (percent > VIDEO_BUFFER_READY_PERCENT) {
        //                    NSLog(@" . . . %.5f -> %.5f, %f percent", CMTimeGetSeconds(timerange.duration), CMTimeGetSeconds(CMTimeAdd(timerange.start, timerange.duration)), percent);
        //                    [self.player prerollAtRate:0.0 completionHandler:^(BOOL finished) {
        //                        [self.player seekToTime:kCMTimeZero];
        //                    }
        
    }else{
        [self timerReconnectCreate];
    }
}

- (void)observe_AVPlayerPlayBackToKeepUp{
    NSLog(@"recieve playbackLikelyToKeepUp");
    if (_avPlayer.currentItem.playbackLikelyToKeepUp == NO &&
        CMTIME_COMPARE_INLINE(_avPlayer.currentTime, >, kCMTimeZero) &&
        CMTIME_COMPARE_INLINE(_avPlayer.currentTime, !=, _avPlayer.currentItem.duration)) {
        NSLog(@"hanged playbackLikelyToKeepUp");
        
        if (_avPlayer.status == AVPlayerStatusReadyToPlay) {
            [self observe_AVPlayerRate];
        }
    }
    
}

#pragma mark - Reconnect with fail streaming
- (void)timerReconnectCreate{
    if (timerRetryConnection) {
        return;
    }
    timerRetryConnection = [NSTimer scheduledTimerWithTimeInterval:kDELAYTIME_RECONNECT
                                                            target:self
                                                          selector:@selector(tryReconnect:)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)timerReplayAudioCreate{
    if (timerDoWithVolumeFadeIn) {
        return;
    }
    timerDoWithVolumeFadeIn = [NSTimer scheduledTimerWithTimeInterval:kDELAYTIME_BUFFERINGTOPLAY
                                                               target:self
                                                             selector:@selector(PlayWithVolumeFadeIn)
                                                             userInfo:nil
                                                              repeats:YES];
}

- (void)tryReconnect:(NSTimer *)sender {
    static int _retries = 0;
    NSLog(@"tryReconnect Called. Retry: %i", _retries);
    if (_retries <= kReconnectRetries) {
        
        // reset AVplayer
        [self avplayerRemoveObserver];
        _avPlayer = nil;
        _avPlayerItem = nil;
        
        _retries ++;
    } else {
        NSLog(@"Connection Dropped: invalidating Timer.");
        
        // release timer
        [self timerRelease];
        
        // reset AVplayer
        _avPlayer = nil;
        _avPlayerItem = nil;
        
        // next to song
        
        _retries = 0;
    }
}

- (void)timerRelease{
    if (timerDoWithVolumeFadeIn) {
        [timerDoWithVolumeFadeIn invalidate];
        timerDoWithVolumeFadeIn = nil;
    }
    
    if (timerRetryConnection) {
        [timerRetryConnection invalidate];
        timerRetryConnection = nil;
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    
    // Song finish play
    [[self delegate] DLTAVPlayer_DidEndSongPlay];
    
}


#pragma mark - Player View At Lock Screen

+ (void)DLTAVPlayer_BackgroundViewPlayerInitWithImageLink:(NSString *)linkArtWork orImageArtWork:(UIImage *)imageArtWork songName:(NSString *)stringSongName singerName:(NSString *)stringSingerName{
    
    [[self shareController] DLTAVPlayer_SetBackgroundModeSongName:stringSongName SingerName:stringSingerName image:imageArtWork orLinkImage:linkArtWork];
    [[self shareController] backgroundViewPlayerControllerUpdateUIWithImageLink:linkArtWork orImageArtWork:imageArtWork songName:stringSongName singerName:stringSingerName];
}

// save back background mode Info
- (void)DLTAVPlayer_SetBackgroundModeSongName:(NSString *)songName SingerName:(NSString *)singerName image:(UIImage *)image orLinkImage:(NSString *)imageLink{
    
    backgroundModeSongName = songName;
    backgroundModeSingerName = singerName;
    
    if (image || imageLink) {
        if (image) {
            backgroundModeImage = image;
            backgroundModeLinkImage = nil;
        }else{
            backgroundModeLinkImage = imageLink;
            backgroundModeImage = nil;
        }
    }
}

- (void)backgroundViewPlayerControllerUpdateUIWithImageLink:(NSString *)linkArtWork orImageArtWork:(UIImage *)imageArtWork songName:(NSString *)stringSongName singerName:(NSString *)stringSingerName{
    
    if (!stringSongName.length > 0) {
        stringSongName = @"Unknow";
    }
    
    if (!stringSingerName.length > 0) {
        stringSingerName = @"Unknow";
    }
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        // Create Song Info for background
        NSDictionary *songInfo = [NSDictionary dictionary];
        
        // Compare NewImage with CurrentImage
        // if no change => use currentimage (not to load new image)
        //        static NSString* stringCompareImageURL = @"";
        NSNumber *avplayerItemDuration = [NSNumber numberWithFloat:[self getAudioTotalTime]];
        NSNumber *avplayerItemCurrentPlayTime = [NSNumber numberWithFloat:[self getAudioCurrentTime]];
        
        UIImage *artworkImage = nil;
        
        if (imageArtWork == nil) {
            artworkImage = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:linkArtWork]]];
        }else{
            artworkImage = imageArtWork;
        }
        
        
        // set background SongInfo
        if(artworkImage){
            MPMediaItemArtwork *albumArt = [[MPMediaItemArtwork alloc] initWithImage: artworkImage];
            
            songInfo = @{ MPMediaItemPropertyTitle:stringSongName,
                          MPMediaItemPropertyArtist: stringSingerName,
                          //                              MPMediaItemPropertyAlbumTitle: @"",
                          MPMediaItemPropertyPlaybackDuration: avplayerItemDuration,
                          MPNowPlayingInfoPropertyPlaybackRate: [NSNumber numberWithInt:1],
                          MPNowPlayingInfoPropertyElapsedPlaybackTime: avplayerItemCurrentPlayTime,
                          MPMediaItemPropertyArtwork: albumArt };
        }else{
            songInfo = @{ MPMediaItemPropertyTitle:stringSongName,
                          MPMediaItemPropertyArtist: stringSingerName,
                          //                              MPMediaItemPropertyAlbumTitle: @"",
                          MPMediaItemPropertyPlaybackDuration: avplayerItemDuration,
                          MPNowPlayingInfoPropertyPlaybackRate: [NSNumber numberWithInt:1],
                          MPNowPlayingInfoPropertyElapsedPlaybackTime: avplayerItemCurrentPlayTime};
        }
        MPNowPlayingInfoCenter *infoCenter = [MPNowPlayingInfoCenter defaultCenter];
        infoCenter.nowPlayingInfo = songInfo;
        
        NSLog(@"Create background view");
    });
}

#pragma mark - AVPlayer Controller Play, Pause , Resume , Stop

// Play
+ (void)DLTAVPlayerPlayAudioFadeInEffect:(BOOL)enable{
    //
    //    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayback error:nil];
    kIsUserPauseAudio = NO;
    if (enable) {
        [[self shareController]PlayWithVolumeFadeIn];
    }else{
        [[self shareController] doVolumeFadeIn];
    }
}

// Pause
+ (void)DLTAVPlayerPauseAudioFadeOutEffect:(BOOL)enable{
    kIsUserPauseAudio = YES;
    
    [[self shareController] PauseWithVolumeFadeOutEnable:enable];
    
}

//Stop
+ (void)DLTAVPLayerStopAudio{
    kIsUserPauseAudio = YES;
    [[self shareController] avplayerRemoveObserver];
}

+ (void)DLTAVPLayerStopAudioWithSongChange{
    [[self shareController] avplayerRemoveObserver];
}

// Seeking
+ (void)DLTAVplayerSeekToProcessingValue:(CGFloat)value{
    [[self shareController] AVPlayerSeekToProcessingValue:value];
}

- (void)AVPlayerSeekToProcessingValue:(CGFloat)value{
    [_avPlayer pause];
    
    [_avPlayer seekToTime:[self getCMTimeWithPlayerProcessingValue:value] completionHandler:^(BOOL finished) {
        if (kIsUserPauseAudio == NO) {
            [_avPlayer play];
            
            //
            [self delegateAVPlayerStateFire:DLTAVPlayerStatePlaying withErrorMessage:nil];
        }
    }];
}

#pragma mark - Get Audio Info
#pragma mark AVAudio Duration And Current Play time
+ (CGFloat)DLTAVPlayerGetAudioProcessingValue{
    return  [[self shareController] getAudioCurrentTime]/ [[self shareController]getAudioTotalTime];
}

+ (CGFloat)DLTAVPlayerGetAudioDurationFloatValue{
    return [[self shareController]getAudioTotalTime];
}

+ (NSString *)DLTAVPlayerGetAudioDurationString{
    return [[self shareController]avplayerGetAudioDurationValue];
}

+ (NSString *)DLTAVPlayerGetAudioCurrentPlayTimeString{
    return [[self shareController]avplayerGetAudioCurrentPlayTime];
}

// audio Processing
- (CGFloat)getAudioCurrentTime{
    CMTime current = _avPlayer.currentItem.currentTime;
    return CMTimeGetSeconds(current);
}

- (CGFloat)getAudioTotalTime{
    CMTime current = _avPlayer.currentItem.asset.duration;
    return CMTimeGetSeconds(current);
}

//audio duration
- (NSString *)avplayerGetAudioDurationValue{
    int durationSecond = [self getAudioTotalTime];
    if (durationSecond > 0) {
        // if audio data get sucess -> duration > 0
        // convert duration to song Duration format
        return [self getAudioTimeFormatWithCMTimeSecond:durationSecond];
    }
    return @"00:00";
}

//audio current playtime
- (NSString *)avplayerGetAudioCurrentPlayTime{
    int currentPlayTime = [self getAudioCurrentTime];
    return [self getAudioTimeFormatWithCMTimeSecond:currentPlayTime];
}

- (CMTime)getCMTimeWithPlayerProcessingValue:(CGFloat)value{
    CGFloat duration = [self getAudioTotalTime];
    int currentPlay = value*duration;
    CMTime seekToTime = CMTimeMake(currentPlay, 1);
    return seekToTime;
}

- (NSString *)getAudioTimeFormatWithCMTimeSecond:(int)songLength{
    
    if (songLength < 0) {
        return @"00:00";
    }
    int hours = songLength / 3600;
    int minutes = (songLength % 3600) / 60;
    int seconds = songLength % 60;
    NSString *lengthString = [[NSString alloc]init];
    if (!hours > 0) {
        lengthString = [NSString stringWithFormat:@"%02d:%02d",minutes, seconds];
    }else{
        lengthString = [NSString stringWithFormat:@"%d:%02d:%02d", hours, minutes, seconds];
    }
    
    return lengthString;
}

#pragma mark - Volume
/**
 get Volume
 */
+ (CGFloat)DLTAVPlayerGetVolumeValue{
    return [[self shareController]getVolumeValue];
}

- (CGFloat)getVolumeValue{
    
    float vol = [[AVAudioSession sharedInstance] outputVolume];
    NSLog(@"output volume: %1.2f dB", 20.f*log10f(vol+FLT_MIN));
    
    return vol;
    
}

/**
 setVolume
 */
+ (void)DLTAVPlayerSetVolumeOff{
    [[self shareController] setPlayerVolumeOff];
}
+ (void)DLTAVPlayerSetVolumeOn{
    [[self shareController] setPlayerVolumeOn];
}

+ (void)DLTAVPlayerSetVolumeWithValue:(CGFloat)value{
    [[self shareController] setPlayerVolumeWithValue:value];
}

- (void)setPlayerVolumeWithValue:(CGFloat)value{
    audioCurrentVolume = value;
    _avPlayer.volume = audioCurrentVolume;
    [MPMusicPlayerController applicationMusicPlayer].volume = value;
}

- (void)setPlayerVolumeOn{
    if (audioCurrentVolume <= 0) {
        audioCurrentVolume = audioVolumeSave;
    }else{
        audioVolumeSave = audioCurrentVolume;
        audioCurrentVolume = 0.0f;
    }
    
    _avPlayer.volume = audioCurrentVolume;
}

- (void)setPlayerVolumeOff{
    if (audioCurrentVolume > 0) {
        audioVolumeSave = audioCurrentVolume;
        audioCurrentVolume = 0.0;
    }else{
        audioCurrentVolume = audioVolumeSave;
    }
    _avPlayer.volume = audioCurrentVolume;
}


#pragma mark - audio effect
//================================= Play Pause With Audio Effect ===================================

- (void)PlayWithVolumeFadeIn{
    
    // flag for play a audio fail with 3 times
    static int i = 0;
    
    // check timePlaying Circle Is Over And Stop the audio
    BOOL isPlayingTimeCircleOver = [self checkPlayingTimeCircleOver];
    
    if (isPlayingTimeCircleOver) {
        NSLog(@"play With Volume Fadein Return Because Time Circle Playing Is Over");
        
        // set back timeEndPlaying
        timeEndPlaying = 0;
        kIsUserPauseAudio = YES;
        
        // delegate call back for pause avplayer
        [self delegateAVPlayerStateFire:DLTAVPlayerStatePause withErrorMessage:nil];
        return;
    }
    
    if (([self checkAVPlayerControllerIsPlaying] && !kStreamingSuccess) || kIsUserPauseAudio) {
        NSLog(@"play With Volume Fadein Return");
        return;
    }
    
    if (_avPlayer && CMTimeGetSeconds(_avPlayer.currentItem.duration) > 0 && i<kReconnectRetries){
        
        //1
        [self performSelector:@selector(doVolumeFadeInWithEffect:) withObject:nil afterDelay:(kDELAYTIME_BUFFERINGTOPLAY*i)];
        
        //set back playing sucess
        kStreamingSuccess = YES;
        
        //2
        // set i to 0 when streaming success
        i = 0 ;
        
        NSLog(@" do volume fadein %d",i);
        NSLog(@" Notification Play Fire");
        
        //check movie is playing and disable
        //        if ([MoviePlayerController moviePlayerIsPlaying] || [MoviePlayerController moviePlayerIsPausing]) {
        //            [MoviePlayerController moviePlayerStop];
        //        }
        
    }else{
        if (i == kReconnectRetries) {
            // the streaming song is get problem . So stop it absolutely
            // Pause AVPlayer
            
            NSLog(@"Notification Fire with Reconnect");
            // STREAMING ERROR FIRE
            // NOTIFICATION FIRE
            
            AVPlayerItem *playerItem = (AVPlayerItem *)_avPlayer.currentItem;
            [self delegateAVPlayerStateFire:DLTAVPlayerStateError withErrorMessage:playerItem.error];
            
            // set back flag count to 0
            i = 0;
            
        }else{
            // increase i for streaming fail three times
            i++;
            [self performSelector:@selector(doVolumeFadeInWithEffect:) withObject:nil afterDelay:(kDELAYTIME_BUFFERINGTOPLAY*i)];
        }
    }
}

- (void)doVolumeFadeInWithEffect:(BOOL)enable{
    
    if (![self checkAVPlayerControllerIsPlaying] && kIsUserPauseAudio == NO) {
        if (enable) {
            [_avPlayer play];
            [self doVolumeFadeIn];
        }else{
            // start play audio
            _avPlayer.volume = [self getVolumeValue];
            [_avPlayer play];
            [self.delegate DLTAVPlayer_StateChange:DLTAVPlayerStatePlaying withErrorMessage:nil];
        }
    }
    
    
}

- (void)doVolumeFadeIn{
    if ([self checkAVPlayerControllerIsPlaying]) {
        // if avplayer is playing do the volume fade in
        CGFloat audioVolume = 0;
        _avPlayer.volume = 0;
        if (audioVolume < [self getVolumeValue]) {
            _avPlayer.volume += 0.1;
            [self performSelector:@selector(doVolumeFadeIn) withObject:nil afterDelay:kDELAYTIME_AUDIOEFFECT];
        }else{
            // release timer
            [self timerRelease];
        }
    }
    //    }else{
    //        // if avplayer is not playing Retry to do volume fade in
    //         [self timerReplayAudioCreate];
    //    }
}

// Pause
- (void)PauseWithVolumeFadeOutEnable:(BOOL)enable{
    if ([self checkAVPlayerControllerIsPlaying]) {
        
        //2
        if (enable) {
            [self doVolumeFadeOutWithEffect];
        }else{
            [_avPlayer pause];
            
            // delegate pause call back
            [self delegateAVPlayerStateFire:DLTAVPlayerStatePause withErrorMessage:nil];
            
        }
    }
}

- (void)doVolumeFadeOutWithEffect{
    if (_avPlayer.volume > 0.25) {
        _avPlayer.volume -=0.25;
        [self performSelector:@selector(doVolumeFadeOutWithEffect) withObject:nil afterDelay:kDELAYTIME_AUDIOEFFECT];
    }else{
        [_avPlayer pause];
        [self delegateAVPlayerStateFire:DLTAVPlayerStatePause withErrorMessage:nil];
    }
}



#pragma mark - Alarm For Playing
- (NSInteger)timeSystemCurrentConvertToMinute{
    NSDate *date = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    NSInteger hour = [components hour];
    NSInteger minute = [components minute] + (hour*60);
    
    NSLog(@"current System Time %lu",(unsigned long)minute);
    return minute;
}

- (BOOL)checkPlayingTimeCircleOver{
    NSInteger currentSystemTime = [self timeSystemCurrentConvertToMinute];
    
    if (currentSystemTime >= timeEndPlaying && timeEndPlaying > 0) {
        NSLog(@"It's Over time for playing audio");
        return YES;
    }
    return NO;
}

#pragma mark - Check Player State
+ (BOOL)DLTAVPlayer_CheckAVPlayerControllerIsPlaying{
    return [[self shareController] checkAVPlayerControllerIsPlaying];
}

+ (BOOL)DLTAVPlayer_CheckAVPlayerControllerIsPausing{
    return [[self shareController] checkAVPlayerIsPausing];
}

+ (BOOL)DLTAVPlayer_CheckAVPlayerControllerIsStopped{
    return [[self shareController] checkAVPlayerControllerIsStopped];
}

- (BOOL)checkAVPlayerControllerIsPlaying{
    if (_avPlayer.rate > 0 && _avPlayer) {
        if (_avPlayer.error) {
            return NO;
        }
        return YES;
    }
    return NO;
}

- (BOOL)checkAVPlayerIsPausing{
    if (_avPlayer.rate == 0 && _avPlayer) {
        if (_avPlayer.error && kIsUserPauseAudio) {
            return NO;
        }
        return YES;
    }
    return NO;
}

- (BOOL)checkAVPlayerControllerIsStopped{
    if (_avPlayer == nil && _avPlayerItem == nil) {
        return YES;
    }
    return NO;
}

#pragma mark - AVPlayer Set Time Play LifeCircle
+ (void)DLTAVPlayerSetPlayingTimeCircleWithValue:(NSUInteger)value{
    [[self shareController] setPlayingTimeCircleWithValue:value];
}

- (void)setPlayingTimeCircleWithValue:(NSUInteger)value{
    if (value == 0) {
        timeEndPlaying = 0;
        return;
    }
    timeEndPlaying = ([self timeSystemCurrentConvertToMinute] + value);
    NSLog(@"Time to end Playing Audio minute convert %lu",(unsigned long)timeEndPlaying);
}

#pragma mark - AVSessionPlayer handle Interuption
/* handle when user playing song and get a phone call */
/* something has caused your audio session to be interrupted */
+ (void)beginInterruption {
    [[self shareController] doVolumeFadeOutWithEffect];
    NSLog(@"audioPlayerBeginInterruption");
}

/* endInterruptionWithFlags: will be called instead if implemented. */
+ (void)userEndInterruption:(NSNotification *)notification {
    //
    //    if ([[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionInterruptionTypeBegan]]) {
    //        NSLog(@"Interruption began!");
    //        [[self shareController] doVolumeFadeOut];
    //
    //    } else
    if([[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionInterruptionTypeEnded]]){
        NSLog(@"Interruption ended!");
        //Resume your audio
        [[self shareController] doVolumeFadeInWithEffect:YES];
    }
}

+ (void)userUnplugedHeadPhone:(NSNotification *)notification {
    NSLog(@"userUnplugedHeadPhone");
    
    NSDictionary *dictInfo = notification.userInfo;
    int changeResasonKey = [[dictInfo objectForKey:@"AVAudioSessionRouteChangeReasonKey"] intValue];
    
    if (changeResasonKey == 2) {
        kIsUserPauseAudio = NO;
        
        [[self shareController] delegateAVPlayerStateFire:DLTAVPlayerStatePlaying withErrorMessage:nil];
    }
}

#pragma mark - Delegate CallBack Fire
- (void)delegateAVPlayerStateFire:(DLTAVPlayerState)state withErrorMessage:(NSError *)errorResult{
    [[self delegate]DLTAVPlayer_StateChange:state withErrorMessage:errorResult];
}

- (void)delegateAVPlayerDidEndFire{
    [[self delegate] DLTAVPlayer_DidEndSongPlay];
}



// Play App In Background tutorial
/*
 add this code to app delegate
 - (void)applicationDidEnterBackground:(UIApplication *)application {
 // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
 // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
 
 if([[UIApplication sharedApplication]  respondsToSelector:@selector(beginReceivingRemoteControlEvents)])
 [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
 
 __block UIBackgroundTaskIdentifier task = 0;
 task=[application beginBackgroundTaskWithExpirationHandler:^{
 NSLog(@"Expiration handler called %f",[application backgroundTimeRemaining]);
 [application endBackgroundTask:task];
 task=UIBackgroundTaskInvalid;
 }];
 
 [AVAudioSession sharedInstance].delegate = self;
 [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayback error:nil];
 [[AVAudioSession sharedInstance] setActive: YES error: nil];
 
 [self becomeFirstResponder];
 
 }
 */


@end
