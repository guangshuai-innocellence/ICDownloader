//
//  ICDownloaderManager.h
//  ICDownloader
//
//  Created by guangshuai li on 21/3/2017.
//  Copyright © 2017 guangshuai li. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ICDownloader : NSObject<NSURLSessionDownloadDelegate,NSURLSessionDataDelegate>

- (instancetype)initWithConcurrentCount:(NSInteger)concurrentCount dstPath:(NSString *)dstPath;

//start downloading with md5-check
- (void)startDownloadWithUrlStringAndMD5Dic:(NSDictionary *)urlAndMD5Dic successBlock:(void(^)())successBlock failBlock:(void(^)())failBlock percentBlock:(void(^)(float totalPercent,NSString *currentfileName,float currentFilePersent))percentBlock;

//start downloading without md5-check
- (void)startDownloadWithUrlStringArray:(NSArray *)urlStringArray successBlock:(void(^)())successBlock failBlock:(void(^)())failBlock percentBlock:(void(^)(float totalPercent,NSString *currentfileName,float currentFilePersent))percentBlock;

- (void)cancelAllTasks;

@end
