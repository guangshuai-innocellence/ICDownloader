//
//  ICDownloaderManager.m
//  ICDownloader
//
//  Created by guangshuai li on 21/3/2017.
//  Copyright © 2017 guangshuai li. All rights reserved.
//

#import "ICDownloader.h"
#import "NSData+MD5Digest.h"

#define DEFAULT_CONCURRENT_COUNT    3
#define DST_FOLDER_NAME             @"ICDownloader"
#define TEMP_FOLODER_NAME           @"TempICDownloader"

@interface ICDownloader()
{
    //run downloading logic in a concurrent queue
    dispatch_queue_t _downloaderQueue;
    //use semaphore to control concurrent count
    dispatch_semaphore_t _semaphore;
    //use dispatch_group to deal with callback called after all the downloadings are done
    dispatch_group_t _dispatchGroup;
    
    //used for cancelling suspended task
    BOOL _isAllTaskCanceled;
    //used for deciding which completion block is called
    BOOL _isErrorOccured;
    //if the downloader is running
    BOOL _isDownloading;
    //whether to remove wrong file by checking md5
    BOOL _isMD5CheckNeeded;
    
    //folder path for final file
    NSString *_dstFolderPath;
    //folder path for resuming data
    NSString *_tempFolderPath;
    
    //progress of downloading
    void (^_percentBlock)(float totalPercent,NSString *currentfileName,float currentFilePersent);
    
    //running task array
    NSMutableArray *_runningTasksArray;
    
    NSMutableDictionary *_filteredUrlAndMD5Dic;
    //use this dic to calculate percent of downloading
    NSMutableDictionary *_totalPercentDic;
}

@end

@implementation ICDownloader

#pragma mark - Init

- (instancetype)init{
    self = [super init];
    if(self){
        [self initParams:DEFAULT_CONCURRENT_COUNT dstPath:nil];
    }
    return self;
}

- (instancetype)initWithConcurrentCount:(NSInteger)concurrentCount dstPath:(NSString *)dstPath{
    self = [super init];
    if(self){
        [self initParams:concurrentCount dstPath:dstPath];
    }
    return self;
}

- (void)initParams:(NSInteger)concurrentCount dstPath:(NSString *)dstPath{
    _downloaderQueue = dispatch_queue_create("com.Kings.ICDownloader", DISPATCH_QUEUE_CONCURRENT);
    _semaphore = dispatch_semaphore_create(concurrentCount);
    _dispatchGroup = dispatch_group_create();
    
    _runningTasksArray = [[NSMutableArray alloc] init];
    _filteredUrlAndMD5Dic = [[NSMutableDictionary alloc] init];
    _totalPercentDic = [[NSMutableDictionary alloc] init];
    
    NSString *homePath = NSHomeDirectory();
    if(dstPath){
        _dstFolderPath = dstPath;
    }else{
        _dstFolderPath = [NSString stringWithFormat:@"%@/Library/Caches/%@",homePath,DST_FOLDER_NAME];
    }
    _tempFolderPath = [NSString stringWithFormat:@"%@/Library/Caches/%@",homePath,TEMP_FOLODER_NAME];
}

#pragma mark - Entrance Function

- (void)startDownloadWithUrlStringArray:(NSArray *)urlStringArray successBlock:(void(^)())successBlock failBlock:(void(^)())failBlock percentBlock:(void(^)(float percent,NSString *currentTaskUrl,float currentTaskPersent))percentBlock{
    
    NSMutableDictionary *urlAndMD5Dic = [[NSMutableDictionary alloc] init];
    for(NSString *urlString in urlStringArray){
        [urlAndMD5Dic setObject:@"" forKey:urlString];
    }
    
    [self startDownloadWithUrlStringAndMD5Dic:urlAndMD5Dic successBlock:successBlock failBlock:failBlock percentBlock:percentBlock isMD5CheckNeeded:NO];
}

- (void)startDownloadWithUrlStringAndMD5Dic:(NSDictionary *)urlAndMD5Dic successBlock:(void(^)())successBlock failBlock:(void(^)())failBlock percentBlock:(void(^)(float percent,NSString *currentTaskUrl,float currentTaskPersent))percentBlock{
    
    [self startDownloadWithUrlStringAndMD5Dic:urlAndMD5Dic successBlock:successBlock failBlock:failBlock percentBlock:percentBlock isMD5CheckNeeded:YES];
}

- (void)cancelAllTasks{
    dispatch_async(_downloaderQueue, ^{
        
        _isAllTaskCanceled = YES;
        
        for(NSURLSessionDownloadTask *task in _runningTasksArray){
            [task cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
                NSString *localPath = [self tempFilePathFromUrlString:task.response.URL.absoluteString];
                [resumeData writeToFile:localPath atomically:YES];
            }];
        }
        
        //need signal one more time to set semaphore to 0
        dispatch_semaphore_signal(_semaphore);
        
        _isDownloading = NO;
    });
}

#pragma mark - Private Function

- (void)startDownloadWithUrlStringAndMD5Dic:(NSDictionary *)urlAndMD5Dic successBlock:(void(^)())successBlock failBlock:(void(^)())failBlock percentBlock:(void(^)(float percent,NSString *currentTaskUrl,float currentTaskPersent))percentBlock isMD5CheckNeeded:(BOOL)isMD5CheckNeeded{
    
    if(_isDownloading){
        NSLog(@"Download is running already,please cancel current operation and try again!");
        return;
    }
    
    dispatch_async(_downloaderQueue, ^{
        _isDownloading = YES;
        _isAllTaskCanceled = NO;
        _isErrorOccured = NO;
        
        _isMD5CheckNeeded = isMD5CheckNeeded;
        
        _percentBlock = percentBlock;
        
        [_runningTasksArray removeAllObjects];
        [_filteredUrlAndMD5Dic removeAllObjects];
        [_totalPercentDic removeAllObjects];
        
        //create foloder
        if(![[NSFileManager defaultManager] fileExistsAtPath:_dstFolderPath]){
            NSError *error;
            [[NSFileManager defaultManager] createDirectoryAtPath:_dstFolderPath withIntermediateDirectories:YES attributes:nil error:&error];
         
            NSAssert(error==nil, @"Create Destination Floder Error!");
        }
        
        if(![[NSFileManager defaultManager] fileExistsAtPath:_tempFolderPath]){
            [[NSFileManager defaultManager] createDirectoryAtPath:_tempFolderPath withIntermediateDirectories:YES attributes:nil error:nil];
        }
        
        NSArray *downloadUrlStringArray = [urlAndMD5Dic allKeys];
        
        //filter download url array
        for(NSString *urlString in downloadUrlStringArray){
            
            BOOL isFileValid = [self isDstFileValid:urlString MD5:[urlAndMD5Dic objectForKey:urlString]];
            
            if(!isFileValid){
                NSString *dstPath = [self dstFilePathFromUrlString:urlString];
                //remove the wrong file
                [self removeFileAtPath:dstPath];
                
                //add to download array
                [_filteredUrlAndMD5Dic setObject:urlAndMD5Dic[urlString] forKey:urlString];
            }
        }
        NSArray *filteredUrlArray = [_filteredUrlAndMD5Dic allKeys];
        
        for (NSString *urlString in filteredUrlArray) {
            NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
            NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
            NSURLSessionDownloadTask *sessionDownloadTask;
            
            NSString *tempPath = [self tempFilePathFromUrlString:urlString];
            BOOL isParticialDataExist = [[NSFileManager defaultManager] fileExistsAtPath:tempPath];
            
            if(isParticialDataExist){
                NSData *particialData = [[NSData alloc] initWithContentsOfFile:tempPath];
                sessionDownloadTask = [session downloadTaskWithResumeData:particialData];
            }else{
                NSURL *url = [NSURL URLWithString:urlString];
                sessionDownloadTask = [session downloadTaskWithURL:url];
            }
            //wait semaphore here
            dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
            
            //all the rest task will not be resumed
            if(_isAllTaskCanceled){
                break;
            }
            NSLog(@"%@ will be resumed.",urlString);
            dispatch_group_enter(_dispatchGroup);
            [sessionDownloadTask resume];
            [_runningTasksArray addObject:sessionDownloadTask];
        }
        
        dispatch_group_notify(_dispatchGroup, dispatch_get_main_queue(), ^(){
            
            _isDownloading = NO;
            
            if(!_isAllTaskCanceled && !_isErrorOccured){
                successBlock();
            }else{
                failBlock();
            }
        });
    });
}

#pragma mark - URL Delegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if(error != nil){
        NSLog(@"Error is %@",error);
        _isErrorOccured = YES;
    }
    [_runningTasksArray removeObject:task];
    
    dispatch_group_leave(_dispatchGroup);
    dispatch_semaphore_signal(_semaphore);
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location{
    
    NSString *localPath = [self dstFilePathFromUrlString:downloadTask.response.URL.absoluteString];
    NSString *urlString = downloadTask.response.URL.absoluteString;
    
    //move file
    NSError *error;
    [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:localPath] error:&error];
    if(error){
        NSLog(@"Error is %@",error);
    }
    
    BOOL isFileValid = [self isDstFileValid:urlString MD5:[_filteredUrlAndMD5Dic objectForKey:urlString]];
    if(!isFileValid){
        [self removeFileAtPath:localPath];
    }
    
    //remove temp data
    NSString *tempPath = [self tempFilePathFromUrlString:downloadTask.response.URL.absoluteString];
    if([[NSFileManager defaultManager] fileExistsAtPath:tempPath]){
        NSError *delError;
        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:&delError];
        if(delError){
            NSLog(@"Error is %@",delError);
        }
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite{
    
    //need to use synchronized to keep _totalPercentDic thread safe
    @synchronized (self) {
        float particalPersent = totalBytesWritten/(totalBytesExpectedToWrite*1.0);
        [_totalPercentDic setObject:[NSNumber numberWithFloat:particalPersent] forKey:downloadTask.response.URL.absoluteString];
        
        NSUInteger totalDownloadCount = [_filteredUrlAndMD5Dic allKeys].count;
        float weight = 1.0/totalDownloadCount;
        NSArray *valueArray = [_totalPercentDic allValues];
        
        float totalPersent = 0;
        for(NSNumber *number in valueArray){
            float value = number.floatValue;
            totalPersent += (value * weight);
        }
        if(_percentBlock)
            _percentBlock(totalPersent,downloadTask.response.URL.absoluteString.lastPathComponent,particalPersent);
    };
}

#pragma mark - Tools Function

- (BOOL)isDstFileValid:(NSString *)urlString MD5:(NSString *)md5FromServer{
    
    NSString *dstPath = [self dstFilePathFromUrlString:urlString];
    
    if([[NSFileManager defaultManager] fileExistsAtPath:dstPath]){
        
        if(_isMD5CheckNeeded){
            if(md5FromServer != nil){
                NSData *fileData = [[NSData alloc] initWithContentsOfFile:dstPath];
                NSString *md5Calculated = [fileData MD5HexDigest];
                if([md5FromServer isEqualToString:md5Calculated]){
                    return YES;
                }else{
                    return NO;
                }
            }else{
                return NO;
            }
        }else{
            //do not need md5 check
            return YES;
        }
    }else{
        return NO;
    }
}

- (void)removeFileAtPath:(NSString *)filePath{
    if([[NSFileManager defaultManager] fileExistsAtPath:filePath]){
        NSError *error;
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        if(error){
            NSLog(@"Error is : %@",error);
        }
    }
}

- (NSString *)dstFilePathFromUrlString:(NSString *)urlString{
    NSString *fileName = urlString.lastPathComponent;
    if(fileName == nil || [fileName isEqualToString:@""]){
        NSLog(@"Error url");
        return @"";
    }
    NSString *localFilePath = [NSString stringWithFormat:@"%@/%@",_dstFolderPath,fileName];
    return localFilePath;
}

- (NSString *)tempFilePathFromUrlString:(NSString *)urlString{
    NSString *fileName = urlString.lastPathComponent;
    if(fileName == nil || [fileName isEqualToString:@""]){
        NSLog(@"Error url");
        return @"";
    }
    NSString *localFilePath = [NSString stringWithFormat:@"%@/%@",_tempFolderPath,fileName];
    return localFilePath;
}


@end
