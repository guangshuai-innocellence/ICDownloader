//
//  ViewController.m
//  ICDownloader
//
//  Created by guangshuai li on 20/3/2017.
//  Copyright © 2017 guangshuai li. All rights reserved.
//

#import "ViewController.h"
#import "ICDownloader.h"

#define CELL_IDENTIFIER @"COMMON_CELL"

@interface ViewController (){
 
    IBOutlet UILabel *percentLabel;
    IBOutlet UITableView *_tableView;
    
    NSArray *fileNameArray;
    NSString *dstFolderPath;
    
    ICDownloader *downloader;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"home is %@",NSHomeDirectory());
    
    NSString *homePath = NSHomeDirectory();
    dstFolderPath = [NSString stringWithFormat:@"%@/Library/Caches/%@",homePath,@"ICDownloader"];
    downloader = [[ICDownloader alloc] initWithConcurrentCount:2 dstPath:dstFolderPath];
}

- (IBAction)startTestWithMD5Check:(id)sender{
    
    NSDictionary *downloadDic = @{@"http://sbslive.cnrmobile.com/storage/storage2/18/01/18/46eeb50b3f21325a6f4bd0e8ba4d2357.3gp":@"",
                                  @"http://sbslive.cnrmobile.com/storage/storage2/51/34/18/3e59db9bb51802c2ef7034793296b724.3gp":@"b142216c02caf2f82bb2afdcf06faf92",
                                  @"http://sbslive.cnrmobile.com/storage/storage2/05/61/05/f2609b3b964bbbcfb3e3703dde59a994.3gp":@"",
                                  @"http://sbslive.cnrmobile.com/storage/storage2/28/11/28/689f8a52fbef0fbbf51db19ee3276ae5.3gp":@"965594f2adc75c212e8c0ec4877d9308",
                                  @"http://sbslive.cnrmobile.com/storage/storage2/71/28/05/512551c6fcf71615ad5f8ae9bd524069.3gp":@""};
    
    
    [downloader startDownloadWithUrlStringAndMD5Dic:downloadDic  successBlock:^{
        NSLog(@"=== Downloading Successed ===");
        fileNameArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dstFolderPath error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [_tableView reloadData];
        });
    } failBlock:^{
        NSLog(@"=== Downloading Failed ===");
    } percentBlock:^(float percent, NSString *fileName, float currentTaskPersent) {
        
        NSLog(@" --- %@     %0.2f",fileName,currentTaskPersent);
        dispatch_async(dispatch_get_main_queue(), ^{
            percentLabel.text = [NSString stringWithFormat:@"%0.2f",percent];
        });
    }];
}

- (IBAction)startTestWithoutMD5Check:(id)sender{
    
    NSArray *downloadArray = @[@"http://sbslive.cnrmobile.com/storage/storage2/18/01/18/46eeb50b3f21325a6f4bd0e8ba4d2357.3gp", @"http://sbslive.cnrmobile.com/storage/storage2/51/34/18/3e59db9bb51802c2ef7034793296b724.3gp", @"http://sbslive.cnrmobile.com/storage/storage2/05/61/05/f2609b3b964bbbcfb3e3703dde59a994.3gp", @"http://sbslive.cnrmobile.com/storage/storage2/28/11/28/689f8a52fbef0fbbf51db19ee3276ae5.3gp", @"http://sbslive.cnrmobile.com/storage/storage2/71/28/05/512551c6fcf71615ad5f8ae9bd524069.3gp"];
    
    [downloader startDownloadWithUrlStringArray:downloadArray successBlock:^{
        NSLog(@"=== Downloading Successed ===");
        
        fileNameArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dstFolderPath error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [_tableView reloadData];
        });
        
    } failBlock:^{
        NSLog(@"=== Downloading Failed ===");
    } percentBlock:^(float percent, NSString *fileName, float currentTaskPersent) {
        NSLog(@" --- %@     %0.2f",fileName,currentTaskPersent);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            percentLabel.text = [NSString stringWithFormat:@"%0.2f",percent];
        });
    }];
}

- (IBAction)cancel:(id)sender{
    [downloader cancelAllTasks];
}

- (IBAction)deleteFiles:(id)sender{
    [[NSFileManager defaultManager] removeItemAtPath:dstFolderPath error:nil];
    fileNameArray = nil;
    [_tableView reloadData];
}

#pragma mark - UITableView Delegate

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CELL_IDENTIFIER forIndexPath:indexPath];
    cell.textLabel.text = [fileNameArray objectAtIndex:indexPath.row];
    return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return [fileNameArray count];
}

@end
