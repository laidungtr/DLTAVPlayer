//
//  DLTAVPlayer.h
//  AVPlayerSample
//
//  Created by ttiamap on 04/01/2016.
//  Copyright © 2016 ttiamap. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "AppDelegate.h"

typedef NS_ENUM(NSUInteger, DLTAVPlayerState){
    DLTAVPlayerStatePlaying = 0,
    DLTAVPlayerStatePause = 1,
    DLTAVPlayerStateBuffering = 2,
    DLTAVPlayerStateError = 3
};

@protocol DLTAVPlayerDelegate <NSObject>

- (void)DLTAVPlayer_StateChange:(DLTAVPlayerState)state withErrorMessage:(NSError *)errorResult;
- (void)DLTAVPlayer_DidEndSongPlay;

@end

@interface DLTAVPlayer : NSObject

#pragma mark - Delegate
@property(nonatomic, weak) id <DLTAVPlayerDelegate> delegate;

// this is status for user tap play or pause
// NO for Pause
// YES for Playing
@property(nonatomic, assign) BOOL playingStatus;

/**
 Singleton
 */
+ (DLTAVPlayer *)shareController;

/**
 add this code to your applicationDidEnterBackground (AppDelegate) for register to play audio in background
 */
+ (void)DLTAVPlayerRegisterAudioInBackgroundMode:(UIApplication *)application;


#pragma mark - Streaming Audio
/**
 stream Audio Online With Streaming link
 */
+ (void)DLTAVPlayer_PlayAudioWithStreamingLink:(NSString *)linkAudio;

/**
 playing with bundle local file audio
 */
+ (void)DLTAVPlayer_PlayingLocalAudioFileWithLink:(NSString *)linkAudio;

#pragma mark - Player View At Lock Screen

/**
 AVPlayer Set player play in Background Mode View
 */
+ (void)DLTAVPlayer_BackgroundViewPlayerInitWithImageLink:(NSString *)linkArtWork orImageArtWork:(UIImage *)imageArtWork songName:(NSString *)stringSongName singerName:(NSString *)stringSingerName;

#pragma mark - Volume
/**
 set AVPlyer Volume Status Off
 */
+ (void)DLTAVPlayerSetVolumeOff;

/**
 set AVPlyer Volume Status Off
 */
+ (void)DLTAVPlayerSetVolumeOn;

/**
 set AVPlyer Volume Value
 */
+ (void)DLTAVPlayerSetVolumeWithValue:(CGFloat)value;

/**
 get AVPlyer Volume Value
 */
+ (CGFloat)DLTAVPlayerGetVolumeValue;

#pragma mark - AVPlayer Controller Play, Pause , Resume , Stop , Seeking
/**
 Play AVPlayer Audio if it pausing
 if effect Enable == YES : the volume play with volume Increase (fade in Effect)
 if effect Enable == NO : the volume playing normally
 */
+ (void)DLTAVPlayerPlayAudioFadeInEffect:(BOOL)enable;


/**
 Pause AVPlayer Audio
 if effect Enable == YES : the volume play with volume decrease (fade out Effect)
 if effect Enable == NO : the volume pause normally
 */
+ (void)DLTAVPlayerPauseAudioFadeOutEffect:(BOOL)enable;

/**
 Stop AVPlayer Audio. It Remove All Obsever And set AVPlayer to Nil
 */
+ (void)DLTAVPLayerStopAudio;
+ (void)DLTAVPLayerStopAudioWithSongChange;

/**
 Seek AVPlayer Audio To CurrentValue
 */
+ (void)DLTAVplayerSeekToProcessingValue:(CGFloat)value;

#pragma mark - Get AVPlayer Audio Duration And Current PlayTime
// AVPlayer Getting
+ (CGFloat)DLTAVPlayerGetAudioProcessingValue;
+ (CGFloat)DLTAVPlayerGetAudioDurationFloatValue;

+ (NSString *)DLTAVPlayerGetAudioDurationString;
+ (NSString *)DLTAVPlayerGetAudioCurrentPlayTimeString;

#pragma mark - Check Player State
+ (BOOL)DLTAVPlayer_CheckAVPlayerControllerIsPlaying;
+ (BOOL)DLTAVPlayer_CheckAVPlayerControllerIsPausing;
+ (BOOL)DLTAVPlayer_CheckAVPlayerControllerIsStopped;

#pragma mark - AVPlayer Set Alarm for playing song list in duration
/**
 set time playing audio for avplayer
 Example:
 current time is 01:00, value is 120;
 => timeEndPlaying = 180;
 
 so the start playing time is 120
 when start playing time >= timeEndPlaying => Pausing The Audio;
 */
+ (void)DLTAVPlayerSetPlayingTimeCircleWithValue:(NSUInteger)value;

@end
