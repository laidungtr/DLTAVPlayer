//
//  ViewController.m
//  AVPlayerSample
//
//  Created by ttiamap on 04/01/2016.
//  Copyright © 2016 ttiamap. All rights reserved.
//

#import "ViewController.h"
#import "DLTAVPlayer.h"

@interface ViewController ()<DLTAVPlayerDelegate>

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [DLTAVPlayer shareController].delegate = (id)self;
    
    NSString *stringStreaming = @"http://st02.freesocialmusic.com/mp3/2016/01/04/1451900136-01-propaganda.mp3";
    
    
    [DLTAVPlayer DLTAVPlayer_BackgroundViewPlayerInitWithImageLink:nil orImageArtWork:[UIImage imageNamed:@"avatar.png"] songName:@"i dont know" singerName:@"not me"];
    [DLTAVPlayer DLTAVPlayer_PlayAudioWithStreamingLink:stringStreaming imageArtWorkLink:nil orImageArtWork:nil];
}

- (void)DLTAVPlayer_StateChange:(DLTAVPlayerState)state withErrorMessage:(NSError *)errorResult{
    
    if (state == DLTAVPlayerStatePlaying) {
        NSLog(@"is playing");
    }else if (state == DLTAVPlayerStatePause){
        NSLog(@"is pausing");
    }else if (state == DLTAVPlayerStateError){
        NSLog(@"Error : %@",[errorResult description]);
    }
}

- (void)DLTAVPlayer_DidEndSongPlay{
    NSLog(@"Song Play did end");
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
